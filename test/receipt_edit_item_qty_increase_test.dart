import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Permintaan user: qty produk yang SAMA boleh dinaikkan (bukan cuma
/// dikurangi) di modal edit item struk, KHUSUS nota yang paid==0 (belum ada
/// uang berpindah sama sekali) — beda dari nota yang sudah ada pembayaran
/// (paid>0), yang tetap cuma bisa dikurangi (risiko rekonsiliasi pembayaran).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedTx({required int paid}) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'kurang_bayar',
          total: 20000,
          paid: paid,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 2,
          priceAtSale: 10000,
          originalPrice: 10000,
          subtotal: 20000,
        ));
    if (paid > 0) {
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay1',
              transactionId: 'tx1',
              amount: paid,
              method: 'tunai'));
    }
  }

  testWidgets(
      'nota paid==0: tombol "+" di modal edit item TETAP aktif walau qty '
      'sudah sama dengan qty asli', (tester) async {
    await seedTx(paid: 0);
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    await tester.tap(find.text('P1').first);
    await tester.pumpAndSettle();

    final plusButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add_circle_outline));
    expect(plusButton.onPressed, isNotNull,
        reason: 'paid==0 — boleh naikkan qty melebihi qty asli');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'nota paid>0: tombol "+" di modal edit item NONAKTIF begitu qty '
      'sudah sama dengan qty asli', (tester) async {
    await seedTx(paid: 20000);
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    await tester.tap(find.text('P1').first);
    await tester.pumpAndSettle();

    final plusButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add_circle_outline));
    expect(plusButton.onPressed, isNull,
        reason: 'paid>0 — tidak boleh naikkan qty melebihi qty asli');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
