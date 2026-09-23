import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/printer_service.dart';

/// Bug dilaporkan user (screenshot struk cetak ESC/POS): kembalian yang
/// SUDAH dicentang "sudah diambil/dipakai" di ronde SEBELUMNYA tetap
/// tercetak lagi kalau ronde SETELAHNYA (Tambah Belanjaan) kebetulan tidak
/// menyisakan kembalian baru — baris "Kembali" basi tercetak BERSAMAAN
/// dengan "Sisa" yang genuinely masih kurang. Skenario PERSIS struk yang
/// dilaporkan: checkout awal Rp73.750 dibayar Rp80.000 (kembalian Rp6.250,
/// DICENTANG diambil) -> Tambah Belanjaan Rp9.000, dibayar Rp6.250 (uang
/// kembalian lama dipakai ulang) -> sisa Rp2.750 genuinely belum terbayar.
void main() {
  late AppDatabase db;
  const txId = 'tx1';
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'ESC/POS struk tunggal: "Kembali" TIDAK tercetak lagi setelah '
      'dicentang, "Sisa" tercetak sendirian', () async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-25',
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

    // Checkout awal: bayar 80.000 utk 73.750 -> kembalian 6.250, dicentang
    // "sudah diambil".
    await db.addPaymentToTransaction(
        txId: txId, amount: 80000, method: 'tunai', kasirId: 'K1');
    final firstPay = (await db.getPaymentsForTx(txId)).single;
    expect(firstPay.changeGiven, 6250, reason: 'sanity check');
    await (db.update(db.transactionPayments)
          ..where((t) => t.id.equals(firstPay.id)))
        .write(const TransactionPaymentsCompanion(changeTaken: Value(true)));

    // Tambah Belanjaan 9.000, dibayar 6.250 (kembalian lama dipakai ulang)
    // -> sisa 2.750 genuinely belum terbayar.
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
    final items = await (db.select(db.transactionItems)
          ..where((i) => i.transactionId.equals(txId)))
        .get();
    final payments = await db.getPaymentsForTx(txId);
    expect(tx.total, 82750);
    expect(tx.status, 'kurang_bayar', reason: 'sanity check');

    final bytes = await PrinterService.debugBuildBytes(
      tx: tx,
      items: items,
      productNames: const {'P0': 'Rinso', 'P1': 'Malkist'},
      unitNames: const {'U0': 'pak', 'U1': 'ret'},
      customer: null,
      storeName: 'Toko Berkah',
      storeAddress: '',
      storePhone: '',
      strukNote: null,
      payments: payments,
      settings: const PrinterSettings(),
    );
    final text = latin1.decode(bytes, allowInvalid: true);

    expect(text.contains('Kembali'), isFalse,
        reason: 'tanpa fix: kembalian 6.250 yg sudah dicentang/dipakai '
            'tercetak lagi seolah masih harus diserahkan');
    expect(text.contains('Sisa'), isTrue,
        reason: 'sisa genuinely masih harus dibayar, TETAP harus tercetak');
    // ESC/POS (_fmtNum) pakai koma sbg pemisah ribuan, beda dari format
    // Indonesia titik yg dipakai in-app/share (formatRupiah).
    expect(text.contains('2,750'), isTrue);
  });
}
