import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): retur produk timbang (mis. minyak kelapa
/// 4.5kg) butuh qty DESIMAL — dialog Retur sebelumnya cuma punya stepper
/// +/-1, tidak bisa mencapai nilai desimal sembarang (mis. retur 2.5 dari
/// beli 4.5 mustahil lewat kelipatan 1 murni). Fix: qty diganti `TextField`
/// yang bisa diketik langsung, sama pola dgn dialog Titip/Ketinggalan.
///
/// Bonus bug ditemukan (bukan cuma fitur baru): tombol stepper `+` lama
/// TIDAK meng-klem ke qty maksimum — bisa menampilkan angka MELEBIHI batas
/// walau DB tetap meng-klem otomatis (jadi tidak ada data rusak, tapi
/// ANGKA DI LAYAR keliru/membingungkan kasir).
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  Finder inSheet(String text) => find.descendant(
      of: find.byType(BottomSheet), matching: find.text(text));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 90000,
          paid: 90000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'P1', name: 'Minyak Kelapa'));
    // Produk timbang, qty DESIMAL (4.5kg) — sama pola dgn kasus Titip/
    // Ketinggalan yg sudah dibereskan sebelumnya.
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: 4.5,
        priceAtSale: 20000,
        originalPrice: 20000,
        subtotal: 90000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: txId, amount: 90000, method: 'tunai'));
  });
  tearDown(() async => db.close());

  testWidgets(
      'retur qty DESIMAL (mis. 2.5 dari beli 4.5) bisa diketik langsung, '
      'refund menyesuaikan proporsional', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.text('Retur'));
    await tester.pumpAndSettle();

    expect(inSheet('Maks 4.5 · Rp 20.000'), findsOneWidget);

    // Ketik angka desimal SEMBARANG (2.5) — mustahil dicapai stepper +/-1
    // murni dari 0 (loncat 1,2,3,4... tidak pernah pas di 2.5 kecuali
    // kebetulan; di sini kita buktikan bisa diketik langsung).
    await tester.enterText(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(TextField)),
        '2.5');
    await tester.pumpAndSettle();

    // Refund menyesuaikan proporsional: 2.5 x Rp 20.000 = Rp 50.000.
    expect(inSheet('Rp 50.000'), findsOneWidget);

    await tester.tap(find.text('Konfirmasi Retur'));
    await tester.pumpAndSettle();

    final returnRows = await (db.select(db.transactionItems)
          ..where((t) => t.transactionId.equals(txId) & t.qty.isSmallerThanValue(0)))
        .get();
    expect(returnRows, hasLength(1));
    expect(returnRows.single.qty, -2.5,
        reason: 'baris retur tersimpan qty desimal persis (bukan dibulatkan)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'susulan: tombol stepper "+" mengklem PERSIS ke batas qty (mis. 4.5), '
      'tidak melebihi jadi 5 walau di layar', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.text('Retur'));
    await tester.pumpAndSettle();

    // Naikkan stepper 4x dari 0 -> 4 (masih di bawah batas 4.5).
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
    }
    expect(inSheet('4'), findsOneWidget);

    // Putaran ke-5 HARUS mendarat PAS di batas 4.5, bukan melebihi jadi 5.
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    expect(inSheet('4.5'), findsOneWidget,
        reason: 'stepper + wajib klem ke qty PERSIS, bukan q+1 polos');
    expect(inSheet('5'), findsNothing);

    // Tombol + sekarang harus nonaktif (sudah di batas maksimum).
    final tambahLagi = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.add_circle_outline),
        matching: find.byType(IconButton)).first);
    expect(tambahLagi.onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
