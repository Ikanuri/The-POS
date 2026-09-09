import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Fitur Pra-Bayar (susulan, permintaan user) — kembalian yang terjadi
/// SELAMA FASE PRA-BAYAR (sebelum checkout, checkbox "kembalian sudah
/// diambil" di footer keranjang) sekarang tercatat sbg METADATA
/// `TransactionPayments.prabayarChangeTakenBeforeCheckout` (diisi oleh
/// `buildPrabayarCheckout`, lihat `payment_prabayar_checkout_test.dart` utk
/// test pure-function-nya) — kartu "Riwayat Pembayaran" in-app WAJIB
/// menampilkan baris keterangan tambahan utk baris pembayaran yang
/// membawa metadata ini, dgn kalimat yg SECARA EKSPLISIT beda dari
/// kembalian normal (`_ChangeTakenRow`) supaya tidak tertukar makna.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> insertTx() => db.into(db.transactions).insert(
      TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 60000,
          paid: 60000,
          changeAmount: 0,
          paymentMethod: 'tunai'));

  Future<void> insertItem() => db.into(db.transactionItems).insert(
      TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 60000,
          originalPrice: 60000,
          subtotal: 60000));

  testWidgets(
      'baris pembayaran yg bawa prabayarChangeTakenBeforeCheckout '
      'menampilkan baris keterangan "sudah diambil sebelum checkout"',
      (tester) async {
    await insertTx();
    await insertItem();
    // Entri Pra-Bayar 40rb, dipotong 10rb (sudah diambil kembali sebelum
    // checkout) jadi baris amount efektif 30rb.
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: 'tx1',
            amount: 30000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 1, 1, 10, 0)),
            prabayarChangeTakenBeforeCheckout: const Value(10000)));
    // Baris "sekarang" — tidak kena potongan, TIDAK boleh dapat baris
    // keterangan ini.
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay2',
            transactionId: 'tx1',
            amount: 30000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 1, 2, 12, 0))));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.text('Riwayat Pembayaran'), findsOneWidget);
    expect(
        find.textContaining(
            'Kembalian ${formatRupiah(10000)} sudah diambil sebelum checkout'),
        findsOneWidget);

    // Drain — hindari StreamProvider hang (lihat CLAUDE.md §Gotcha).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tanpa metadata (null/0): baris keterangan TIDAK muncul sama sekali',
      (tester) async {
    await insertTx();
    await insertItem();
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: 'tx1',
            amount: 60000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 1, 1, 10, 0))));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.textContaining('sudah diambil sebelum checkout'),
        findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'skenario BUG DILAPORKAN USER (screenshot keranjang & struk): '
      'nominal utama HARUS "Tunai Rp 426.000" (BUKAN Rp 425.400 hasil '
      'potongan diam-diam), dgn catatan kembalian Rp 600 TERPISAH di bawahnya',
      (tester) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx1',
        localId: 'K1-1',
        status: 'lunas',
        total: 425400,
        paid: 425400,
        changeAmount: 0,
        paymentMethod: 'tunai'));
    await db.into(db.transactionItems).insert(
        TransactionItemsCompanion.insert(
            id: 'ti1',
            transactionId: 'tx1',
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: 425400,
            originalPrice: 425400,
            subtotal: 425400));
    // Persis skenario user: Pra-Bayar dikunci Rp426.000, kembalian Rp600
    // diambil SEBELUM checkout — `amount` tersimpan HARUS gross (426.000),
    // potongannya metadata terpisah (fix `buildPrabayarCheckout`).
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: 'tx1',
            amount: 426000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 9, 9, 10, 0)),
            prabayarChangeTakenBeforeCheckout: const Value(600)));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.textContaining(formatRupiah(426000)), findsWidgets,
        reason: 'nominal utama Riwayat Pembayaran HARUS tampil sbg 426.000, '
            'BUKAN 425.400 (426.000 dipotong diam-diam 600)');
    expect(
        find.textContaining(
            'Kembalian ${formatRupiah(600)} sudah diambil sebelum checkout'),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
