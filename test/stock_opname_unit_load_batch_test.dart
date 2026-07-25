import 'package:drift/drift.dart'
    show ApplyInterceptor, InsertMode, QueryExecutor, QueryInterceptor, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/stock_opname_screen.dart';

import 'helpers/pump_app.dart';

/// Layar "Hitung Fisik" (Stock Opname) memuat pemilih satuan untuk SELURUH
/// daftar produk sekaligus, dan menahan semua barisnya di balik
/// `CircularProgressIndicator` sampai pemuatan itu selesai. Dulu caranya
/// N+1 BERLAPIS: `getProductUnits` sekali per produk, lalu satu select
/// `unit_types` per satuan — 1000 produk berjenjang = 3000 round-trip
/// (~440ms di SQLite memori x86, jauh lebih parah di HP kelas bawah krn
/// SQLCipher mendekripsi tiap page + I/O file), jadi layarnya diam di
/// spinner selama itu. Sekarang satu query JOIN
/// (`getUnitsWithTypeNamesFor`).
///
/// Test tier DB/widget biasa TIDAK bisa menangkap kelas bug ini — hasil
/// akhirnya identik, yang berbeda hanya JUMLAH query. Jadi di sini
/// query-nya benar-benar dihitung lewat `QueryInterceptor` Drift.
class _SelectCounter extends QueryInterceptor {
  final List<String> selects = [];

  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor executor, String statement, List<Object?> args) {
    selects.add(statement);
    return executor.runSelect(statement, args);
  }

  /// Hanya query yang menyentuh tabel satuan — mengisolasi kerja pemuatan
  /// satuan dari query lain milik layar (mis. `watchStockOverview`).
  int get unitQueries => selects
      .where((s) => s.contains('product_units') || s.contains('unit_types'))
      .length;
}

void main() {
  Future<void> addTieredProduct(AppDatabase db, int i) async {
    final id = 'p$i';
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: id, name: 'Produk $i'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: '$id-pcs',
          productId: id,
          isBaseUnit: const Value(true),
          unitTypeId: const Value(101),
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: '$id-dus',
          productId: id,
          isBaseUnit: const Value(false),
          ratioToBase: const Value(10),
          unitTypeId: const Value(102),
        ));
    await db.adjustStock(productUnitId: '$id-pcs', newQty: 50);
  }

  testWidgets(
      'buka Hitung Fisik: satuan seluruh daftar dimuat dgn SATU query batch, '
      'bukan N+1 per produk/per satuan', (tester) async {
    final counter = _SelectCounter();
    final db = AppDatabase(NativeDatabase.memory().interceptWith(counter));

    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(101), name: 'Pcs'),
        mode: InsertMode.insertOrIgnore);
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(102), name: 'Dus'),
        mode: InsertMode.insertOrIgnore);

    const n = 40;
    for (var i = 0; i < n; i++) {
      await addTieredProduct(db, i);
    }

    await pumpWithFakeApp(tester, db: db, child: const StockOpnameScreen());

    counter.selects.clear();
    await tester.tap(find.text('Mulai Hitung'));
    await tester.pumpAndSettle();

    // Spinner sudah hilang = pemuatan satuan selesai.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Pemilih satuan benar-benar terbentuk (bukan lolos karena tidak memuat
    // apa pun) — 40 produk berjenjang, dropdown-nya lazy-build di viewport
    // jadi cukup pastikan ada.
    expect(find.byType(DropdownButton<int>), findsWidgets);

    // Sebelum fix: 40 produk -> 40 getProductUnits + 80 select unit_types
    // = 120 query. Sesudah: 1 query batch (+ `watchStockOverview` yang juga
    // menyentuh product_units), jadi ambang longgar 5 sudah membedakan
    // keduanya dgn sangat jelas.
    expect(counter.unitQueries, lessThanOrEqualTo(5),
        reason: 'satuan harus dimuat sekali secara batch, bukan per produk. '
            'Query menyentuh tabel satuan: ${counter.unitQueries}');

    await db.close();
  });

  test(
      'getUnitsWithTypeNamesFor: hasil identik dgn cara lama (grouping, nama '
      'tipe satuan, urutan insert, fallback unitTypeId null -> id 1)',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(101), name: 'Pcs'),
        mode: InsertMode.insertOrIgnore);
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(102), name: 'Dus'),
        mode: InsertMode.insertOrIgnore);

    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'pA', name: 'A'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'pA-pcs',
          productId: 'pA',
          isBaseUnit: const Value(true),
          unitTypeId: const Value(101),
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'pA-dus',
          productId: 'pA',
          isBaseUnit: const Value(false),
          ratioToBase: const Value(10),
          unitTypeId: const Value(102),
        ));

    // Produk B: satuan TANPA unitTypeId — perilaku lama `u.unitTypeId ?? 1`
    // jatuh ke unit type id 1 ('Kg' di seed default), bukan 'Satuan'.
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'pB', name: 'B'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'pB-base',
          productId: 'pB',
          isBaseUnit: const Value(true),
        ));

    final map = await db.getUnitsWithTypeNamesFor(['pA', 'pB']);

    expect(map['pA']!.map((e) => e.unit.id).toList(), ['pA-pcs', 'pA-dus'],
        reason: 'urutan harus urutan insert (rowid), karena indeks dropdown '
            'dan indexWhere(isBaseUnit) bergantung padanya');
    expect(map['pA']!.map((e) => e.unitName).toList(), ['Pcs', 'Dus']);
    expect(map['pB']!.single.unitName, 'Kg',
        reason: 'unitTypeId null harus tetap jatuh ke id 1 spt kode lama, '
            'bukan berubah jadi "Satuan"');

    // Produk yang tidak diminta tidak ikut terbawa, dan input kosong aman.
    expect(map.containsKey('pC'), isFalse);
    expect(await db.getUnitsWithTypeNamesFor([]), isEmpty);
  });
}
