import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Dilaporkan user (25 Juli): "membuat dua produk dengan barcode yang sama,
/// dan itu lolos". Yang SEBENARNYA terjadi lebih buruk dari sekadar lolos —
/// `saveProduct` dulu menjalankan `DELETE ... WHERE barcode = value` polos
/// untuk menghindari `UNIQUE(barcode)`, jadi produk kedua **MENCURI** barcode
/// dari produk pertama tanpa error apa pun: produk pertama jadi tidak bisa
/// di-scan, dan scan kode itu di kasir menagih produk yang SALAH.
///
/// Sekarang bentrok lintas-produk (produk lain masih AKTIF) ditolak lewat
/// [BarcodeConflictException] & seluruh transaksi di-rollback. Dua kasus
/// reuse yang SAH tetap harus jalan (diuji di bawah): produk yang sudah
/// dinonaktifkan, dan baris milik produk itu sendiri.
void main() {
  Future<void> saveWithBarcode(
    AppDatabase db,
    String pid,
    String barcode, {
    String? barcodeRowId,
    bool isPrimary = true,
  }) =>
      db.saveProduct(
        product: ProductsCompanion.insert(id: pid, name: 'Produk $pid'),
        units: [
          ProductUnitsCompanion.insert(
              id: '$pid-u', productId: pid, isBaseUnit: const Value(true)),
        ],
        tiersByUnitTempId: const {},
        barcodesByUnitTempId: {
          '$pid-u': [
            ProductBarcodesCompanion.insert(
              id: barcodeRowId ?? '$pid-bc',
              productUnitId: '$pid-u',
              barcode: barcode,
              isPrimary: Value(isPrimary),
            ),
          ],
        },
      );

  test(
      'barcode sudah dipakai produk lain yang AKTIF -> simpan DITOLAK, '
      'barcode produk pertama TIDAK tersentuh', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await saveWithBarcode(db, 'A', '8991234567890');

    await expectLater(
      () => saveWithBarcode(db, 'B', '8991234567890'),
      throwsA(isA<BarcodeConflictException>()),
    );

    // Produk A masih memegang barcode-nya — inti bug lamanya.
    final aBarcodes = await db.getProductBarcodes('A-u');
    expect(aBarcodes.map((b) => b.barcode).toList(), ['8991234567890'],
        reason: 'barcode produk lain TIDAK boleh dicuri/dihapus diam-diam');

    // Scan mengarah ke A, bukan B.
    final hit = await db.lookupBarcode('8991234567890');
    expect(hit?.productUnitId, 'A-u');

    // Rollback total: B tidak boleh tersimpan setengah jalan.
    final b = await (db.select(db.products)..where((t) => t.id.equals('B')))
        .getSingleOrNull();
    expect(b, isNull,
        reason: 'seluruh transaksi saveProduct harus di-rollback');
  });

  test('pesan error menyebut nama produk pemegang barcode-nya', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'A', name: 'Indomie Goreng'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'A-u', productId: 'A', isBaseUnit: const Value(true)));
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
          id: 'A-bc',
          productUnitId: 'A-u',
          barcode: '8991234567890',
          isPrimary: const Value(true),
        ));

    try {
      await saveWithBarcode(db, 'B', '8991234567890');
      fail('seharusnya melempar BarcodeConflictException');
    } on BarcodeConflictException catch (e) {
      expect(e.productName, 'Indomie Goreng');
      expect(e.barcode, '8991234567890');
      expect(e.toString(), contains('Indomie Goreng'),
          reason: 'user harus tahu produk MANA yang bentrok, bukan cuma '
              '"UNIQUE constraint failed"');
    }
  });

  test(
      'KASUS SAH 1: produk pemegang sudah dinonaktifkan -> barcode boleh '
      'dipakai produk baru', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await saveWithBarcode(db, 'A', '8991234567890');
    await db.deactivateProduct('A'); // melepas barcode (rename RELEASED:)

    await saveWithBarcode(db, 'B', '8991234567890');

    final hit = await db.lookupBarcode('8991234567890');
    expect(hit?.productUnitId, 'B-u',
        reason: 'reuse setelah produk lama dinonaktifkan harus tetap boleh');
  });

  test(
      'KASUS SAH 2: barcode dipegang produk ITU SENDIRI sbg alias '
      '(isPrimary=false, ditulis sinkron harga) -> boleh jadi barcode utama',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await saveWithBarcode(db, 'A', '1111111111111');
    // Alias non-primary utk unit yang SAMA, spt yang ditulis PriceMatchService.
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
          id: 'A-alias',
          productUnitId: 'A-u',
          barcode: '8991234567890',
          isPrimary: const Value(false),
        ));

    // Owner mengetik nilai alias itu sbg barcode utama produk yang sama.
    await saveWithBarcode(db, 'A', '8991234567890', barcodeRowId: 'A-bc2');

    final hit = await db.lookupBarcode('8991234567890');
    expect(hit?.productUnitId, 'A-u');
    expect(hit?.isPrimary, isTrue,
        reason: 'barcode milik produk sendiri harus bisa dipromosikan tanpa '
            'dianggap bentrok');
  });

  test(
      'KASUS SAH 3: menyimpan ulang produk yang sama dgn barcode yang sama '
      '(edit biasa) tetap jalan, tidak menuduh diri sendiri bentrok',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await saveWithBarcode(db, 'A', '8991234567890');
    await saveWithBarcode(db, 'A', '8991234567890'); // simpan lagi

    final aBarcodes = await db.getProductBarcodes('A-u');
    expect(aBarcodes.length, 1, reason: 'tidak menumpuk baris duplikat');
    expect(aBarcodes.single.barcode, '8991234567890');
  });
}
