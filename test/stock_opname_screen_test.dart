import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/stock_opname_screen.dart';

import 'helpers/pump_app.dart';

/// Item 36 — Stock Opname: alur hitung BUTA (stok sistem TIDAK ditampilkan
/// saat input) → review selisih (baru di sini stok sistem vs fisik
/// dibandingkan) → commit ke DB via AppDatabase.commitOpname.
void main() {
  Future<String> addProduct(AppDatabase db, String name,
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
      'layar hitung TIDAK menampilkan stok sistem (mode buta) — hanya nama '
      'produk & input kosong', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await addProduct(db, 'Beras', initialStock: 25);

    await pumpWithFakeApp(tester, db: db, child: const StockOpnameScreen());
    await tester.tap(find.text('Mulai Hitung'));
    await tester.pumpAndSettle();

    expect(find.text('Beras'), findsOneWidget);
    // Mode buta: angka stok sistem (25) TIDAK BOLEH muncul di layar hitung.
    expect(find.text('25'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);

    await db.close();
  });

  testWidgets(
      'alur penuh: hitung → review menampilkan selisih → commit menyimpan '
      'ke stock_ledger dgn stok baru = hasil hitung fisik', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final u = await addProduct(db, 'Gula', initialStock: 10);

    await pumpWithFakeApp(tester, db: db, child: const StockOpnameScreen());
    await tester.tap(find.text('Mulai Hitung'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '7');
    await tester.tap(find.text('Review Selisih'));
    await tester.pumpAndSettle();

    // Di layar review, stok sistem BARU muncul & selisih dihitung benar.
    expect(find.textContaining('Sistem: 10'), findsOneWidget);
    expect(find.textContaining('Fisik: 7'), findsOneWidget);
    expect(find.text('-3'), findsOneWidget);

    await tester.tap(find.text('Simpan (1 produk beda)'));
    await tester.pumpAndSettle();

    expect(await db.currentStock(u), 7);

    final sessions = await db.getOpnameSessions();
    expect(sessions.length, 1);
    expect(sessions.first.note, contains('Seluruh'));

    await db.close();
  });

  testWidgets('produk yang hitungannya dibiarkan kosong TIDAK ikut disimpan',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await addProduct(db, 'Kopi', initialStock: 5);
    await addProduct(db, 'Teh', initialStock: 8);

    await pumpWithFakeApp(tester, db: db, child: const StockOpnameScreen());
    await tester.tap(find.text('Mulai Hitung'));
    await tester.pumpAndSettle();

    // Hanya isi hitungan utk 'Kopi' (field pertama), biarkan 'Teh' kosong.
    await tester.enterText(find.byType(TextField).first, '4');
    await tester.tap(find.text('Review Selisih'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Kopi'), findsOneWidget);
    expect(find.textContaining('Teh'), findsNothing,
        reason: 'produk tanpa input hitungan tidak boleh ikut ke review');

    await db.close();
  });
}
