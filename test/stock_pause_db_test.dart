import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// `pauseStockTrackingForAllProducts`/`resumeStockTrackingForAllProducts` —
/// lihat dok panjang di app_database.dart. Test level DB murni (tanpa UI),
/// melengkapi `pengaturan_stock_pause_toggle_test.dart`.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedUnit(String id, String productId, bool nonStock) async {
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: id,
        productId: productId,
        isBaseUnit: const Value(true),
        isNonStock: Value(nonStock)));
  }

  test('pause: hanya satuan yang tadinya dilacak yang diubah, hitungan benar',
      () async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'A'));
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p2', name: 'B'));
    await seedUnit('u1', 'p1', false);
    await seedUnit('u2', 'p2', true); // sudah non-stok dari awal

    final changed = await db.pauseStockTrackingForAllProducts();
    expect(changed, 1);
    expect(await db.isStockTrackingPaused(), isTrue);

    final u1 = await (db.select(db.productUnits)
          ..where((t) => t.id.equals('u1')))
        .getSingle();
    expect(u1.isNonStock, isTrue);
  });

  test('pause dipanggil 2x (sudah jeda) -> no-op, return 0', () async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'A'));
    await seedUnit('u1', 'p1', false);

    await db.pauseStockTrackingForAllProducts();
    final second = await db.pauseStockTrackingForAllProducts();
    expect(second, 0);
  });

  test('resume: mengembalikan persis satuan yg diubah pause, bukan semua',
      () async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'A'));
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p2', name: 'B'));
    await seedUnit('u1', 'p1', false);
    await seedUnit('u2', 'p2', true);

    await db.pauseStockTrackingForAllProducts();
    final restored = await db.resumeStockTrackingForAllProducts();
    expect(restored, 1);
    expect(await db.isStockTrackingPaused(), isFalse);

    final u1 = await (db.select(db.productUnits)
          ..where((t) => t.id.equals('u1')))
        .getSingle();
    final u2 = await (db.select(db.productUnits)
          ..where((t) => t.id.equals('u2')))
        .getSingle();
    expect(u1.isNonStock, isFalse, reason: 'dipulihkan');
    expect(u2.isNonStock, isTrue,
        reason: 'tidak pernah diubah pause, jadi tidak disentuh resume juga');
  });

  test('resume tanpa sedang dijeda -> no-op, return 0', () async {
    expect(await db.resumeStockTrackingForAllProducts(), 0);
  });
}
