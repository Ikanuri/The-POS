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

/// Bug dilaporkan user (screenshot): baris "Lunasi Nota #X" sudah menyatu ke
/// list item struk (redesain ketiga), TAPI baris "Total"/"Total akhir" &
/// "Dibayar" di ringkasan bawah TIDAK ikut menjumlahkan nominal nota hutang
/// yang dilunasi — cuma tampilkan `tx.total`/`tx.paid` MENTAH (item saja).
/// Fix: ketiga jenis struk (in-app, share/gambar, cetak ESC/POS) sekarang
/// menampilkan "Total"/"Dibayar" = item + hutang digabung — MURNI perubahan
/// TAMPILAN, kolom DB `tx.total`/`tx.paid` TIDAK disentuh sama sekali
/// (Laporan/kalkulasi lain yang pakai kolom itu tidak terpengaruh).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  TestWidgetsFlutterBinding.ensureInitialized();

  /// Nota lunas dgn item Rp 212.400 + Lunasi Nota #16 Rp 690.000 (persis
  /// kasus di screenshot user) — Total/Dibayar HARUS tampil Rp 902.400.
  Future<void> seedLunasWithDebtSettlement({int pointsEarned = 0}) async {
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
          pointsEarned: Value(pointsEarned),
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
      'in-app: "Total" & "Dibayar" gabung item + nota hutang (Rp 212.400 + '
      'Rp 690.000 = Rp 902.400)', (tester) async {
    await seedLunasWithDebtSettlement();
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));
    await tester.pumpAndSettle();

    // Baris "Total" adalah Text tunggal berisi persis nominal gabungan.
    // Item 67: baris Riwayat Pembayaran paling awal SEKARANG juga
    // menampilkan Text persis sama ("Rp 902.400") — jadi 2 match, bukan 1.
    expect(find.text(formatRupiah(902400)), findsNWidgets(2),
        reason: '"Total" DAN baris Riwayat Pembayaran paling awal harus '
            'menampilkan gabungan item + nota hutang, bukan cuma tx.total '
            'mentah (Rp 212.400)');
    // Baris "Dibayar" formatnya '<metode> · <nominal>' dalam SATU Text
    // (bukan Text terpisah) — cek via textContaining.
    // Item 67: baris Riwayat Pembayaran paling awal sekarang JUGA ikut
    // digabung (lihat receipt_payment_timeline_settlement_test.dart) —
    // jadi ada 3 match, bukan 2.
    expect(find.textContaining(formatRupiah(902400)), findsNWidgets(3),
        reason: '"Total", "Dibayar" (format "Tunai · Rp ..."), DAN baris '
            'Riwayat Pembayaran paling awal harus sama-sama mengandung '
            'nominal gabungan Rp 902.400');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'share/gambar (_ReceiptPaper): "Total"/"Bayar.." gabung item + nota '
      'hutang', (tester) async {
    await seedLunasWithDebtSettlement();
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    // Item 67: baris timeline "Pembayaran:" paling awal sekarang JUGA ikut
    // digabung — jadi ada 3 match ("Total", "Bayar..", DAN baris timeline).
    expect(find.text('Rp ${_fmtNum(902400)}'), findsNWidgets(3),
        reason: 'struk share/gambar juga harus menggabung item + hutang '
            'di baris Total/Bayar/timeline (3 baris)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  test('cetak ESC/POS: baris "Total"/"Bayar" gabung item + nota hutang',
      () async {
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

    expect(text.contains('Rp ${_fmtNumComma(902400)}'), isTrue,
        reason: 'Total & Bayar tercetak harus gabungan item + hutang '
            '(Rp 902.400), bukan cuma Rp 212.400 (item mentah)');
    // Nominal MENTAH item saja tidak boleh muncul sbg baris Total (baris
    // item produk & "Lunasi Nota" boleh tercetak beda nominal, jadi kita
    // cek langsung window di sekitar "Total", bukan larangan substring
    // global).
    final totalLineStart = text.indexOf('Total');
    final totalSection = text.substring(totalLineStart, totalLineStart + 60);
    expect(totalSection.contains('Rp ${_fmtNumComma(212400)}'), isFalse,
        reason: 'baris Total tidak boleh lagi tampil nominal item mentah');
  });

  testWidgets(
      'regresi: nota TANPA nota hutang — Total/Dibayar TIDAK berubah '
      '(tetap tx.total/tx.paid mentah)', (tester) async {
    const txId = 'tx2';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-3',
          status: 'lunas',
          total: 50000,
          paid: 50000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 50000,
        originalPrice: 50000,
        subtotal: 50000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay2',
            transactionId: txId,
            amount: 50000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 9, 7, 8, 0))));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));
    await tester.pumpAndSettle();

    expect(find.text(formatRupiah(50000)), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'Poin Didapat TIDAK ikut naik krn nota hutang — tetap basis lama '
      '(tx.pointsEarned mentah, bukan +debt)', (tester) async {
    await seedLunasWithDebtSettlement(pointsEarned: 21);
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));
    await tester.pumpAndSettle();

    // 21 poin ini murni dari basis lama (mis. dihitung dari belanja
    // barang Rp 212.400 saja) — HARUS tampil apa adanya, TIDAK ikut naik
    // krn nota hutang Rp 690.000 turut dilunasi di nota ini.
    expect(find.text('+21 poin'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'kombinasi kurang_bayar + nota hutang: "Sisa Tagihan" TIDAK ikut '
      'ditambah nota hutang (murni sisa item nota ini sendiri)',
      (tester) async {
    const txId = 'tx3';
    final detail = jsonEncode([
      {
        'invoiceId': 'old20',
        'invoiceLocalId': 'K1-20260901-0020',
        'invoiceDate': DateTime(2026, 9, 1).millisecondsSinceEpoch,
        'amount': 690000,
        'customerName': 'Budi',
      },
    ]);
    // Item Rp 212.400, baru dibayar Rp 100.000 (sisa item sendiri
    // seharusnya Rp 112.400) + nota hutang lama Rp 690.000 turut dilunasi
    // (uang yg SUDAH diterima, bukan bagian yg belum dibayar).
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-4',
          status: 'kurang_bayar',
          total: 212400,
          paid: 100000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          debtSettlementDetail: Value(detail),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i2',
        transactionId: txId,
        productId: 'P2',
        productUnitId: 'U2',
        qty: 1,
        priceAtSale: 212400,
        originalPrice: 212400,
        subtotal: 212400));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay3',
            transactionId: txId,
            amount: 100000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 9, 7, 8, 0))));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));
    await tester.pumpAndSettle();

    // Total gabungan tampil (item + hutang): 212400 + 690000 = 902400.
    expect(find.text(formatRupiah(902400)), findsWidgets);
    // Sisa Tagihan HARUS murni 212400 - 100000 = 112400, TIDAK ikut
    // ditambah 690000 (yg BUKAN 802400).
    expect(find.text(formatRupiah(112400)), findsOneWidget,
        reason: '"Sisa Tagihan" harus murni sisa item nota ini sendiri, '
            'TIDAK ikut ditambah nominal nota hutang yg sudah dilunasi');
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

/// Pasangan `PrinterService._fmtNum` (cetak ESC/POS) — pemisah ribuan KOMA
/// (beda dari share/gambar & in-app yang pakai `formatRupiah`/titik).
String _fmtNumComma(int v) {
  final s = v.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
