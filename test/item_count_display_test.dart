import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

import 'helpers/pump_app.dart';

/// Jumlah item ditampilkan di 2 tempat (usulan user, screenshot struk):
/// - Struk in-app, sebaris dgn "Tandai Semua" (kiri).
/// - Keranjang kasir, di samping kiri nominal Total.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets('struk in-app tampilkan jumlah item top-level di baris '
      'Tandai Semua', (tester) async {
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
          qty: 1,
          priceAtSale: 15000,
          originalPrice: 15000,
          subtotal: 15000,
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti2',
          transactionId: 'tx1',
          productId: 'P2',
          productUnitId: 'U2',
          qty: 1,
          priceAtSale: 15000,
          originalPrice: 15000,
          subtotal: 15000,
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: 'tx1', amount: 30000, method: 'tunai'));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.text('2 item'), findsOneWidget);
    expect(find.text('Tandai Semua'), findsOneWidget);
  });

  testWidgets(
      'keranjang kasir tampilkan jumlah item (non-varian) di samping kiri '
      'nominal Total', (tester) async {
    final prefs = {
      'cart_v1_main': jsonEncode([
        const CartItem(
          productId: 'P1',
          productUnitId: 'U1',
          productName: 'Kopi Sachet',
          unitName: 'Pcs',
          qty: 1,
          price: 15000,
          originalPrice: 15000,
          costPrice: 10000,
        ).toJson(),
        const CartItem(
          productId: 'P2',
          productUnitId: 'U2',
          productName: 'Gula Pasir',
          unitName: 'Kg',
          qty: 2,
          price: 12000,
          originalPrice: 12000,
          costPrice: 9000,
        ).toJson(),
      ]),
    };

    await pumpWithFakeApp(tester,
        db: db, initialPrefs: prefs, child: const CartSheet());

    expect(find.text('2 item'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
  });
}
