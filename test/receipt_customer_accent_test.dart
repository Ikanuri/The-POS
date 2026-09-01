import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Susulan permintaan user: teks nama pelanggan (bukan cuma ikonnya) di
/// header struk in-app juga harus ikut aksen terracotta kalau pelanggannya
/// TERDAFTAR (`Transactions.customerId` terisi) — nama ad-hoc (cuma diketik
/// di nota, tanpa record `Customers`) tetap warna netral biasa.
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  Future<void> seedTx({String? customerId, String? customerName}) async {
    db = AppDatabase(NativeDatabase.memory());
    if (customerId != null) {
      await db.into(db.customers).insert(
          CustomersCompanion.insert(id: customerId, name: customerName!));
    }
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: Value(customerId),
          customerName: Value(customerId == null ? customerName : null),
        ));
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P1', name: 'Barang'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000));
  }

  tearDown(() async => db.close());

  testWidgets(
      'pelanggan TERDAFTAR -> nama di header nota ikut warna aksen terracotta',
      (tester) async {
    await seedTx(customerId: 'C1', customerName: 'Bu Ani Terdaftar');
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    final text = tester.widget<Text>(find.text('Bu Ani Terdaftar'));
    expect(text.style?.color, AppTheme.accent);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('nama AD-HOC -> TIDAK ikut aksen terracotta', (tester) async {
    await seedTx(customerName: 'Orang Lewat');
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    final text = tester.widget<Text>(find.text('Orang Lewat'));
    expect(text.style?.color, isNot(AppTheme.accent));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
