import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/printer_service.dart';
import 'package:the_pos/core/theme/app_theme.dart' show formatRupiah;
import 'package:the_pos/core/utils/change_display.dart';
import 'package:the_pos/features/kasir/cart_prabayar_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Item 88 (laporan user + foto struk) — struk "last state": centang
/// "kembalian sudah diambil" TIDAK lagi menghapus baris Kembali di struk
/// cetak/share. Foto dari user: Pra-Bayar Rp253.800 + Rp115.000 utk total
/// Rp366.800 (kembalian Rp2.000). Dicentang -> cetakan menulis "Bayar
/// Rp366.800" tanpa Kembali, padahal riwayat pembayarannya menjumlah
/// Rp368.800 — menyesatkan. Kembalian menumpuk yang belum diambil
/// digabung lewat tombol di struk in-app.
void main() {
  late AppDatabase db;
  const txId = 'tx1';
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> seedTx({required int total, required int paid}) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: total,
          paid: paid,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: total,
        originalPrice: total,
        subtotal: total));
  }

  Future<void> pay(String id, int amount, int hour,
      {int change = 0,
      bool taken = false,
      Value<int?> reused = const Value.absent()}) async {
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: id,
            transactionId: txId,
            amount: amount,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 9, 27, hour)),
            changeGiven: Value(change),
            changeTaken: Value(taken),
            changeReused: reused));
  }

  /// Skenario PERSIS foto user, kembalian 2.000 SUDAH dicentang diambil.
  Future<void> seedPhoto() async {
    await seedTx(total: 366800, paid: 366800);
    await pay('p1', 253800, 9);
    await pay('p2', 115000, 10, change: 2000, taken: true);
  }

  Future<String> printText({int? merged}) async {
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    final bytes = await PrinterService.debugBuildBytes(
      tx: tx,
      items: await (db.select(db.transactionItems)
            ..where((i) => i.transactionId.equals(txId)))
          .get(),
      productNames: const {'P0': 'Produk'},
      unitNames: const {'U0': 'pcs'},
      customer: null,
      storeName: 'Toko',
      storeAddress: '',
      storePhone: '',
      strukNote: null,
      payments: await db.getPaymentsForTx(txId),
      settings: const PrinterSettings(),
      mergedUnclaimedChange: merged,
    );
    return latin1.decode(bytes, allowInvalid: true);
  }

  test(
      'cetak (foto user): kembalian dicentang TETAP tercetak, Bayar = '
      'uang yang benar-benar diterima', () async {
    await seedPhoto();
    final text = await printText();
    expect(text.contains('Kembali'), isTrue,
        reason: 'tanpa fix: centang menghapus baris Kembali dari cetakan');
    expect(text.contains('2,000'), isTrue);
    expect(text.contains('Rp 368,800'), isTrue,
        reason: 'Bayar harus cocok dgn riwayat 253.800 + 115.000');
  });

  testWidgets('share (foto user): kembalian dicentang TETAP tampil',
      (tester) async {
    await seedPhoto();
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));
    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();
    expect(find.text('Kembali'), findsOneWidget);
    expect(find.text('Rp 2.000'), findsWidgets);
    expect(find.text('Rp 368.800'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  group('kembalian cuma SEKALI di ronde lama, tambah barang dibayar pas', () {
    // Laporan user (screenshot): bayar 150.000 utk 143.350 (kembalian
    // 6.650, TIDAK dicentang) -> Tambah Belanjaan 14.000 dibayar pas.
    // Total 157.350; struk harus tetap gross (Bayar 164.000, Kembali 6.650)
    // & TIDAK menawarkan tombol gabung (tidak ada yang menumpuk).
    Future<void> seedOnce(
        {bool taken = false, Value<int?> reused = const Value.absent()}) async {
      await seedTx(total: 157350, paid: 164000);
      await pay('p1', 150000, 8, change: 6650, taken: taken);
      await pay('p2', 14000, 9, reused: reused);
    }

    test('cetak: Kembali 6.650 & Bayar gross 164.000', () async {
      await seedOnce();
      final text = await printText();
      expect(text.contains('Kembali'), isTrue,
          reason: 'tanpa fix: ronde terakhir tanpa kembalian -> struk net');
      expect(text.contains('6,650'), isTrue);
      expect(text.contains('Rp 164,000'), isTrue);
    });

    testWidgets(
        'in-app: Dibayar gross, baris Kembalian ada, TANPA tombol '
        'gabung', (tester) async {
      await seedOnce();
      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: txId));
      expect(find.text('Tunai · ${formatRupiah(164000)}'), findsOneWidget);
      expect(find.text('Kembalian'), findsWidgets);
      expect(find.textContaining('Gabungkan kembalian belum diambil'),
          findsNothing,
          reason: 'kembalian cuma satu, bukan menumpuk');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    test(
        'Item 89: kembalian ronde lama dicentang "diserahkan" -> struk TETAP '
        'gross (centang murni pengingat)', () async {
      await seedOnce(taken: true);
      final text = await printText();
      expect(text.contains('Kembali'), isTrue,
          reason: 'tanpa Item 89: dicentang -> dianggap dipakai -> net');
      expect(text.contains('Rp 164,000'), isTrue);
    });

    test(
        'kembalian ronde lama DIPAKAI (change_reused) -> tidak tampil, '
        'Bayar net', () async {
      await seedOnce(reused: const Value(6650));
      final text = await printText();
      expect(text.contains('Kembali'), isFalse);
      expect(text.contains('Rp 157,350'), isTrue);
    });

    test('data LAMA (change_reused null) + dicentang -> aturan lama: net',
        () async {
      await seedOnce(taken: true, reused: const Value(null));
      final text = await printText();
      expect(text.contains('Kembali'), isFalse);
      expect(text.contains('Rp 157,350'), isTrue);
    });
  });

  group('kembalian menumpuk belum diambil', () {
    Future<void> seedStacked() async {
      await seedTx(total: 100000, paid: 107000);
      await pay('p1', 55000, 9, change: 5000);
      await pay('p2', 52000, 10, change: 2000);
    }

    test(
        'default = ronde terakhir; mode gabungan = jumlah semua belum '
        'diambil', () async {
      await seedStacked();
      final payments = await db.getPaymentsForTx(txId);
      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(txId)))
          .getSingle();
      expect(lastStateChange(tx, payments), 2000);
      expect(unclaimedChangeTotal(payments), 7000);
      expect(hasExtraUnclaimedChange(tx, payments), isTrue);

      final normal = await printText();
      expect(normal.contains('Rp 2,000'), isTrue);
      final merged = await printText(merged: 7000);
      expect(merged.contains('Kembali (gabungan)'), isTrue);
      expect(merged.contains('Rp 7,000'), isTrue);
    });

    testWidgets(
        'tombol gabung muncul, share ikut; hilang setelah semua '
        'dicentang', (tester) async {
      await seedStacked();
      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: txId));

      final button = find.textContaining('Gabungkan kembalian belum diambil');
      expect(button, findsOneWidget);
      expect(find.textContaining(formatRupiah(7000)), findsWidgets);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bagikan Struk'));
      await tester.pumpAndSettle();
      expect(find.text('Kembali (gabungan)'), findsOneWidget);
      expect(find.text('Rp 7.000'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));

      // Kembalian ronde lama dicentang (mis. dari device lain lewat sync)
      // -> tidak ada lagi yang perlu digabung.
      await (db.update(db.transactionPayments)..where((t) => t.id.equals('p1')))
          .write(const TransactionPaymentsCompanion(changeTaken: Value(true)));
      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(txId)))
          .getSingle();
      expect(hasExtraUnclaimedChange(tx, await db.getPaymentsForTx(txId)),
          isFalse);
      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: txId));
      expect(find.textContaining('Gabungkan kembalian belum diambil'),
          findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  test(
      'atribusi potongan Pra-Bayar per ronde: kembalian ronde 1 yang '
      'diambil TIDAK menempel ke entri ronde 2', () {
    final t0 = DateTime(2026, 9, 27, 9);
    final a =
        PrabayarEntry(id: 'a', amount: 300000, method: 'tunai', lockedAt: t0);
    final b = PrabayarEntry(
        id: 'b',
        amount: 115000,
        method: 'tunai',
        lockedAt: t0.add(const Duration(minutes: 20)));
    final cuts = prabayarChangeTakenCuts([a, b], 46200,
        takes: [
          ChangeTakenEntry(
              id: 'c1',
              amount: 46200,
              takenAt: t0.add(const Duration(minutes: 5))),
        ]);
    expect(cuts, {'a': 46200},
        reason: 'tanpa atribusi per ronde potongan jatuh ke entri TERBARU '
            '(b) & terbaca sbg kembalian ronde terakhir di struk');
  });
}
