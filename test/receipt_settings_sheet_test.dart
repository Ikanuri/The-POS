import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Redesain ikon gear app bar layar Struk — sebelumnya `PopupMenuButton`
/// bawaan Flutter ("terasa template"), diganti bottom sheet custom
/// ("Pengaturan Struk") mengikuti pola sheet lain di app ini (handle bar +
/// Material rounded-top). Isi tetap 1 opsi ("Tampilkan Laba"), perilaku
/// (state `_showProfit`, persist ke `receipt_show_profit`) TIDAK berubah.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> seedTx() async {
    const txId = 'tx1';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 8000,
        subtotal: 10000));
    return txId;
  }

  testWidgets(
      'ikon gear membuka bottom sheet custom "Pengaturan Struk" (bukan '
      'PopupMenuButton) berisi switch "Tampilkan Laba"', (tester) async {
    final txId = await seedTx();
    await pumpWithFakeApp(tester,
        db: db, child: ReceiptScreen(transactionId: txId));

    expect(find.byType(PopupMenuButton<String>), findsNothing,
        reason: 'PopupMenuButton generik sudah harus diganti sheet custom');

    await tester.tap(find.byTooltip('Pengaturan Struk'));
    await tester.pumpAndSettle();

    expect(find.text('Pengaturan Struk'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    final switchTile = tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Tampilkan Laba'));
    expect(switchTile.value, isTrue, reason: 'default _showProfit = true');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'toggle "Tampilkan Laba" di sheet baru berfungsi & persist ke '
      'SharedPreferences (receipt_show_profit)', (tester) async {
    final txId = await seedTx();
    await pumpWithFakeApp(tester,
        db: db, child: ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('Pengaturan Struk'));
    await tester.pumpAndSettle();

    // Matikan "Tampilkan Laba".
    await tester.tap(find.widgetWithText(SwitchListTile, 'Tampilkan Laba'));
    await tester.pumpAndSettle();

    final switchTile = tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Tampilkan Laba'));
    expect(switchTile.value, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('receipt_show_profit'), isFalse);

    // Tutup sheet, buka lagi — state harus bertahan (persisten).
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Pengaturan Struk'));
    await tester.pumpAndSettle();
    final reopened = tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Tampilkan Laba'));
    expect(reopened.value, isFalse,
        reason: 'nilai OFF yg tadi dipilih harus bertahan');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
