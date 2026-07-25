import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/cek_stok_screen.dart';

import 'helpers/pump_app.dart';

/// Item 4 (usulan user) — Cek Stok: produk berjenjang (>1 satuan) yg
/// dicentang utk restock dapat pemilih satuan; teks Order Restock
/// menampilkan "{qty} {satuan} {nama}" (format sama dgn contoh HTML yg
/// dikirim user: "10 dus Glukol") memakai satuan yg dipilih, BUKAN cuma
/// "- {nama}" polos spt produk bersatuan tunggal.
void main() {
  Future<void> addTieredProduct(AppDatabase db, String name,
      {required double stockBase, required double ratioDus}) async {
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
    if (stockBase != 0) {
      await db.adjustStock(productUnitId: baseUnitId, newQty: stockBase);
    }
  }

  testWidgets(
      'produk berjenjang dicentang → muncul pemilih satuan; pilih "Dus" → '
      'teks Order Restock jadi "{qty} Dus {nama}"', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await addTieredProduct(db, 'Indomie', stockBase: 25, ratioDus: 10);

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<int>), findsOneWidget,
        reason: 'produk berjenjang yg dicentang harus dapat pemilih satuan');

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dus').last);
    await tester.pumpAndSettle();

    // 25 pcs / ratio 10 = 2.5 dus.
    expect(find.textContaining('2.5 Dus Indomie'), findsWidgets);

    await db.close();
  });

  testWidgets(
      'produk bersatuan tunggal dicentang → TIDAK ada pemilih satuan, teks '
      'tetap "- {nama}" polos seperti sebelumnya', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p-Beras', name: 'Beras'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'p-Beras-u',
          productId: 'p-Beras',
          isBaseUnit: const Value(true),
        ));

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(find.textContaining('- Beras'), findsOneWidget);

    await db.close();
  });
}
