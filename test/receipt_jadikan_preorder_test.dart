import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Fitur baru (permintaan user): kasir kadang lupa input pre-order saat
/// checkout (mis. LPG lupa dicek stok, nota keburu lunas/tempo). TAP baris
/// item di struk in-app (bukan long-press — itu tetap "Edit Catatan") membuka
/// sheet "Edit Barang" yang sudah ada, dengan tombol baru "Jadikan Pre-order"
/// di dalamnya — mencatat `PreorderEntries` baru bertaut ke nota INI, TANPA
/// mengubah nota itu sendiri (total/paid/item tetap apa adanya).
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  Future<void> seedTx(String status,
      {int total = 50000,
      int paid = 50000,
      bool requiresDeposit = false}) async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: status,
          total: total,
          paid: paid,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P1', name: 'LPG 3kg'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1',
          productId: 'P1',
          isBaseUnit: const Value(true),
          requiresDeposit: Value(requiresDeposit),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: 5,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 50000));
    if (paid > 0) {
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay1', transactionId: txId, amount: paid, method: 'tunai'));
    }
  }

  tearDown(() async => db.close());

  testWidgets(
      'nota LUNAS: tap item -> sheet edit barang -> "Jadikan Pre-order" -> '
      'konfirmasi -> PreorderEntries baru bertaut ke nota ini, kartu '
      'Pre-order muncul', (tester) async {
    await seedTx('lunas');
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.text('LPG 3kg'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jadikan Pre-order'));
    await tester.pumpAndSettle();

    // Dialog qty default = qty penuh baris (5).
    expect(find.text('Maks 5'), findsOneWidget);
    await tester.tap(find.text('Jadikan Pre-order').last);
    await tester.pumpAndSettle();

    final rows = await db.select(db.preorderEntries).get();
    expect(rows, hasLength(1));
    expect(rows.single.transactionId, txId);
    expect(rows.single.qtyOrdered, 5);
    expect(rows.single.paid, isTrue,
        reason: 'uang sudah tercatat lunas via nota ini sendiri');

    // Nota itu sendiri TIDAK berubah sama sekali.
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    expect(tx.total, 50000);
    expect(tx.paid, 50000);
    expect(tx.status, 'lunas');

    // Kartu "Pre-order" otomatis muncul (query by transactionId).
    expect(find.text('Pre-order'), findsOneWidget);
    expect(find.textContaining('belum dipenuhi'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'nota TEMPO: tap item -> sheet edit barang tetap punya tombol '
      '"Jadikan Pre-order"', (tester) async {
    await seedTx('tempo', total: 50000, paid: 0);
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.text('LPG 3kg'));
    await tester.pumpAndSettle();

    expect(find.text('Jadikan Pre-order'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'sisa qty baris SUDAH habis dijadikan pre-order -> tombol tidak '
      'muncul lagi (cegah dobel-tandai)', (tester) async {
    await seedTx('lunas');
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
          id: 'po1',
          productId: 'P1',
          productUnitId: 'U1',
          transactionId: const Value(txId),
          customerName: 'Umum',
          qtyOrdered: 5,
        ));
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.text('LPG 3kg'));
    await tester.pumpAndSettle();

    expect(find.text('Jadikan Pre-order'), findsNothing,
        reason: 'seluruh qty baris (5) sudah dijadikan pre-order sebelumnya');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'produk dgn toggle jaminan (requiresDeposit) -> dialog Jadikan '
      'Pre-order punya field "Jumlah jaminan dititip", default = qty, '
      'tersimpan ke depositQty', (tester) async {
    await seedTx('lunas', requiresDeposit: true);
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.text('LPG 3kg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jadikan Pre-order'));
    await tester.pumpAndSettle();

    expect(find.text('Jumlah jaminan dititip'), findsOneWidget);
    // Default deposit qty = qty pesanan penuh (5).
    final depositField = tester.widget<TextField>(find
        .byWidgetPredicate((w) => w is TextField && w.controller?.text == '5')
        .last);
    expect(depositField.controller!.text, '5');

    await tester.tap(find.text('Jadikan Pre-order').last);
    await tester.pumpAndSettle();

    final rows = await db.select(db.preorderEntries).get();
    expect(rows.single.depositQty, 5);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'produk TANPA toggle jaminan -> dialog Jadikan Pre-order TIDAK '
      'punya field "Jumlah jaminan dititip"', (tester) async {
    await seedTx('lunas', requiresDeposit: false);
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.text('LPG 3kg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jadikan Pre-order'));
    await tester.pumpAndSettle();

    expect(find.text('Jumlah jaminan dititip'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
