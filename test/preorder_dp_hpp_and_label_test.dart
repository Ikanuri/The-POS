import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Pembukuan pre-order DP-0: HPP baris yang DP-nya belum dibayar DITUNDA
/// (laba tanggal nota tidak sempat negatif — pendapatan & HPP baris itu
/// masuk bersamaan begitu DP dibayar). + keterangan "Pembayaran pre-order
/// [produk]" di Riwayat Pembayaran.
void main() {
  late AppDatabase db;
  final d0 = DateTime(2026, 9, 18, 7, 25);
  final from = DateTime(2026, 9, 18);
  final to = DateTime(2026, 9, 18, 23, 59, 59);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P1', name: 'Gula'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P2', name: 'LPG'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U2', productId: 'P2', isBaseUnit: const Value(true)));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx1',
        localId: 'K1-1',
        status: 'lunas',
        total: 10000,
        paid: 10000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt: Value(d0)));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000,
        costAtSale: const Value(8000)));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i2',
        transactionId: 'tx1',
        productId: 'P2',
        productUnitId: 'U2',
        qty: 2,
        priceAtSale: 0,
        originalPrice: 18000,
        subtotal: 0,
        costAtSale: const Value(15000)));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay0',
            transactionId: 'tx1',
            amount: 10000,
            method: 'tunai',
            paidAt: Value(d0)));
    await db.addPreorderEntry(
        id: 'e1',
        productId: 'P2',
        productUnitId: 'U2',
        customerName: 'A',
        qtyOrdered: 2,
        transactionId: 'tx1',
        transactionItemId: 'i2');
    await db.backfillMissingSummaries();
  });
  tearDown(() async => db.close());

  Future<int> summaryHpp() async =>
      (await db.getDailySummaries(from, to)).single.hpp;

  test('DP belum dibayar: HPP baris pre-order TIDAK dihitung di mana pun',
      () async {
    expect((await db.getReportTotals(from, to)).cogs, 8000,
        reason: 'tanpa fix: 38.000 -> laba kotor 18 Sep NEGATIF');
    expect(await summaryHpp(), 8000);
    final top = await db.getTopProductsByRevenue(from, to);
    expect(top.firstWhere((s) => s.productId == 'P2').cogs, 0);
    final stat = await db.getProductStatsSummary('P2', from, to);
    expect(stat.cogs, 0);
  });

  test('DP dibayar: HPP ikut masuk SEKETIKA (ringkasan harian langsung benar)',
      () async {
    await db.collectPreorderDeposit(
        preorderEntryId: 'e1', amount: 36000, method: 'tunai', kasirId: 'K1');
    expect((await db.getReportTotals(from, to)).cogs, 38000);
    final s = (await db.getDailySummaries(from, to)).single;
    expect(s.hpp, 38000,
        reason: 'tanpa rebuild di collectPreorderDeposit: cache baru benar '
            'setelah Laporan dibuka');
    expect(s.omzet, 46000);
  });

  test('Batalkan Pembayaran DP: HPP ditunda lagi', () async {
    await db.collectPreorderDeposit(
        preorderEntryId: 'e1', amount: 36000, method: 'tunai', kasirId: 'K1');
    final dp = (await db.getPaymentsForTx('tx1'))
        .firstWhere((p) => p.note == AppDatabase.preorderDepositNote);
    await db.voidPayment(dp.id);
    expect(await summaryHpp(), 8000);
    expect((await db.getReportTotals(from, to)).cogs, 8000);
  });

  test('pre-order DIBATALKAN & DP tak pernah dibayar: HPP tetap tidak dihitung',
      () async {
    await db.cancelPreorderEntry('e1');
    expect((await db.getReportTotals(from, to)).cogs, 8000);
  });

  test('pre-order yang DP-nya sudah lunas sejak checkout: HPP dihitung',
      () async {
    await (db.update(db.preorderEntries)..where((t) => t.id.equals('e1')))
        .write(const PreorderEntriesCompanion(paid: Value(true)));
    expect((await db.getReportTotals(from, to)).cogs, 38000);
  });

  test(
      'perbaikan satu kali jalan: ringkasan harian LAMA (HPP masih memuat '
      'pre-order belum dibayar) dibetulkan; idempotent', () async {
    // Simulasikan cache dari build sebelum fix: omzet benar, HPP 38.000.
    await (db.update(db.dailySummaries)
          ..where((t) => t.date.equals('2026-09-18')))
        .write(const DailySummariesCompanion(hpp: Value(38000)));
    expect(await summaryHpp(), 38000, reason: 'prakondisi: cache basi');

    expect(await db.repairDeferredPreorderHppSummaries(), 1);
    expect(await summaryHpp(), 8000);
    expect(await db.repairDeferredPreorderHppSummaries(), 0,
        reason: 'idempotent — tidak ada lagi yang perlu dibangun ulang');
  });

  testWidgets(
      'Riwayat Pembayaran: baris DP berketerangan "Pembayaran pre-order LPG"',
      (tester) async {
    await db.collectPreorderDeposit(
        preorderEntryId: 'e1', amount: 36000, method: 'tunai', kasirId: 'K1');
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));
    final label = find.byKey(const ValueKey('preorder-payment-label'));
    expect(label, findsOneWidget,
        reason: 'hanya baris DP yang berketerangan, bukan pembayaran awal');
    expect(tester.widget<Text>(label).data, 'Pembayaran pre-order LPG');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
