import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Bug dilaporkan user: di struk cetak/gambar (_ReceiptPaper — muncul lewat
/// tombol "Bagikan Struk"), baris "Kembali" pakai `tx.changeAmount` mentah —
/// beda dari Ringkasan on-screen (sudah diperbaiki, pakai `_latestPayment.
/// changeGiven`) & nota gabungan (sudah diperbaiki, pakai `latestWithChange.
/// changeGiven`). Saat kembalian lama dipakai ulang jadi pembayaran baru
/// (mis. tambah belanjaan), `tx.changeAmount` mengakumulasi SELURUH riwayat
/// kembalian nota, bukan cuma yang baru saja diberikan — user minta
/// "tampilkan kembalian TERAKHIR, jangan akumulasi".
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'struk gambar (_ReceiptPaper) tampilkan Kembali dari pembayaran '
      'TERAKHIR (5.000), BUKAN tx.changeAmount akumulasi (15.000)',
      (tester) async {
    const txId = 'tx1';
    // Nota awal: total 50.000, bayar 60.000 -> kembalian pay1 = 10.000.
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 50000,
          paid: 60000,
          changeAmount: 10000,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 50000,
        originalPrice: 50000,
        subtotal: 50000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: txId,
            amount: 60000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 7, 18, 8, 0)),
            changeGiven: const Value(10000)));

    // Tambah belanjaan 5.000 (total jadi 55.000), bayar 10.000 (reuse penuh
    // kembalian pay1) -> kembalian pay2 = 5.000 (10.000 pay2 - 5.000
    // kebutuhan tambahan). Tapi tx.changeAmount hasil reconcile = Σamount
    // (60000+10000=70000) - total(55000) = 15.000 — AKUMULASI, beda dari
    // kembalian pembayaran terakhir yang sesungguhnya (5.000).
    await db.addItemsToTransaction(
      txId: txId,
      items: [
        TransactionItemsCompanion.insert(
            id: 'i1',
            transactionId: txId,
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: 5000,
            originalPrice: 5000,
            subtotal: 5000),
      ],
      stockItems: const [],
      payment: TransactionPaymentsCompanion.insert(
        id: 'pay2',
        transactionId: txId,
        amount: 10000,
        method: 'tunai',
        paidAt: Value(DateTime(2026, 7, 18, 8, 5)),
      ),
      kasirId: 'K1',
    );

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    // Sanity check angka skenario sebelum verifikasi UI.
    expect(tx.total, 55000);
    expect(tx.changeAmount, 15000,
        reason: 'tx.changeAmount (header) memang AKUMULASI — inilah yg '
            'harus TIDAK dipakai lagi buat tampilan');
    final payments = await db.getPaymentsForTx(txId);
    final pay2 = payments.firstWhere((p) => p.id == 'pay2');
    expect(pay2.changeGiven, 5000,
        reason: 'kembalian pembayaran TERAKHIR yang sesungguhnya');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    // Struk gambar HARUS tampilkan kembalian pembayaran TERAKHIR (5.000),
    // BUKAN tx.changeAmount akumulasi (15.000).
    expect(find.text('Rp ${_fmt(5000)}'), findsWidgets,
        reason: 'kembalian yang benar (pembayaran terakhir)');
    expect(find.text('Rp ${_fmt(15000)}'), findsNothing,
        reason: 'tx.changeAmount akumulasi TIDAK BOLEH tampil sbg Kembali');
  });
}

// `_ReceiptPaper._fmtNum` pakai TITIK sbg pemisah ribuan (gaya Indonesia),
// BEDA dari `printer_service.dart._fmtNum` yang pakai koma — cocokkan
// persis format widget yang sedang diuji di sini.
String _fmt(int amount) {
  final s = amount.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}
