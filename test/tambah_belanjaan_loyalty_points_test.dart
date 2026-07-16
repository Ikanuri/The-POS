import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

import 'helpers/pump_app.dart';

/// Bug dilaporkan user: poin loyalitas tidak ikut bertambah (secara
/// kumulatif, sesuai nominal) saat "Tambah Belanjaan" menaikkan total nota
/// yang sudah pernah dapat poin sebelumnya. Test end-to-end lewat
/// `PaymentScreen(addToTxId:)` sungguhan (bukan cuma DB tier) — membuktikan
/// wiring `_confirmAddItems` benar2 memanggil ulang perhitungan poin.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'Tambah Belanjaan pada nota yg sudah pernah dapat poin → poin '
      'bertambah sesuai kenaikan total (kumulatif)', (tester) async {
    await db.setSetting('loyalty_point_threshold', '10000');
    await db.setSetting('loyalty_points_per', '1');
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'c1',
          name: 'Bu Siti',
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 50000,
          paid: 50000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: const Value('c1'),
          pointsEarned: const Value(5), // 50.000/10.000 = 5, sudah diberikan
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 50000,
          originalPrice: 50000,
          subtotal: 50000,
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: 'tx1', amount: 50000, method: 'tunai'));
    await (db.update(db.customers)..where((t) => t.id.equals('c1')))
        .write(const CustomersCompanion(loyaltyPoints: Value(5)));

    final prefs = {
      'cart_v1_tx1': jsonEncode([
        const CartItem(
          productId: 'P2',
          productUnitId: 'U2',
          productName: 'Barang Tambahan',
          unitName: 'pcs',
          qty: 1,
          price: 70000,
          originalPrice: 70000,
          costPrice: 40000,
        ).toJson(),
      ]),
    };

    await pumpWithFakeApp(tester,
        db: db,
        initialPrefs: prefs,
        child: const PaymentScreen(addToTxId: 'tx1'));

    await tester.tap(find.text('Bayar ${formatRupiah(70000)}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uang Pas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bayar'));
    await tester.pumpAndSettle();

    final tx =
        await (db.select(db.transactions)..where((t) => t.id.equals('tx1')))
            .getSingle();
    expect(tx.total, 120000);
    expect(tx.pointsEarned, 12,
        reason: '120.000 / 10.000 = 12 kelipatan (naik dari 5)');

    final cust =
        await (db.select(db.customers)..where((t) => t.id.equals('c1')))
            .getSingle();
    expect(cust.loyaltyPoints, 12,
        reason: 'bertambah 7 (selisih), bukan tetap 5 atau dobel jadi 17');
  });
}
