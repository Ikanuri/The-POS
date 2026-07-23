import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 52 — bulk assign produk ke kategori (dari layar Kelola Kategori,
/// tap kategori → pilih banyak produk sekaligus). Produk yang SUDAH punya
/// kategori lain boleh ikut dipilih & ditimpa (keputusan eksplisit user).
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(100), name: const Value('Minuman')));
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(200), name: const Value('Snack')));

    Future<void> seed(String id, String name, {int? groupId}) => db.saveProduct(
          product: ProductsCompanion.insert(
            id: id,
            name: name,
            productGroupId: Value(groupId),
          ),
          units: [
            ProductUnitsCompanion.insert(
                id: '${id}_u', productId: id, isBaseUnit: const Value(true)),
          ],
          tiersByUnitTempId: {
            '${id}_u': [
              PriceTiersCompanion.insert(
                  id: '${id}_t', productUnitId: '${id}_u', price: 1000),
            ],
          },
          barcodesByUnitTempId: const {},
          altPricesByUnitTempId: const {},
        );

    await seed('p1', 'Teh Botol'); // tanpa kategori
    await seed('p2', 'Kopi Sachet', groupId: 200); // sudah di kategori lain
    await seed('p3', 'Air Mineral'); // tanpa kategori
  });
  tearDown(() => db.close());

  test('assignProductsToGroup menugaskan banyak produk sekaligus ke satu '
      'kategori, termasuk yang sudah punya kategori lain (ditimpa)',
      () async {
    await db.assignProductsToGroup(['p1', 'p2', 'p3'], 100);

    final all = await (db.select(db.products)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    for (final p in all) {
      expect(p.productGroupId, 100,
          reason: '${p.id} harus ikut ter-assign ke kategori 100');
    }
  });

  test('produk yang TIDAK dipilih tidak ikut berubah kategorinya', () async {
    await db.assignProductsToGroup(['p1'], 100);

    final p2 = await (db.select(db.products)..where((t) => t.id.equals('p2')))
        .getSingle();
    final p3 = await (db.select(db.products)..where((t) => t.id.equals('p3')))
        .getSingle();
    expect(p2.productGroupId, 200, reason: 'p2 tidak dipilih, tetap Snack');
    expect(p3.productGroupId, isNull, reason: 'p3 tidak dipilih, tetap kosong');
  });

  test('updated_at dicap ulang ke SAAT INI (supaya ikut tersinkron ke '
      'klien lain) — bukan gotcha CLAUDE.md yang terulang', () async {
    final before = await (db.select(db.products)..where((t) => t.id.equals('p1')))
        .getSingle();
    final oldUpdatedAt = before.updatedAt;

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final beforeAssign = DateTime.now().subtract(const Duration(seconds: 1));
    await db.assignProductsToGroup(['p1'], 100);

    final after = await (db.select(db.products)..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(after.updatedAt.isAfter(oldUpdatedAt), isTrue);
    expect(
        after.updatedAt.isAfter(beforeAssign) ||
            after.updatedAt.isAtSameMomentAs(beforeAssign),
        isTrue);

    // Baris harus tetap ikut dumpSince berikutnya (watermark klien di
    // antara edit lama dan assign barusan).
    final sinceAfterOldEdit = DateTime.now().subtract(const Duration(seconds: 1, milliseconds: 500));
    final dump = await db.dumpSince(sinceAfterOldEdit);
    expect(dump['products']!.any((r) => r['id'] == 'p1'), isTrue);
  });

  test('daftar kosong tidak melakukan apa-apa (tidak error)', () async {
    await db.assignProductsToGroup(const [], 100);
    final p1 = await (db.select(db.products)..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(p1.productGroupId, isNull);
  });
}
