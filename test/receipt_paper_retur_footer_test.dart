import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Item 49g — struk gambar (_ReceiptPaper, "Bagikan Struk") nota LUNAS yang
/// pernah diretur: separator "----- Retur HH:MM -----" + footer breakdown
/// "Total awal/Retur/Total akhir/Refund" — sama pola dgn struk in-app.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'struk gambar nota lunas diretur: separator Retur + footer breakdown '
      'tampil, bukan pola 3-baris biasa', (tester) async {
    const txId = 'tx1';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 406000,
          paid: 406000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i-12',
        transactionId: txId,
        productId: 'P12',
        productUnitId: 'U-Slop',
        qty: 1,
        priceAtSale: 193000,
        originalPrice: 193000,
        subtotal: 193000));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i-refil',
        transactionId: txId,
        productId: 'PRefil',
        productUnitId: 'U-Slop-Refil',
        qty: 1,
        priceAtSale: 213000,
        originalPrice: 213000,
        subtotal: 213000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: txId, amount: 406000, method: 'tunai'));

    await db.returnPaidTransactionItems(
      txId: txId,
      returns: const [(transactionItemId: 'i-refil', qty: 1)],
      kasirId: 'K1',
      refundMethod: 'tunai',
    );

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));
    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    final receiptPaper = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_ReceiptPaper');
    expect(receiptPaper, findsOneWidget);

    expect(
        find.descendant(
            of: receiptPaper, matching: find.textContaining('Retur')),
        findsWidgets,
        reason: 'separator "----- Retur HH:MM -----" harus muncul');
    expect(
        find.descendant(of: receiptPaper, matching: find.text('Total awal')),
        findsOneWidget);
    expect(find.descendant(of: receiptPaper, matching: find.text('Akhir')),
        findsOneWidget);
    expect(
        find.descendant(
            of: receiptPaper,
            matching: find.text('Rp ${_fmtNumLike(406000)}')),
        findsWidgets,
        reason: 'Total awal 406.000');
    expect(
        find.descendant(
            of: receiptPaper,
            matching: find.textContaining('Refund')),
        findsOneWidget);
    expect(
        find.descendant(of: receiptPaper, matching: find.text('Total')),
        findsNothing,
        reason: 'label "Total" polos (bukan Total awal/akhir) tidak boleh '
            'tampil saat nota pernah diretur');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

// `_ReceiptPaper._fmtNum` pakai TITIK sbg pemisah ribuan (gaya Indonesia).
String _fmtNumLike(int amount) {
  final s = amount.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}
