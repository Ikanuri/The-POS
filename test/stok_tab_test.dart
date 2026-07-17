import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laporan/tabs/stok_tab.dart';

import 'helpers/pump_app.dart';

/// Item 30(c) — tab Stok di Laporan: agregasi (grand total, per-kategori,
/// deteksi harga pokok kosong, daftar stok negatif) dihitung di provider
/// (`_stokTabProvider`) dari baris mentah `getInventoryRows()` — widget test
/// ini yang membuktikan logika agregasi Dart-nya benar (bukan cuma query
/// SQL-nya, yang sudah dites terpisah di test/inventory_rows_test.dart).
void main() {
  Future<String> addProduct(
    AppDatabase db,
    String name, {
    int? groupId,
    int costPrice = 0,
  }) async {
    final id = 'p-$name';
    final unitId = '$id-u';
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: id,
          name: name,
          productGroupId: Value(groupId),
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: id,
          isBaseUnit: const Value(true),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: '$unitId-t1',
          productUnitId: unitId,
          minQty: const Value(1),
          price: 10000,
          costPrice: Value(costPrice),
        ));
    return unitId;
  }

  testWidgets(
      'grand total = Σ(stok×harga pokok) semua produk, tampil sbg Rupiah',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final u1 = await addProduct(db, 'Gula', groupId: 1, costPrice: 10000);
    final u2 = await addProduct(db, 'Beras', groupId: 2, costPrice: 8000);
    await db.adjustStock(productUnitId: u1, newQty: 5); // 50.000
    await db.adjustStock(productUnitId: u2, newQty: 10); // 80.000

    await pumpWithFakeApp(tester, db: db, child: const StokTab());

    expect(find.text(formatRupiah(130000)), findsOneWidget);
    await db.close();
  });

  testWidgets(
      'produk dgn harga pokok kosong/0 dihitung & ditandai (nilainya '
      'understated)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final u1 = await addProduct(db, 'Ada Harga', costPrice: 5000);
    final u2 = await addProduct(db, 'Tanpa Harga', costPrice: 0);
    await db.adjustStock(productUnitId: u1, newQty: 2);
    await db.adjustStock(productUnitId: u2, newQty: 3);

    await pumpWithFakeApp(tester, db: db, child: const StokTab());

    expect(find.textContaining('1 produk belum ada harga pokok'),
        findsOneWidget);
    await db.close();
  });

  testWidgets('daftar stok negatif tampil, diurut paling minus dulu',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final u1 = await addProduct(db, 'Minus Sedikit', costPrice: 1000);
    final u2 = await addProduct(db, 'Minus Banyak', costPrice: 1000);
    await db.adjustStock(productUnitId: u1, newQty: -2);
    await db.adjustStock(productUnitId: u2, newQty: -10);

    await pumpWithFakeApp(tester, db: db, child: const StokTab());

    expect(find.textContaining('Stok Negatif Saat Ini (2)'), findsOneWidget);
    final minusBanyakY =
        tester.getCenter(find.text('Minus Banyak')).dy;
    final minusSedikitY =
        tester.getCenter(find.text('Minus Sedikit')).dy;
    expect(minusBanyakY, lessThan(minusSedikitY),
        reason: '-10 (paling minus) harus di atas -2');
    await db.close();
  });

  testWidgets(
      'tanpa stok negatif → seksi "Stok Negatif" tidak muncul sama sekali',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final u1 = await addProduct(db, 'Aman', costPrice: 1000);
    await db.adjustStock(productUnitId: u1, newQty: 5);

    await pumpWithFakeApp(tester, db: db, child: const StokTab());

    expect(find.textContaining('Stok Negatif'), findsNothing);
    await db.close();
  });
}
