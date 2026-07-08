import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_parser_service.dart';

/// Test Tier 1 (DB murni) untuk fitur eksperimental "Tempel Pesanan" —
/// sisi kasir yang membaca teks pesanan hasil Katalog Pesanan (HTML) dan
/// mencocokkannya balik ke data produk lokal.

Future<String> _addProduct(
  AppDatabase db, {
  required String name,
  required int price,
  int costPrice = 0,
  bool isActive = true,
  String? parentProductId,
  int unitTypeId = 2, // Pcs
}) async {
  final productId = 'p-${DateTime.now().microsecondsSinceEpoch}-$name';
  final unitId = '$productId-u';
  await db.into(db.products).insert(ProductsCompanion.insert(
        id: productId,
        name: name,
        isActive: Value(isActive),
        parentProductId: Value(parentProductId),
      ));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId,
        productId: productId,
        unitTypeId: Value(unitTypeId),
        isBaseUnit: const Value(true),
      ));
  await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: '$unitId-t1',
        productUnitId: unitId,
        minQty: const Value(1),
        price: price,
        costPrice: Value(costPrice),
      ));
  return productId;
}

Future<String> _unitIdOf(AppDatabase db, String productId) async {
  final u = await (db.select(db.productUnits)
        ..where((t) => t.productId.equals(productId)))
      .getSingle();
  return u.id;
}

void main() {
  test(
      'teks tanpa kode mesin (#PSN:) dilaporkan hasMachineCode=false, '
      'bukan error', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final result =
        await OrderParserService.parse(db: db, text: 'halo, ada gula?');
    expect(result.hasMachineCode, isFalse);
    expect(result.items, isEmpty);
    await db.close();
  });

  test(
      'parse berhasil: item cocok ke DB lokal dengan harga LIVE dari DB, '
      'bukan angka di teks pesanan (katalog terkirim bisa basi)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Gula Pasir', price: 15000);
    final unitId = await _unitIdOf(db, productId);

    // Harga di DB naik SETELAH katalog HTML dikirim ke pelanggan — teks
    // pesanan yang ditempel tidak membawa info harga sama sekali, murni
    // productUnitId + qty.
    await db.update(db.priceTiers).write(const PriceTiersCompanion(
          price: Value(17000),
        ));

    final text = 'Nama: Budi\nHP: 0812\n#PSN:$unitId=3;';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.hasMachineCode, isTrue);
    expect(result.items, hasLength(1));
    expect(result.items.first.qty, 3);
    expect(result.items.first.price, 17000,
        reason: 'harga harus di-resolve ulang dari DB saat parse, bukan '
            'dari harga lama saat katalog dibuat');
    expect(result.customerName, 'Budi');
    expect(result.customerPhone, '0812');
    await db.close();
  });

  test('unitId dobel di kode mesin digabung qty-nya, bukan jadi 2 baris',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Minyak', price: 32000);
    final unitId = await _unitIdOf(db, productId);

    final text = '#PSN:$unitId=1;$unitId=2;';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.items, hasLength(1),
        reason: 'unitId sama tidak boleh jadi baris keranjang terpisah');
    expect(result.items.first.qty, 3);
    await db.close();
  });

  test(
      'unitId yang sudah dihapus/dinonaktifkan sejak katalog dibuat masuk '
      'notFound, tidak menggagalkan baris valid lain', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Sabun', price: 5000);
    final unitId = await _unitIdOf(db, productId);
    await _addProduct(db, name: 'Dihapus', price: 1000, isActive: false);
    final ghostUnitId = await _unitIdOf(
        db,
        (await (db.select(db.products)..where((t) => t.name.equals('Dihapus')))
                .getSingle())
            .id);

    final text = '#PSN:$unitId=1;$ghostUnitId=1;unit-tak-ada=1;';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.items, hasLength(1));
    expect(result.items.first.productName, 'Sabun');
    expect(result.notFound, containsAll([ghostUnitId, 'unit-tak-ada']));
    await db.close();
  });

  test(
      'baris Nama/HP bertanda "-" (fallback template saat pelanggan tidak '
      'isi field) diperlakukan sebagai kosong; baris Catatan yang tidak ada '
      'sama sekali (template melewatkannya bila kosong) juga null', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Beras', price: 65000);
    final unitId = await _unitIdOf(db, productId);

    final text = 'Nama: -\nHP: -\n#PSN:$unitId=1;';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.customerName, isNull);
    expect(result.customerPhone, isNull);
    expect(result.note, isNull);
    await db.close();
  });

  test(
      'varian ikut ditandai isVariant+parentProductId agar keranjang bisa '
      'menjaga invariant stok induk', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final parentId = await _addProduct(db, name: 'Pop Ice', price: 2000);
    final variantId = await _addProduct(db,
        name: 'Coklat', price: 2500, parentProductId: parentId);
    final variantUnitId = await _unitIdOf(db, variantId);

    final text = '#PSN:$variantUnitId=2;';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.items.first.isVariant, isTrue);
    expect(result.items.first.parentProductId, parentId);
    await db.close();
  });
}
