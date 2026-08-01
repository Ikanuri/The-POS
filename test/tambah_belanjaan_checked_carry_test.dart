import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): "state di centang di cartbar ketika tambah
/// barang (setelah nota lunas/tempo) tidak terikut ke struk in app".
///
/// Checkout nota BARU (`_confirmPayment`) memang sudah lama meneruskan status
/// centang keranjang ke `transactions.checkedItemIds`, tapi jalur "Tambah
/// Belanjaan" (`_confirmAddItems`) sama sekali tidak — barang yang sudah
/// dicentang kasir di cart bar muncul TANPA centang di struk in-app.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedPaidTx({String? checkedItemIds}) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 50000,
          paid: 50000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          checkedItemIds: Value(checkedItemIds),
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
  }

  Map<String, Object> cartPrefs({required bool checked}) => {
        'cart_v1_tx1': jsonEncode([
          CartItem(
            productId: 'P2',
            productUnitId: 'U2',
            productName: 'Barang Tambahan',
            unitName: 'pcs',
            qty: 1,
            price: 70000,
            originalPrice: 70000,
            costPrice: 40000,
            checked: checked,
          ).toJson(),
        ]),
      };

  Future<Set<String>> checkedIdsOf(String txId) async {
    final tx = await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
        .getSingle();
    if (tx.checkedItemIds == null || tx.checkedItemIds!.isEmpty) return {};
    return (jsonDecode(tx.checkedItemIds!) as List).cast<String>().toSet();
  }

  Future<void> payAddItems(WidgetTester tester) async {
    await tester.tap(find.text('Bayar ${formatRupiah(70000)}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uang Pas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bayar'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Tambah Belanjaan: item yang DICENTANG di keranjang ikut tercentang di '
      'struk (masuk transactions.checkedItemIds)', (tester) async {
    await seedPaidTx();
    await pumpWithFakeApp(tester,
        db: db,
        initialPrefs: cartPrefs(checked: true),
        child: const PaymentScreen(addToTxId: 'tx1'));
    await payAddItems(tester);

    final added = await (db.select(db.transactionItems)
          ..where((t) => t.productId.equals('P2')))
        .getSingle();
    expect(await checkedIdsOf('tx1'), contains(added.id),
        reason: 'status centang keranjang harus ikut ke struk in-app');
  });

  testWidgets(
      'centang nota LAMA tidak hilang saat ada tambahan belanjaan (digabung, '
      'bukan ditimpa)', (tester) async {
    await seedPaidTx(checkedItemIds: jsonEncode(['ti1']));
    await pumpWithFakeApp(tester,
        db: db,
        initialPrefs: cartPrefs(checked: true),
        child: const PaymentScreen(addToTxId: 'tx1'));
    await payAddItems(tester);

    final ids = await checkedIdsOf('tx1');
    expect(ids, contains('ti1'),
        reason: 'barang lama yang sudah dicentang di struk tidak boleh hilang');
    expect(ids, hasLength(2), reason: 'barang lama + barang tambahan');
  });

  testWidgets('item yang TIDAK dicentang tetap tidak tercentang di struk',
      (tester) async {
    await seedPaidTx();
    await pumpWithFakeApp(tester,
        db: db,
        initialPrefs: cartPrefs(checked: false),
        child: const PaymentScreen(addToTxId: 'tx1'));
    await payAddItems(tester);

    expect(await checkedIdsOf('tx1'), isEmpty);
  });
}
