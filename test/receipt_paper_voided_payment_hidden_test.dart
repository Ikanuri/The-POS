import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Dilaporkan user (foto struk kertas): pembayaran yang DIBATALKAN
/// (`transactionPayments.voided = true`, mis. salah input nominal lalu
/// dibatalkan & diulang) ikut tercetak di struk fisik & struk gambar
/// (share) sbg baris "Tunai" biasa — kertas termal tidak bisa menampilkan
/// coretan "Dibatalkan" spt kartu Riwayat Pembayaran in-app, jadi pelanggan
/// melihat 3x "Tunai Rp150.000" identik tanpa tahu 2 di antaranya batal,
/// seolah dibayar 3x. Akar: `_visiblePayments` (_ReceiptPaper, dipakai
/// share) & `visiblePayments` (printer_service.dart, dipakai cetak fisik)
/// sudah filter method 'edit'/'retur' tapi LUPA filter `voided` — beda dari
/// `_refundTotal`/`_refundMethod` di file yang sama yang sudah benar. Fix:
/// tambahkan `!p.voided` di kedua tempat; in-app (kartu Riwayat Pembayaran,
/// jalur BERBEDA) SENGAJA tetap tampilkan semua dgn coretan.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'struk gambar (_ReceiptPaper): pembayaran dibatalkan TIDAK tampil di '
      'timeline, pembayaran yang masih berlaku tetap tampil',
      (tester) async {
    const txId = 'tx1';
    final t0 = DateTime(2026, 7, 26, 7, 6);
    final t1 = DateTime(2026, 7, 26, 7, 7);

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 100000,
          paid: 100000,
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

    // Pembayaran pertama (salah input) - lalu dibatalkan.
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: txId,
            amount: 150000,
            method: 'tunai',
            paidAt: Value(t0)));
    await db.voidPayment('pay1');

    // Pembayaran kedua (uang SUNGGUHAN, yang benar-benar berlaku).
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay2',
            transactionId: txId,
            amount: 100000,
            method: 'tunai',
            paidAt: Value(t1)));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    final receiptPaper = find
        .byWidgetPredicate((w) => w.runtimeType.toString() == '_ReceiptPaper');
    expect(receiptPaper, findsOneWidget);

    // Timeline pembayaran hanya boleh punya SATU baris "Rp150.000" — angka
    // pembayaran yang dibatalkan tidak boleh muncul sama sekali di sini.
    expect(
        find.descendant(
            of: receiptPaper, matching: find.textContaining('150.000')),
        findsNothing,
        reason: 'pembayaran yang dibatalkan (Rp150.000) tidak boleh ikut '
            'tercetak/ter-share, hanya boleh tampil di in-app struk');
    expect(
        find.descendant(
            of: receiptPaper, matching: find.textContaining('100.000')),
        findsWidgets,
        reason: 'pembayaran yang masih berlaku tetap harus tampil');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
