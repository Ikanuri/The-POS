import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Widget test — checkbox "kembalian sudah diambil" di struk mencegah kasir
/// memberi kembalian dua kali untuk nota yang barangnya diambil belakangan.
Future<void> _insertTx(AppDatabase db,
    {required String id,
    required String localId,
    required int total,
    required int paid,
    required int changeAmount}) async {
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id,
        localId: localId,
        status: 'lunas',
        total: total,
        paid: paid,
        changeAmount: changeAmount,
        paymentMethod: 'tunai',
      ));
}

Future<void> _insertItem(AppDatabase db,
    {required String id,
    required String transactionId,
    required int priceAtSale}) async {
  await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: id,
        transactionId: transactionId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: priceAtSale,
        originalPrice: priceAtSale,
        subtotal: priceAtSale,
      ));
}

void main() {
  testWidgets(
      'nota berkembalian menampilkan checkbox "Kembalian" TIDAK tercentang '
      'secara default, dan tap men-toggle + menulis balik ke DB',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertTx(db,
        id: 'tx1',
        localId: 'K1-1',
        total: 10000,
        paid: 15000,
        changeAmount: 5000);
    await _insertItem(db, id: 'ti1', transactionId: 'tx1', priceAtSale: 10000);

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.text('Kembalian'), findsOneWidget);
    final checkboxFinder = find.byType(Checkbox);
    expect(checkboxFinder, findsWidgets);

    Checkbox findChangeCheckbox() {
      final all = tester.widgetList<Checkbox>(checkboxFinder);
      return all.firstWhere((c) => c.value == false);
    }

    expect(findChangeCheckbox().value, isFalse,
        reason: 'default belum dicentang — kembalian belum diambil');

    await tester.tap(find.text('Kembalian'));
    await tester.pumpAndSettle();

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(tx.changeTaken, isTrue,
        reason: 'tap baris Kembalian harus menulis changeTaken=true ke DB');

    await db.close();
  });

  testWidgets(
      'nota TANPA kembalian (changeAmount 0) tidak menampilkan baris '
      'Kembalian sama sekali', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertTx(db,
        id: 'tx1', localId: 'K1-1', total: 10000, paid: 10000, changeAmount: 0);
    await _insertItem(db, id: 'ti1', transactionId: 'tx1', priceAtSale: 10000);

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.text('Kembalian'), findsNothing);

    await db.close();
  });
}
