import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Bug dilaporkan user (screenshot): kembalian yang SUDAH dicentang "sudah
/// diambil/dipakai" (checkbox `changeTaken`) di ronde SEBELUMNYA tetap
/// muncul lagi di struk cetak/share kalau ronde SETELAHNYA (mis. Tambah
/// Belanjaan) kebetulan `changeGiven`-nya 0 — baris "Kembali" basi tampil
/// BERSAMAAN dengan "Sisa" yang genuinely masih kurang, padahal uang
/// kembalian itu sudah selesai urusannya (sudah diberikan, atau sudah
/// dipakai motong tagihan tambahan). Skenario PERSIS struk yang dilaporkan:
/// checkout awal Rp73.750 dibayar Rp80.000 (kembalian Rp6.250, DICENTANG
/// diambil) -> Tambah Belanjaan Rp9.000, dibayar Rp6.250 (memakai kembalian
/// lama, uang fisiknya bukan uang baru) -> sisa Rp2.750 genuinely belum
/// terbayar.
///
/// `latestChangeGiven` (dipakai share `_ReceiptPaper`) & pola sepadan di
/// `printer_service.dart` (cetak ESC/POS, struk tunggal & gabungan) SEKARANG
/// melewati baris yang `changeTaken`-nya sudah dicentang saat mencari
/// kembalian yang PALING AKHIR & MASIH aktif.
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> seedScenario() async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'kurang_bayar',
          total: 73750,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 73750,
        originalPrice: 73750,
        subtotal: 73750));

    // Checkout awal: bayar 80.000 utk 73.750 -> kembalian 6.250.
    await db.addPaymentToTransaction(
        txId: txId, amount: 80000, method: 'tunai', kasirId: 'K1');
    final firstPay = (await db.getPaymentsForTx(txId)).single;
    expect(firstPay.changeGiven, 6250, reason: 'sanity check');

    // Kasir mencentang "kembalian sudah diambil/dipakai" SEBELUM tambahan
    // barang berikutnya (persis `_toggleChangeTaken`/
    // `_toggleUnclaimedChangeTaken`).
    await (db.update(db.transactionPayments)
          ..where((t) => t.id.equals(firstPay.id)))
        .write(const TransactionPaymentsCompanion(changeTaken: Value(true)));

    // Tambah Belanjaan 9.000, dibayar 6.250 (uang kembalian lama dipakai
    // ulang) -> sisa 2.750 genuinely belum terbayar.
    await db.addItemsToTransaction(
      txId: txId,
      items: [
        TransactionItemsCompanion.insert(
            id: 'i1',
            transactionId: txId,
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: 9000,
            originalPrice: 9000,
            subtotal: 9000),
      ],
      stockItems: const [],
      payment: TransactionPaymentsCompanion.insert(
          id: 'payAdd',
          transactionId: txId,
          amount: 6250,
          method: 'tunai',
          note: const Value('Tambah belanjaan')),
    );

    final tx = await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
        .getSingle();
    expect(tx.total, 82750);
    expect(tx.status, 'kurang_bayar');
    return txId;
  }

  test(
      'latestChangeGiven (fungsi murni, dipakai share) melewati baris yg '
      'changeTaken=true, TIDAK resurface kembalian basi', () async {
    await seedScenario();
    final payments = await db.getPaymentsForTx(txId);
    final tx = await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
        .getSingle();

    expect(latestChangeGiven(payments), 0,
        reason: 'tanpa fix: kembalian basi 6.250 (sudah dicentang) '
            'ditemukan lagi krn ronde tambahan changeGiven-nya 0');
    expect(netRemainingOwed(tx, payments), 2750,
        reason: 'sisa genuinely masih harus dibayar, TIDAK boleh berubah');
  });

  testWidgets(
      'struk gambar (_ReceiptPaper): "Kembali" TIDAK muncul lagi setelah '
      'dicentang, "Sisa" TETAP tampil sendirian', (tester) async {
    await seedScenario();

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    expect(find.text('Kembali'), findsNothing,
        reason: 'tanpa fix: kembalian 6.250 yg sudah dicentang/dipakai '
            'tampil lagi seolah masih harus diserahkan (baris ringkasan '
            '"Kembali", BEDA dari nominal Rp6.250 yg legitimately tampil '
            'di baris Riwayat Pembayaran sbg jumlah pembayaran tambahan)');
    expect(find.text('Sisa'), findsWidgets);
    expect(find.text('Rp ${_fmt(2750)}'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

String _fmt(int amount) {
  final s = amount.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}
