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

/// Item 67 — bug nyata dilaporkan user (screenshot): kartu "Riwayat
/// Pembayaran" (in-app) hanya menampilkan `_payments` APA ADANYA (uang
/// pelunasan hutang/pre-order sungguhan tercatat sbg `transaction_payments`
/// di nota SUMBER, bukan nota ini) — padahal "Dibayar" di Ringkasan atas
/// SUDAH lama menjumlahkan `_debtSettlementTotal` (lihat
/// `receipt_debt_settlement_total_paid_test.dart`). Dua angka di layar yang
/// SAMA jadi tidak saling menjumlah tanpa penjelasan.
///
/// Fix: baris pembayaran PALING AWAL (momen checkout — SAMA persis dgn
/// nominal yg diketik kasir di kalkulator sekali jalan) di ketiga jenis
/// struk (in-app, share/gambar, cetak) digabung tampilannya dgn
/// `_debtSettlementTotal`, MURNI tampilan — `p.amount`/DB tidak disentuh.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  TestWidgetsFlutterBinding.ensureInitialized();

  /// Nota lunas: item Rp 212.400 + Lunasi Nota #16 Rp 690.000 (Dibayar
  /// gabungan = Rp 902.400), SATU pembayaran Rp 212.400 tercatat di nota
  /// ini (paidAt beda dari createdAt supaya timeline share/cetak ikut
  /// tampil — lihat `_showTimeline`/`showTimeline`).
  Future<void> seedLunasWithDebtSettlement() async {
    const txId = 'tx1';
    final detail = jsonEncode([
      {
        'invoiceId': 'old16',
        'invoiceLocalId': 'K1-20260901-0016',
        'invoiceDate': DateTime(2026, 9, 1).millisecondsSinceEpoch,
        'amount': 690000,
        'customerName': 'Budi',
      },
    ]);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-2',
          status: 'lunas',
          total: 212400,
          paid: 212400,
          changeAmount: 0,
          paymentMethod: 'tunai',
          debtSettlementDetail: Value(detail),
          createdAt: Value(DateTime(2026, 9, 7, 7, 0)),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 212400,
        originalPrice: 212400,
        subtotal: 212400));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: txId,
            amount: 212400,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 9, 7, 8, 0))));
  }

  testWidgets(
      'in-app: baris Riwayat Pembayaran PALING AWAL menampilkan gabungan '
      'item + nota hutang (Rp 212.400 + Rp 690.000 = Rp 902.400), sama '
      'dgn "Dibayar" di Ringkasan atas', (tester) async {
    await seedLunasWithDebtSettlement();
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));
    await tester.pumpAndSettle();

    // "Dibayar" (Ringkasan atas) DAN baris Riwayat Pembayaran SEKARANG
    // sama-sama menampilkan Rp 902.400 — tidak ada lagi selisih tak
    // terjelaskan di layar yang sama.
    expect(find.textContaining(formatRupiah(902400)), findsNWidgets(3),
        reason: '"Total", "Dibayar", DAN baris Riwayat Pembayaran harus '
            'sama-sama mengandung nominal gabungan Rp 902.400');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'share/gambar (_ReceiptPaper): baris timeline "Pembayaran:" gabung '
      'item + nota hutang', (tester) async {
    await seedLunasWithDebtSettlement();
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    expect(find.text('Rp ${_fmtNum(902400)}'), findsNWidgets(3),
        reason: 'Total, Bayar.., DAN baris timeline "Pembayaran:" harus '
            'sama-sama Rp 902.400');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  test(
      'cetak ESC/POS: baris "Pembayaran:" gabung item + nota hutang, bukan '
      'nominal item mentah', () async {
    await seedLunasWithDebtSettlement();
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    final items = await (db.select(db.transactionItems)
          ..where((i) => i.transactionId.equals('tx1')))
        .get();
    final payments = await db.getPaymentsForTx('tx1');

    final bytes = await PrinterService.debugBuildBytes(
      tx: tx,
      items: items,
      productNames: const {'P0': 'Indomie'},
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

    final pembayaranIdx = text.indexOf('Pembayaran:');
    expect(pembayaranIdx, greaterThan(-1),
        reason: 'timeline "Pembayaran:" harus tercetak (paidAt beda dari '
            'createdAt)');
    final timelineSection =
        text.substring(pembayaranIdx, pembayaranIdx + 80);
    expect(timelineSection.contains('Rp ${_fmtNumComma(902400)}'), isTrue,
        reason: 'baris pembayaran di timeline cetak harus gabungan '
            '(Rp 902.400), bukan cuma item (Rp 212.400)');
    expect(timelineSection.contains('Rp ${_fmtNumComma(212400)}'), isFalse,
        reason: 'nominal item mentah tidak boleh lagi tercetak sendirian '
            'di baris timeline');
  });

  testWidgets(
      'DUA pembayaran (cicilan): HANYA baris PALING AWAL yg digabung, '
      'baris kedua TETAP nominal aslinya (tidak dobel-hitung)',
      (tester) async {
    const txId = 'tx2';
    final detail = jsonEncode([
      {
        'invoiceId': 'old17',
        'invoiceLocalId': 'K1-20260901-0017',
        'invoiceDate': DateTime(2026, 9, 1).millisecondsSinceEpoch,
        'amount': 690000,
        'customerName': 'Sari',
      },
    ]);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-5',
          status: 'lunas',
          total: 212400,
          paid: 212400,
          changeAmount: 0,
          paymentMethod: 'tunai',
          debtSettlementDetail: Value(detail),
          createdAt: Value(DateTime(2026, 9, 7, 7, 0)),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i3',
        transactionId: txId,
        productId: 'P3',
        productUnitId: 'U3',
        qty: 1,
        priceAtSale: 212400,
        originalPrice: 212400,
        subtotal: 212400));
    // Momen checkout: bayar 100.000 dulu (paling awal).
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay4',
            transactionId: txId,
            amount: 100000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 9, 7, 8, 0))));
    // Cicilan berikutnya (BUKAN momen checkout, harus TETAP nominal asli).
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay5',
            transactionId: txId,
            amount: 112400,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 9, 8, 8, 0))));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));
    await tester.pumpAndSettle();

    // Baris PALING AWAL: 100.000 + 690.000 = 790.000.
    expect(find.text(formatRupiah(790000)), findsOneWidget,
        reason: 'baris pembayaran PALING AWAL harus digabung dgn nota '
            'hutang');
    // Baris KEDUA (cicilan): TETAP 112.400 apa adanya, TIDAK ikut digabung
    // lagi (kalau dobel-hitung, hasilnya jadi 802.400 -- salah).
    expect(find.text(formatRupiah(112400)), findsOneWidget,
        reason: 'baris cicilan kedua TIDAK boleh ikut digabung dgn nota '
            'hutang -- itu momen TERPISAH dari checkout');
    expect(find.text(formatRupiah(802400)), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

/// Pasangan `_ReceiptPaper._fmtNum` (share/gambar) — pemisah ribuan TITIK.
String _fmtNum(int v) {
  final s = v.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Pasangan `PrinterService._fmtNum` (cetak ESC/POS) — pemisah ribuan KOMA.
String _fmtNumComma(int v) {
  final s = v.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
