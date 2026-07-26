import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Dilaporkan user 25 Juli: produk "Amplop" punya 2 barcode berlabel
/// "Primer" sekaligus, padahal form Edit Produk cuma punya 1 field Barcode.
/// Akar masalah: `restoreFromDump` (fitur restore backup) menimpa SELURUH DB
/// lokal VERBATIM dari file backup TANPA cek invarian apa pun — device host
/// pernah restore backup FULL dari device klien yang product_barcodes-nya
/// sudah basi akibat bug orphan-cleanup sinkron (fix `6455b9a`, lihat
/// `orphan_master_data_sync_test.dart`), jadi duplikatnya ikut terbawa
/// mentah-mentah. `findMasterDataDuplicates` mendeteksi kelas masalah ini di
/// 3 tabel yang rentan (product_barcodes/price_tiers/alt_prices).
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> seedProduct() async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Amplop'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
  }

  test('tidak ada temuan di database bersih (tanpa duplikat)', () async {
    await seedProduct();
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000));
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
        id: 'bc1',
        productUnitId: 'u1',
        barcode: '68888602',
        isPrimary: const Value(true)));

    expect(await db.findMasterDataDuplicates(), isEmpty);
  });

  test(
      'mendeteksi 2 barcode Primer sekaligus utk satu satuan (skenario '
      'dilaporkan user persis)', () async {
    await seedProduct();
    // Simulasikan hasil restore backup verbatim: 2 baris barcode Primer utk
    // unit yang sama — tidak lewat saveProduct (yang akan mencegah ini),
    // langsung raw insert spt restoreFromDump.
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
        id: 'bc1',
        productUnitId: 'u1',
        barcode: '68888602',
        isPrimary: const Value(true)));
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
        id: 'bc2',
        productUnitId: 'u1',
        barcode: '09130982',
        isPrimary: const Value(true)));

    final dupes = await db.findMasterDataDuplicates();
    expect(dupes, hasLength(1));
    expect(dupes.single.productName, 'Amplop');
    expect(dupes.single.table, 'product_barcodes');
    expect(dupes.single.detail, contains('2 barcode'));
  });

  test('mendeteksi tier harga dobel di qty yang sama', () async {
    await seedProduct();
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 't1', productUnitId: 'u1', minQty: const Value(1), price: 5000));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 't2', productUnitId: 'u1', minQty: const Value(1), price: 4500));

    final dupes = await db.findMasterDataDuplicates();
    expect(dupes, hasLength(1));
    expect(dupes.single.table, 'price_tiers');
  });

  test('mendeteksi Harga Lain dgn label sama dobel', () async {
    await seedProduct();
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'ap1', productUnitId: 'u1', label: 'Grosir', price: 4000));
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'ap2', productUnitId: 'u1', label: 'Grosir', price: 3800));

    final dupes = await db.findMasterDataDuplicates();
    expect(dupes, hasLength(1));
    expect(dupes.single.table, 'alt_prices');
    expect(dupes.single.detail, contains('Grosir'));
  });

  test(
      'menyimpan ulang produk lewat saveProduct (spt tombol Simpan Produk) '
      'merapikan barcode dobel jadi 1 baris', () async {
    await seedProduct();
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
        id: 'bc1',
        productUnitId: 'u1',
        barcode: '68888602',
        isPrimary: const Value(true)));
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
        id: 'bc2',
        productUnitId: 'u1',
        barcode: '09130982',
        isPrimary: const Value(true)));
    expect(await db.findMasterDataDuplicates(), hasLength(1));

    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Amplop'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: const {},
      barcodesByUnitTempId: {
        'u1': [
          ProductBarcodesCompanion.insert(
              id: 'bc3',
              productUnitId: 'u1',
              barcode: '68888602',
              isPrimary: const Value(true)),
        ],
      },
    );

    expect(await db.findMasterDataDuplicates(), isEmpty);
    final remaining = await db.getProductBarcodes('u1');
    expect(remaining, hasLength(1));
    expect(remaining.single.barcode, '68888602');
  });
}
