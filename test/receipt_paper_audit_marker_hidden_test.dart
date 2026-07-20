import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Item 49f — baris audit-trail internal (`transactionPayments.method`
/// 'edit'/'retur', amount selalu 0, disisipkan `returnUnpaidTransactionItems`
/// sbg jejak "kapan ada retur/edit") BUKAN utk konsumsi pelanggan. Sebelum
/// fix, baris ini ikut ke timeline pembayaran struk gambar (_ReceiptPaper,
/// muncul lewat "Bagikan Struk") — `_methodShort` tak kenal method itu,
/// jadi tampil sbg string mentah "retur"/"edit" di struk. User: "jejak
/// audit... bukan untuk konsumsi pelanggan, lagipula ada in-app struk yang
/// menyimpan semuanya" — jadi HANYA disembunyikan dari share/print, timeline
/// pembayaran ASLI (uang sungguhan) tetap tampil apa adanya.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'struk gambar (_ReceiptPaper): marker audit "retur" TIDAK tampil di '
      'timeline pembayaran, tapi 2 cicilan tunai ASLI tetap tampil',
      (tester) async {
    const txId = 'tx1';
    final t0 = DateTime(2026, 7, 20, 8, 0);
    final t2 = DateTime(2026, 7, 20, 9, 0);

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'kurang_bayar',
          total: 100000,
          paid: 40000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(t0),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 10,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 100000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: txId,
            amount: 40000,
            method: 'tunai',
            paidAt: Value(t0)));

    // Retur sebagian (2 dari 10) — menyisipkan marker audit method 'retur'
    // amount 0 ke transactionPayments (lihat returnUnpaidTransactionItems).
    await db.returnUnpaidTransactionItems(
      txId: txId,
      returns: const [(transactionItemId: 'i0', qty: 2)],
      kasirId: 'K1',
    );

    // Cicilan kedua (uang SUNGGUHAN) — harus tetap tampil di timeline.
    await db.addPaymentToTransaction(
      txId: txId,
      amount: 40000,
      method: 'tunai',
      kasirId: 'K1',
      now: t2,
    );

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    // Scope pencarian KHUSUS ke dalam _ReceiptPaper (struk gambar) — layar
    // ReceiptScreen di balik modal sheet TETAP mounted (Flutter tidak
    // membongkar route di bawah showModalBottomSheet) & memang SENGAJA
    // masih menampilkan marker "retur" apa adanya di timeline in-app-nya
    // sendiri (_buildPaymentTimeline, method _methodLabel) — kalau dicari
    // tanpa scope, assertion di bawah akan salah menangkap Text itu.
    final receiptPaper = find
        .byWidgetPredicate((w) => w.runtimeType.toString() == '_ReceiptPaper');
    expect(receiptPaper, findsOneWidget);

    // Marker audit method mentah TIDAK BOLEH tampil di struk gambar
    // (case-sensitive lowercase — beda dari label tombol "Retur Barang"
    // berhuruf kapital, yang memang di layar lain/tak disentuh test ini).
    expect(
        find.descendant(
            of: receiptPaper, matching: find.textContaining('retur')),
        findsNothing,
        reason: 'marker audit "retur" (amount 0) tidak boleh tampil di '
            'timeline struk gambar');

    // Timeline pembayaran ASLI (2 cicilan tunai sungguhan) tetap tampil.
    expect(
        find.descendant(of: receiptPaper, matching: find.text('Pembayaran:')),
        findsOneWidget);
    expect(
        find.descendant(
            of: receiptPaper, matching: find.textContaining('Tunai')),
        findsWidgets,
        reason: '2 cicilan tunai asli harus tetap tampil apa adanya');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
