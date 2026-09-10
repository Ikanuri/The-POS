import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/printer_service.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Bug dilaporkan user (kata-kata persis): "ketika kembalian dari pre-paid
/// sudah diambil, kemudian paid, dan ternyata tambah barang dan ada
/// kembalian, total kembalian dihitung bahkan dari fase pre-paid (yang
/// tentu uang itu sudah di pelanggan)." Ronde checkout ASLI (Pra-Bayar,
/// potongan pre-checkout SUDAH diberikan ke pelanggan & SUDAH tuntas
/// tercatat di baris Riwayat Pembayaran-nya sendiri) tidak boleh lagi
/// disumbangkan ke ringkasan "Kembalian" SAAT INI begitu ada ronde "Tambah
/// Belanjaan" (`note == 'Tambah belanjaan'`, ditulis oleh
/// `_confirmAddItems` di payment_screen.dart) berikutnya pada nota yang
/// SAMA — root cause & fix: `totalPrabayarChangeTakenBeforeCheckout` /
/// `_hasLaterAddItemsRound` di receipt_screen.dart, duplikat inline di
/// printer_service.dart (struk tunggal & gabungan).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> insertTx(
      {required String id,
      required int total,
      required int paid,
      String status = 'lunas'}) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: 'K1-1',
          status: status,
          total: total,
          paid: paid,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: '$id-i0',
        transactionId: id,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: total,
        originalPrice: total,
        subtotal: total));
  }

  /// Ronde ASLI: Pra-Bayar, potongan pre-checkout 105.150 SUDAH diambil
  /// pelanggan. Ronde KEDUA: "Tambah Belanjaan", changeGiven 115.750 milik
  /// ronde ini sendiri (TIDAK PERNAH bawa `prabayarChangeTakenBeforeCheckout`
  /// — field itu eksklusif milik ronde checkout asli).
  Future<void> insertOriginalPrabayarRoundThenAddItemsRound(String txId,
      {required int prabayarCut, required int addItemsChangeGiven}) async {
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay-original',
            transactionId: txId,
            amount: 300000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 9, 9, 10, 0)),
            prabayarChangeTakenBeforeCheckout: Value(prabayarCut)));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay-tambah-belanjaan',
            transactionId: txId,
            amount: 50000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 9, 9, 11, 0)),
            changeGiven: Value(addItemsChangeGiven),
            note: const Value('Tambah belanjaan')));
  }

  group('totalPrabayarChangeTakenBeforeCheckout (fungsi murni)', () {
    test(
        'SKENARIO DILAPORKAN USER: begitu ada ronde Tambah Belanjaan, '
        'potongan pre-checkout ronde ASLI TIDAK ikut dihitung lagi (harus 0)',
        () async {
      const txId = 'tx1';
      await insertTx(id: txId, total: 250000, paid: 350000);
      await insertOriginalPrabayarRoundThenAddItemsRound(txId,
          prabayarCut: 105150, addItemsChangeGiven: 115750);

      final payments = await db.getPaymentsForTx(txId);

      expect(totalPrabayarChangeTakenBeforeCheckout(payments), 0,
          reason: 'BUG: sebelum fix ini akan 105150 (potongan pre-checkout '
              'ronde ASLI yang sudah diberikan ke pelanggan), bukan 0');
    });

    test(
        'REGRESI: tanpa ronde Tambah Belanjaan (satu ronde Pra-Bayar saja) — '
        'potongan pre-checkout TETAP dihitung spt sebelumnya (commit 22ba425)',
        () async {
      const txId = 'tx1';
      await insertTx(id: txId, total: 425400, paid: 426000);
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay1',
              transactionId: txId,
              amount: 426000,
              method: 'tunai',
              paidAt: Value(DateTime(2026, 9, 9, 10, 0)),
              prabayarChangeTakenBeforeCheckout: const Value(600)));

      final payments = await db.getPaymentsForTx(txId);

      expect(totalPrabayarChangeTakenBeforeCheckout(payments), 600,
          reason: 'perilaku lama (fix 22ba425) TIDAK BOLEH berubah tanpa '
              'ronde Tambah Belanjaan');
    });
  });

  group('in-app — Ringkasan atas', () {
    testWidgets(
        'SKENARIO DILAPORKAN USER: Kembalian Ringkasan atas HANYA dari '
        'ronde Tambah Belanjaan (115.750), TIDAK ditambah potongan '
        'pre-checkout ronde asli (105.150)', (tester) async {
      const txId = 'tx1';
      await insertTx(id: txId, total: 250000, paid: 350000);
      await insertOriginalPrabayarRoundThenAddItemsRound(txId,
          prabayarCut: 105150, addItemsChangeGiven: 115750);

      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: txId));

      // Baris breakdown "Kembalian (sebelum checkout, sudah diambil)" TIDAK
      // BOLEH muncul lagi — ronde asli sudah historis/tuntas.
      expect(
          find.textContaining('Kembalian (sebelum checkout, sudah diambil)'),
          findsNothing,
          reason: 'BUG: potongan pre-checkout ronde ASLI yang sudah selesai '
              'tidak boleh nongol lagi di Ringkasan atas ronde berjalan');
      // Nominal 105.150 (ronde asli) TIDAK BOLEH muncul di baris Kembalian.
      expect(find.text(formatRupiah(220900)), findsNothing,
          reason: 'BUG: 115.750 + 105.150 = 220.900 TIDAK BOLEH jadi total '
              'Kembalian yang ditampilkan');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  group('cetak ESC/POS — printer_service.dart (struk tunggal)', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test(
        'SKENARIO DILAPORKAN USER: struk cetak Kembali/Bayar HANYA dari '
        'ronde Tambah Belanjaan, TIDAK ikut potongan pre-checkout ronde asli',
        () async {
      const txId = 'tx1';
      await insertTx(id: txId, total: 250000, paid: 350000);
      await insertOriginalPrabayarRoundThenAddItemsRound(txId,
          prabayarCut: 105150, addItemsChangeGiven: 115750);

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(txId)))
          .getSingle();
      final items = await (db.select(db.transactionItems)
            ..where((i) => i.transactionId.equals(txId)))
          .get();
      final payments = await db.getPaymentsForTx(txId);

      final bytes = await PrinterService.debugBuildBytes(
        tx: tx,
        items: items,
        productNames: const {'P0': 'Produk'},
        unitNames: const {'U0': 'pcs'},
        customer: null,
        storeName: 'Toko A',
        storeAddress: '',
        storePhone: '',
        strukNote: null,
        payments: payments,
        settings: const PrinterSettings(),
      );
      final text = latin1.decode(bytes, allowInvalid: true);

      // BUG lama: kembalian gabungan akan 115.750 + 105.150 = 220.900.
      expect(text.contains('Rp 220,900'), isFalse,
          reason: 'BUG: potongan pre-checkout ronde ASLI (105.150) TIDAK '
              'BOLEH ikut dijumlah ke Kembali struk cetak');
    });
  });
}
