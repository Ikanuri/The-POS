import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/stock_opname_screen.dart';

import 'helpers/pump_app.dart';

/// Item 3 (usulan user) — Stock Opname sekarang boleh dihitung dalam
/// satuan berjenjang (mis. "10 dus"), dikonversi ke satuan dasar
/// (`ratio_to_base`) sebelum dibandingkan/disimpan. HANYA produk dengan
/// >1 satuan yang dapat pemilih satuan — produk bersatuan tunggal (mayoritas
/// toko) tetap field polos seperti sebelumnya, sudah dibuktikan tidak
/// berubah di `stock_opname_screen_test.dart`.
void main() {
  Future<String> addTieredProduct(AppDatabase db, String name,
      {required double initialStockBase, required double ratioDus}) async {
    final id = 'p-$name';
    final baseUnitId = '$id-pcs';
    final dusUnitId = '$id-dus';
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: id, name: name));
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(101), name: 'Pcs'),
        mode: InsertMode.insertOrIgnore);
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(102), name: 'Dus'),
        mode: InsertMode.insertOrIgnore);
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: baseUnitId,
          productId: id,
          isBaseUnit: const Value(true),
          unitTypeId: const Value(101),
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: dusUnitId,
          productId: id,
          isBaseUnit: const Value(false),
          ratioToBase: Value(ratioDus),
          unitTypeId: const Value(102),
        ));
    if (initialStockBase != 0) {
      await db.adjustStock(productUnitId: baseUnitId, newQty: initialStockBase);
    }
    return baseUnitId;
  }

  Future<String> addPlainProduct(AppDatabase db, String name,
      {double initialStock = 0}) async {
    final id = 'p-$name';
    final unitId = '$id-u';
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: id, name: name));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: id,
          isBaseUnit: const Value(true),
        ));
    if (initialStock != 0) {
      await db.adjustStock(productUnitId: unitId, newQty: initialStock);
    }
    return unitId;
  }

  testWidgets(
      'produk bersatuan tunggal TIDAK dapat pemilih satuan (tampilan '
      'tidak berubah)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await addPlainProduct(db, 'Beras', initialStock: 5);

    await pumpWithFakeApp(tester, db: db, child: const StockOpnameScreen());
    await tester.tap(find.text('Mulai Hitung'));
    await tester.pumpAndSettle();

    expect(find.text('Beras'), findsOneWidget);
    expect(find.byType(DropdownButton<int>), findsNothing,
        reason: 'produk 1 satuan tidak perlu pemilih satuan sama sekali');

    await db.close();
  });

  testWidgets(
      'produk berjenjang (Pcs/Dus) dapat pemilih satuan; input "10" dgn '
      'Dus dipilih dikonversi ke 100 Pcs (ratio 10) saat review',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final baseUnitId = await addTieredProduct(db, 'Indomie',
        initialStockBase: 20, ratioDus: 10);

    await pumpWithFakeApp(tester, db: db, child: const StockOpnameScreen());
    await tester.tap(find.text('Mulai Hitung'));
    await tester.pumpAndSettle();

    expect(find.text('Indomie'), findsOneWidget);
    expect(find.byType(DropdownButton<int>), findsOneWidget,
        reason: 'produk berjenjang harus dapat pemilih satuan');

    await tester.enterText(find.byType(TextField).first, '10');
    // Pilih satuan "Dus" — panggil langsung callback `onChanged` (bukan
    // tap buka popup lalu tap opsi) supaya test TIDAK bergantung pada
    // timing Overlay/Route milik popup `DropdownButton` (ditemukan flaky
    // sesekali di full-suite: popup yg belum sempat settle bisa
    // menghalangi tap "Simpan" di layar berikutnya). Ini tetap menguji
    // wiring `onChanged` sungguhan (state + konversi), cuma tidak
    // menguji mekanik popup Flutter sendiri (sudah teruji framework).
    final dropdown =
        tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>));
    final dusIdx = dropdown.items!
        .indexWhere((item) => (item.child as Text).data == 'Dus');
    dropdown.onChanged!(dusIdx);
    await tester.pump();

    await tester.tap(find.text('Review Selisih'));
    await tester.pumpAndSettle();

    // 10 dus * ratio 10 = 100 Pcs (satuan dasar) — dibandingkan dgn stok
    // sistem 20 Pcs, selisih +80.
    expect(find.textContaining('Sistem: 20'), findsOneWidget);
    expect(find.textContaining('Fisik: 100'), findsOneWidget);
    expect(find.text('+80'), findsOneWidget);
    expect(find.textContaining('diketik: 10 Dus'), findsOneWidget,
        reason: 'nilai APA ADANYA yang diketik user harus tetap terlihat, '
            'bukan cuma hasil konversinya');

    await tester.tap(find.text('Simpan (1 produk beda)'));
    await tester.pumpAndSettle();

    expect(await db.currentStock(baseUnitId), 100);

    await db.close();
  });
}
