import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart' show formatRupiah;
import 'package:the_pos/features/kasir/cart_debt_settlement_provider.dart';
import 'package:the_pos/features/kasir/cart_prabayar_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// Audit Pra-Bayar: saat Pra-Bayar menutup SEBAGIAN belanja, kartu Pra-Bayar
/// sudah benar menampilkan "Sisa yang perlu dibayar", tapi tombol Bayar,
/// keypad ("Uang Pas"), nominal QRIS & gerbang Item 65 memakai grand total
/// PENUH — "Uang Pas" mengisi total penuh & struk mencatat kembalian sebesar
/// Pra-Bayar. Kalau pelanggan cuma menyerahkan sisanya (sesuai kartu) dan
/// kasir menuruti struk, laci kurang sebesar Pra-Bayar.
void main() {
  Future<({AppDatabase db, ProviderContainer container})> pumpPayment(
    WidgetTester tester, {
    required int itemPrice,
    required int prabayar,
    int debtAmount = 0,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    if (debtAmount > 0) {
      await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'cust1', name: 'Budi'));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'old1',
            localId: 'old1',
            status: 'tempo',
            total: debtAmount,
            paid: 0,
            changeAmount: 0,
            paymentMethod: 'tunai',
            customerId: const Value('cust1'),
            createdAt: Value(DateTime.now().subtract(const Duration(days: 1))),
          ));
    }
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'Kasir Uji',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(kMainCartId).notifier).addItem(CartItem(
          productId: 'p1',
          productUnitId: 'u1',
          productName: 'Gula Pasir',
          unitName: 'Pcs',
          qty: 1,
          price: itemPrice,
          originalPrice: itemPrice,
          costPrice: 1000,
        ));
    container.read(cartPrabayarProvider(kMainCartId).notifier).add(
        PrabayarEntry(
            id: 'pb1',
            amount: prabayar,
            method: 'tunai',
            lockedAt: DateTime.now()));
    if (debtAmount > 0) {
      container.read(cartDebtSettlementProvider(kMainCartId).notifier).add(
          DebtSettlementEntry(
            id: 'ds1',
            invoiceId: 'old1',
            invoiceLocalId: 'old1',
            invoiceDate: DateTime.now().subtract(const Duration(days: 1)),
            customerId: 'cust1',
            customerName: 'Budi',
            amount: debtAmount,
            createdAt: DateTime.now(),
          ));
    }

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PaymentScreen()),
    ));
    await tester.pumpAndSettle();
    return (db: db, container: container);
  }

  Future<void> drain(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  }

  Future<void> payExactViaKeypad(WidgetTester tester) async {
    await tester.tap(find.textContaining('Bayar Rp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uang Pas'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Pra-Bayar Rp50.000 dari belanja Rp80.000: tombol Bayar menagih SISA '
      'Rp30.000, "Uang Pas" -> lunas TANPA kembalian', (tester) async {
    final r = await pumpPayment(tester, itemPrice: 80000, prabayar: 50000);

    expect(find.textContaining('Bayar ${formatRupiah(30000)}'), findsOneWidget,
        reason: 'tanpa fix: "Bayar Rp80.000" padahal kartu Pra-Bayar bilang '
            'sisa Rp30.000');

    await payExactViaKeypad(tester);

    final tx = await r.db.select(r.db.transactions).getSingle();
    expect(tx.total, 80000);
    expect(tx.paid, 80000);
    expect(tx.status, 'lunas');
    expect(tx.changeAmount, 0,
        reason: 'tanpa fix: "Uang Pas" mengisi 80.000 -> kembalian 50.000 '
            'dicatat & disuruh diserahkan');
    final pays = await r.db.select(r.db.transactionPayments).get();
    expect(pays.fold<int>(0, (s, p) => s + p.changeGiven), 0);

    await drain(tester, r.db);
  });

  testWidgets(
      'Pra-Bayar sebagian + Lunasi Hutang: gerbang menerima SISA (belanja '
      'setelah Pra-Bayar + hutang), bukan grand total penuh', (tester) async {
    final r = await pumpPayment(tester,
        itemPrice: 100000, prabayar: 40000, debtAmount: 50000);

    // Belanja 100.000 - Pra-Bayar 40.000 + hutang 50.000 = 110.000.
    expect(
        find.textContaining('Bayar ${formatRupiah(110000)}'), findsOneWidget);

    await payExactViaKeypad(tester);

    expect(find.textContaining('belum menutup Total Diterima'), findsNothing,
        reason: 'tanpa fix: gerbang menuntut 150.000 & menolak uang pas');
    final newTx = await (r.db.select(r.db.transactions)
          ..where((t) => t.id.isNotValue('old1')))
        .getSingle();
    expect(newTx.paid, 100000);
    expect(newTx.changeAmount, 0,
        reason: 'tanpa fix: kembalian fiktif sebesar Pra-Bayar (40.000)');
    final old = await (r.db.select(r.db.transactions)
          ..where((t) => t.id.equals('old1')))
        .getSingle();
    expect(old.status, 'lunas');

    await drain(tester, r.db);
  });
}
