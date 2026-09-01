import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Permintaan user: "di print serta share struk, jika ada pre-order dengan
/// jaminan dititip, tulis keterangan titip juga di samping nama item" —
/// struk in-app (in-screen) SUDAH punya penanda "· Titip N" ini
/// (`_preorderDeposit`), tapi struk gambar (share, `_ReceiptPaper`) &
/// print ESC/POS BELUM. Test ini cakupan struk gambar (share); ESC/POS
/// dicek di printer_service_test.dart.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedTx() async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Tabung Gas'));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 30000,
          paid: 30000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 2,
          priceAtSale: 15000,
          originalPrice: 15000,
          subtotal: 30000,
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: 'tx1', amount: 30000, method: 'tunai'));
  }

  testWidgets(
      'pre-order dgn jaminan dititip -> "· Titip N" tampil di samping nama '
      'item pada struk GAMBAR (share)', (tester) async {
    await seedTx();
    await db.addPreorderEntry(
        id: 'po1',
        productId: 'P1',
        productUnitId: 'U1',
        customerName: 'Umum',
        qtyOrdered: 2,
        depositQty: 2,
        transactionId: 'tx1');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));
    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    final nameText = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((t) => (t.data ?? '').contains('· Titip 2'));
    expect(nameText.data, contains('Tabung Gas'),
        reason: 'penanda titip harus nempel di baris nama item yang sama');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'item TANPA jaminan dititip -> tidak ada penanda "Titip" sama sekali',
      (tester) async {
    await seedTx();

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));
    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .where((t) => (t.data ?? '').contains('Titip'))
            .isEmpty,
        isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'jaminan qty BULAT tampil tanpa desimal (mis. "Titip 2", bukan '
      '"Titip 2.0")', (tester) async {
    await seedTx();
    await db.addPreorderEntry(
        id: 'po1',
        productId: 'P1',
        productUnitId: 'U1',
        customerName: 'Umum',
        qtyOrdered: 2,
        depositQty: 2,
        transactionId: 'tx1');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));
    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .where((t) => (t.data ?? '').contains('Titip 2.0'))
            .isEmpty,
        isTrue,
        reason: 'qty jaminan bulat tidak boleh tampil dgn desimal ".0"');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
