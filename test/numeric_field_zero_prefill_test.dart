import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pelanggan/pelanggan_form_screen.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Laporan user: "ketika cursor ada di field dengan nol, nol sebagai
/// placeholder pra-cursor tidak terhapus".
///
/// Dua pelanggar pola ditemukan (field angka lain di app — `thresholdCtrl`
/// Pengaturan, `debt_payment_sheet`, harga/HPP produk — SUDAH sengaja
/// kosong saat nilainya nol):
///
/// 1. Dialog "Sesuaikan Stok" (`produk_form_screen.dart`): field `autofocus`
///    TAPI sudah terisi stok sekarang, jadi cursor mendarat di UJUNG angka —
///    mengetik MENEMPEL, bukan mengganti. Untuk stok 0 hasilnya "012"
///    (kebetulan masih ter-parse 12), tapi untuk stok NON-nol ini bahaya
///    data nyata: stok 5 + ketik "12" = "512" -> stok tersimpan 512.
///    Padahal "Stok saat ini" sudah tertulis di atas field, jadi angka di
///    dalam field itu murni redundan.
/// 2. Field "Poin Loyalitas" pelanggan baru: di-prefill '0' literal.
void main() {
  testWidgets(
      'dialog Sesuaikan Stok: angka stok lama ter-select seluruhnya saat '
      'dialog terbuka, jadi ketikan MENGGANTI (bukan menempel di belakang)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Indomie'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'p1-u',
          productId: 'p1',
          isBaseUnit: const Value(true),
        ));
    // Stok NON-nol: kasus yang paling berbahaya (menempel = angka salah
    // tersimpan, bukan cuma merepotkan).
    await db.adjustStock(productUnitId: 'p1-u', newQty: 5);

    await pumpWithFakeApp(tester, db: db,
        child: const ProdukFormScreen(productId: 'p1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sesuaikan').first);
    await tester.pumpAndSettle();
    expect(find.text('Sesuaikan Stok'), findsOneWidget,
        reason: 'dialog harus benar-benar terbuka sebelum diperiksa');

    final qtyField = tester.widget<TextField>(find.ancestor(
      of: find.text('Stok baru'),
      matching: find.byType(TextField),
    ));
    final ctrl = qtyField.controller!;

    expect(ctrl.text, '5', reason: 'stok sekarang tetap ditampilkan di field');
    expect(ctrl.selection, const TextSelection(baseOffset: 0, extentOffset: 1),
        reason: 'seluruh angka harus ter-select supaya ketikan menggantinya, '
            'bukan menempel jadi "512"');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'form pelanggan baru: field Poin Loyalitas KOSONG, bukan diisi "0" '
      'yang harus dihapus dulu', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());

    await pumpWithFakeApp(tester, db: db, child: const PelangganFormScreen());
    await tester.pumpAndSettle();

    final pointsField = tester.widget<TextFormField>(find.ancestor(
      of: find.text('Poin Loyalitas'),
      matching: find.byType(TextFormField),
    ));
    expect(pointsField.controller!.text, isEmpty,
        reason: 'nol default tidak boleh jadi teks yang harus dihapus manual');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets('pelanggan lama berpoin 0: field juga kosong', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'c0',
          name: 'Tanpa Poin',
          loyaltyPoints: const Value(0),
        ));

    await pumpWithFakeApp(tester, db: db,
        child: const PelangganFormScreen(customerId: 'c0'));
    await tester.pumpAndSettle();

    final ctrl = tester
        .widget<TextFormField>(find.ancestor(
          of: find.text('Poin Loyalitas'),
          matching: find.byType(TextFormField),
        ))
        .controller!;
    expect(ctrl.text, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets('poin NON-nol tetap ditampilkan apa adanya', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'c1',
          name: 'Punya Poin',
          loyaltyPoints: const Value(250),
        ));

    await pumpWithFakeApp(tester, db: db,
        child: const PelangganFormScreen(customerId: 'c1'));
    await tester.pumpAndSettle();

    final ctrl = tester
        .widget<TextFormField>(find.ancestor(
          of: find.text('Poin Loyalitas'),
          matching: find.byType(TextFormField),
        ))
        .controller!;
    expect(ctrl.text, '250',
        reason: 'blanking hanya berlaku untuk nol, bukan menghapus data asli');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
