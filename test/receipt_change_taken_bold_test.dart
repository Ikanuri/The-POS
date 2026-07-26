import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Usulan user: kembalian TERAKHIR di baris Ringkasan struk in-app (bukan
/// baris per-pembayaran di kartu Riwayat Pembayaran) perlu di-bold/highlight
/// — nominal yang harus benar-benar diserahkan sekarang, beda dari histori.
void main() {
  testWidgets(
      'baris "Kembalian" di Ringkasan (pertama) BOLD, baris di Riwayat '
      'Pembayaran (kedua) TETAP normal', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 10000,
          paid: 15000,
          changeAmount: 5000,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'tx1-pay',
            transactionId: 'tx1',
            amount: 15000,
            method: 'tunai',
            changeGiven: const Value(5000)));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'ti1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    final labels = tester.widgetList<Text>(find.text('Kembalian')).toList();
    expect(labels, hasLength(2));

    final ringkasan = tester.widget<Text>(find.text('Kembalian').first);
    final riwayat = tester.widget<Text>(find.text('Kembalian').last);

    expect(ringkasan.style?.fontWeight, FontWeight.w700,
        reason: 'baris Ringkasan (kembalian terakhir) harus di-bold');
    expect(riwayat.style?.fontWeight, isNot(FontWeight.w700),
        reason: 'baris di kartu Riwayat Pembayaran tetap normal, bukan bold');

    await db.close();
  });
}
