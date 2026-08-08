import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_parse_diagnostics.dart';
import 'package:the_pos/core/services/order_parser_service.dart';

/// Item 55 — logging diagnostik SEMENTARA untuk investigasi bug "Tempel
/// Pesanan pegawai tidak dapat produk". Test ini HANYA memastikan
/// instrumentasinya sendiri jalan benar (mencatat titik gagal yang tepat) —
/// BUKAN test regresi bug utamanya (yang masih belum diketahui akar
/// masalahnya, makanya logging ini dipasang). Hapus test ini bersamaan
/// dgn pencabutan seluruh instrumentasi Item 55.
Future<String> _addProduct(AppDatabase db, {required String name}) async {
  final productId = 'p-$name';
  final unitId = '$productId-u';
  await db.into(db.products).insert(ProductsCompanion.insert(
        id: productId,
        name: name,
      ));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId,
        productId: productId,
        isBaseUnit: const Value(true),
      ));
  await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: '$unitId-t1',
        productUnitId: unitId,
        minQty: const Value(1),
        price: 10000,
      ));
  return unitId;
}

void main() {
  setUp(OrderParseDiagnostics.clear);

  test('teks tanpa kode mesin -> log mencatat "tidak ada kode mesin"',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await OrderParserService.parse(db: db, text: 'halo, ada gula?');

    expect(
        OrderParseDiagnostics.entries
            .any((e) => e.contains('TIDAK ADA kode mesin')),
        isTrue);
  });

  test('unitId TIDAK ketemu di product_units -> log mencatat titik gagal #1',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await OrderParserService.parse(db: db, text: '#PSN:unit-tidak-ada=2;');

    expect(
        OrderParseDiagnostics.entries.any((e) =>
            e.contains('unitId=unit-tidak-ada') &&
            e.contains('TIDAK KETEMU') &&
            e.contains('notFound')),
        isTrue);
  });

  test(
      'product tidak aktif -> log mencatat titik gagal #2 (unit ketemu, '
      'product nonaktif)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const unitId = 'u-nonaktif';
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'p-nonaktif',
          name: 'Produk Nonaktif',
          isActive: const Value(false),
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: 'p-nonaktif',
          isBaseUnit: const Value(true),
        ));

    await OrderParserService.parse(db: db, text: '#PSN:$unitId=2;');

    expect(
        OrderParseDiagnostics.entries.any((e) =>
            e.contains('unitId=$unitId') &&
            e.contains('is_active=false') &&
            e.contains('notFound')),
        isTrue);
  });

  test('unit & product KETEMU & aktif -> log mencatat masuk items', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final unitId = await _addProduct(db, name: 'Gula');

    final result = await OrderParserService.parse(db: db, text: '#PSN:$unitId=2;');

    expect(result.items, hasLength(1));
    expect(
        OrderParseDiagnostics.entries.any((e) =>
            e.contains('unitId=$unitId') &&
            e.contains('KETEMU') &&
            e.contains('is_active=true') &&
            e.contains('-> items')),
        isTrue);
  });

  test('entries dibatasi 200 terakhir (buang yang paling lama)', () async {
    for (var i = 0; i < 250; i++) {
      OrderParseDiagnostics.add('entry-$i');
    }
    expect(OrderParseDiagnostics.entries, hasLength(200));
    expect(OrderParseDiagnostics.entries.first, 'entry-50',
        reason: '50 entry paling lama (0..49) harus sudah dibuang');
    expect(OrderParseDiagnostics.entries.last, 'entry-249');
  });
}
