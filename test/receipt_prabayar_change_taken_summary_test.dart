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

/// Bug lanjutan dilaporkan user (screenshot): Pra-Bayar dikunci, kembalian
/// diambil SEBELUM checkout (`prabayarChangeTakenBeforeCheckout`, kolom
/// terpisah dari `changeGiven` momen checkout) — struk in-app: "Total" &
/// "Dibayar" ringkasan atas SAMA-SAMA persis Total, TANPA baris "Kembalian"
/// sama sekali, padahal Riwayat Pembayaran (SUDAH benar sejak fix
/// `191570c`) menampilkan nominal gross + catatan "sudah diambil sebelum
/// checkout". Root cause: `dibayarDisplay` dipanggil dgn
/// `_latestPayment?.changeGiven` SAJA, tidak pernah menjumlah
/// `prabayarChangeTakenBeforeCheckout`. Fix: `_kembalianGabungan`
/// (`_ReceiptScreenState`) / `kembalianGabungan` (`_ReceiptPaper`) /
/// `kembalianGabungan` (`printer_service.dart`) menjumlah KEDUA komponen.
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

  group('in-app — Ringkasan atas', () {
    testWidgets(
        'SKENARIO DILAPORKAN USER: Pra-Bayar, kembalian HANYA dari '
        'pre-checkout (tanpa kembalian momen checkout) — Dibayar HARUS '
        'gross (match Riwayat Pembayaran) + baris Kembalian breakdown '
        'pre-checkout HARUS muncul', (tester) async {
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

      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: txId));

      // BUG: sebelum fix, ini akan "Tunai · Rp 425.400" (= Total, salah).
      expect(find.text('Tunai · ${formatRupiah(426000)}'), findsOneWidget,
          reason: 'Dibayar Ringkasan atas HARUS gross, match Riwayat '
              'Pembayaran (Tunai Rp 426.000)');
      expect(find.text('Tunai · ${formatRupiah(425400)}'), findsNothing,
          reason: 'Dibayar TIDAK BOLEH = Total (bug dilaporkan user)');
      expect(
          find.textContaining('Kembalian (sebelum checkout, sudah diambil)'),
          findsOneWidget,
          reason: 'baris breakdown Kembalian pre-checkout HARUS muncul di '
              'Ringkasan atas');
      expect(find.text(formatRupiah(600)), findsWidgets,
          reason: 'nominal kembalian pre-checkout (600) HARUS tampil');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets(
        'REGRESI: kembalian NORMAL momen checkout (bukan Pra-Bayar) — '
        'perilaku TIDAK BERUBAH (gross+Kembalian spt sebelumnya), TANPA '
        'baris breakdown pre-checkout', (tester) async {
      const txId = 'tx1';
      await insertTx(id: txId, total: 10000, paid: 15000);
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay1',
              transactionId: txId,
              amount: 15000,
              method: 'tunai',
              paidAt: Value(DateTime(2026, 9, 9, 10, 0)),
              changeGiven: const Value(5000)));

      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: txId));

      expect(find.text('Tunai · ${formatRupiah(15000)}'), findsOneWidget);
      expect(find.text('Kembalian'), findsWidgets,
          reason: 'baris Kembalian checkout-moment (dgn checkbox) tetap ada');
      expect(
          find.textContaining('Kembalian (sebelum checkout, sudah diambil)'),
          findsNothing,
          reason: 'tanpa metadata pre-checkout, breakdown row TIDAK muncul');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets(
        'KOMBINASI: kembalian pre-checkout Pra-Bayar DAN kembalian momen '
        'checkout SEKALIGUS — KEDUA komponen ikut terhitung benar '
        '(Dibayar = Total + jumlah keduanya), kedua baris muncul terpisah',
        (tester) async {
      const txId = 'tx1';
      await insertTx(id: txId, total: 100000, paid: 100600);
      // Baris Pra-Bayar lebih awal — kembalian 600 diambil SEBELUM checkout.
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay1',
              transactionId: txId,
              amount: 50600,
              method: 'tunai',
              paidAt: Value(DateTime(2026, 9, 9, 9, 0)),
              prabayarChangeTakenBeforeCheckout: const Value(600)));
      // Baris TERAKHIR — kembalian momen checkout 1.000 (BISA ditoggle).
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay2',
              transactionId: txId,
              amount: 50000,
              method: 'tunai',
              paidAt: Value(DateTime(2026, 9, 9, 10, 0)),
              changeGiven: const Value(1000)));

      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: txId));

      // 100.000 (total) + 1.000 (checkout-moment) + 600 (pre-checkout).
      expect(find.text('Tunai · ${formatRupiah(101600)}'), findsOneWidget,
          reason: 'Dibayar HARUS gabungan kedua komponen kembalian');
      // Baris "Kembalian" checkout-moment (checkbox, amount 1.000).
      expect(find.text('Kembalian'), findsWidgets);
      expect(find.text(formatRupiah(1000)), findsWidgets);
      // Baris breakdown pre-checkout (amount 600) TERPISAH, tanpa checkbox.
      expect(
          find.textContaining('Kembalian (sebelum checkout, sudah diambil)'),
          findsOneWidget);
      expect(find.text(formatRupiah(600)), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  group('share/gambar — _ReceiptPaper', () {
    testWidgets(
        'SKENARIO DILAPORKAN USER: struk gambar juga HARUS tampilkan '
        'baris "Kembali" (600) & "Bayar.." gross (426.000)', (tester) async {
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

      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: txId));
      await tester.tap(find.byTooltip('Bagikan Struk'));
      await tester.pumpAndSettle();

      expect(find.text('Rp ${_fmt(426000)}'), findsWidgets,
          reason: '"Bayar.." HARUS gross 426.000, bukan 425.400');
      expect(find.text('Kembali'), findsOneWidget,
          reason: 'baris "Kembali" HARUS muncul (sebelum fix: tidak pernah '
              'muncul sama sekali krn latestChangeGiven-nya 0)');
      expect(find.text('Rp ${_fmt(600)}'), findsWidgets,
          reason: 'nominal Kembali HARUS 600 (dari pre-checkout Pra-Bayar)');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets(
        'KOMBINASI di struk gambar: kedua komponen kembalian dijumlah benar '
        '(1.600)', (tester) async {
      const txId = 'tx1';
      await insertTx(id: txId, total: 100000, paid: 100600);
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay1',
              transactionId: txId,
              amount: 50600,
              method: 'tunai',
              paidAt: Value(DateTime(2026, 9, 9, 9, 0)),
              prabayarChangeTakenBeforeCheckout: const Value(600)));
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay2',
              transactionId: txId,
              amount: 50000,
              method: 'tunai',
              paidAt: Value(DateTime(2026, 9, 9, 10, 0)),
              changeGiven: const Value(1000)));

      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: txId));
      await tester.tap(find.byTooltip('Bagikan Struk'));
      await tester.pumpAndSettle();

      expect(find.text('Kembali'), findsOneWidget);
      expect(find.text('Rp ${_fmt(1600)}'), findsWidgets,
          reason: 'Kembali gabungan = 1.000 (checkout) + 600 (pre-checkout)');
      expect(find.text('Rp ${_fmt(101600)}'), findsWidgets,
          reason: '"Bayar.." = Total(100.000) + Kembali gabungan(1.600)');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  group('cetak ESC/POS — printer_service.dart', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test(
        'SKENARIO DILAPORKAN USER: struk cetak tunggal HARUS tampilkan '
        '"Kembali" (600) & "Bayar" gross (426.000)', () async {
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

      expect(text.contains('Kembali'), isTrue,
          reason: 'baris Kembali HARUS tercetak (sebelum fix: tidak pernah '
              'krn latestWithChange null)');
      expect(text.contains('Rp 600'), isTrue,
          reason: 'nominal Kembali HARUS 600');
      expect(text.contains('Rp 426,000'), isTrue,
          reason: 'Bayar HARUS gross 426.000');
      final bayarIdx = text.indexOf('Bayar');
      final bayarLineEnd = text.indexOf('\n', bayarIdx);
      final bayarLine =
          text.substring(bayarIdx, bayarLineEnd < 0 ? text.length : bayarLineEnd);
      expect(bayarLine.contains('425,400'), isFalse,
          reason: 'baris Bayar TIDAK BOLEH = Total (bug dilaporkan user)');
    });

    test(
        'KOMBINASI cetak tunggal: kedua komponen kembalian dijumlah benar '
        '(1.600)', () async {
      const txId = 'tx1';
      await insertTx(id: txId, total: 100000, paid: 100600);
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay1',
              transactionId: txId,
              amount: 50600,
              method: 'tunai',
              paidAt: Value(DateTime(2026, 9, 9, 9, 0)),
              prabayarChangeTakenBeforeCheckout: const Value(600)));
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay2',
              transactionId: txId,
              amount: 50000,
              method: 'tunai',
              paidAt: Value(DateTime(2026, 9, 9, 10, 0)),
              changeGiven: const Value(1000)));

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

      expect(text.contains('Rp 1,600'), isTrue,
          reason: 'Kembali gabungan = 1.000 + 600');
      expect(text.contains('Rp 101,600'), isTrue,
          reason: 'Bayar = Total(100.000) + Kembali gabungan(1.600)');
    });
  });
}

// `_ReceiptPaper._fmtNum` pakai TITIK sbg pemisah ribuan (gaya Indonesia) —
// cocokkan persis format widget yang sedang diuji di sini (lihat juga
// `receipt_paper_kembali_net_test.dart`).
String _fmt(int amount) {
  final s = amount.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}
