import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_preorder_settlement_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Fitur "Pelunasi Pre-order" DI KERANJANG — arsitektur & test SAMA PERSIS
/// `cart_sheet_debt_settlement_test.dart` (baca dok di sana dulu), cuma
/// sumber datanya pre-order (DP/jaminan tertunggak), bukan nota tempo/
/// kurang_bayar.
void main() {
  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Gula Pasir',
    unitName: 'Pcs',
    qty: 2,
    price: 15000,
    originalPrice: 15000,
    costPrice: 10000,
  );

  Future<
      ({
        AppDatabase db,
        ProviderContainer container,
      })> pumpCartSheetOpen(
    WidgetTester tester, {
    required String deviceRole,
    bool terimaPembayaran = false,
    String cartId = kMainCartId,
    String? customerId,
    String? customerName,
    Future<void> Function(AppDatabase db)? seed,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('terima_pembayaran')))
        .write(KasirPermissionsCompanion(isEnabled: Value(terimaPembayaran)));
    // WAJIB seed SEBELUM sheet dibuka & provider pertama kali di-watch —
    // `cartCustomerPreorderDepositProvider` (FutureProvider.autoDispose)
    // TIDAK auto-refetch begitu saja saat DB berubah belakangan (beda dari
    // StreamProvider), jadi data harus sudah ada di DB SAAT provider
    // pertama kali dibaca.
    if (seed != null) await seed(db);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'HP Kasir',
          deviceCode: 'K2',
          deviceRole: deviceRole,
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(cartId).notifier).addItem(item);
    if (customerId != null || customerName != null) {
      container
          .read(cartMetaProvider(cartId).notifier)
          .setCustomer(customerId, customerName);
    }

    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => CartSheet(cartId: cartId),
                ),
                child: const Text('buka keranjang'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka keranjang'));
    await tester.pumpAndSettle();
    return (db: db, container: container);
  }

  Future<void> seedCustomer(AppDatabase db,
      {required String customerId, required String customerName}) async {
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: customerId, name: customerName));
  }

  /// Seed pre-order SUMBER: satu produk, satu baris nota pre-order dikunci
  /// Rp 0 (`priceAtSale: 0`), tertaut `PreorderEntries.paid = false` — pola
  /// sama persis `preorder_deposit_payment_test.dart`.
  Future<void> seedPreorder(
    AppDatabase db, {
    required String customerId,
    required String preorderEntryId,
    required String txId,
    required String txLocalId,
    required String productName,
    int originalPrice = 15000,
    double qty = 1,
    DateTime? createdAt,
  }) async {
    final productId = '${preorderEntryId}_prod';
    final unitId = '${preorderEntryId}_unit';
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: productId, name: productName));
    await db.into(db.productUnits).insert(
        ProductUnitsCompanion.insert(id: unitId, productId: productId));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: txLocalId,
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: Value(customerId),
          createdAt:
              Value(createdAt ?? DateTime.now().subtract(const Duration(days: 3))),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: '${preorderEntryId}_ti',
          transactionId: txId,
          productId: productId,
          productUnitId: unitId,
          qty: qty,
          priceAtSale: 0,
          originalPrice: originalPrice,
          subtotal: 0,
        ));
    await db.addPreorderEntry(
        id: preorderEntryId,
        productId: productId,
        productUnitId: unitId,
        customerName: 'x',
        customerId: customerId,
        qtyOrdered: qty,
        transactionId: txId,
        transactionItemId: '${preorderEntryId}_ti');
  }

  final chipFinder = find.textContaining('DP Pre-order');

  testWidgets('pelanggan TANPA DP pre-order tertunggak -> chip TIDAK muncul',
      (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'owner',
        terimaPembayaran: true,
        customerId: 'c1',
        customerName: 'Sari');
    addTearDown(() async => r.db.close());
    expect(chipFinder, findsNothing);
  });

  testWidgets(
      'pegawai TANPA izin terima_pembayaran -> chip TIDAK muncul walau '
      'pelanggan terikat punya DP pre-order tertunggak', (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir',
        terimaPembayaran: false,
        customerId: 'c1',
        customerName: 'Sari',
        seed: (db) async {
          await seedCustomer(db, customerId: 'c1', customerName: 'Sari');
          await seedPreorder(db,
              customerId: 'c1',
              preorderEntryId: 'po1',
              txId: 'tx1',
              txLocalId: 'A1-0007',
              productName: 'Galon Aqua');
        });
    addTearDown(() async => r.db.close());
    expect(chipFinder, findsNothing);
  });

  testWidgets(
      'tap chip -> sheet pilih pre-order, centang -> Terapkan -> entri '
      'masuk keranjang, Total naik', (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'owner',
        terimaPembayaran: true,
        customerId: 'c1',
        customerName: 'Sari',
        seed: (db) async {
          await seedCustomer(db, customerId: 'c1', customerName: 'Sari');
          await seedPreorder(db,
              customerId: 'c1',
              preorderEntryId: 'po1',
              txId: 'tx1',
              txLocalId: 'A1-0007',
              productName: 'Galon Aqua',
              originalPrice: 20000,
              createdAt: DateTime(2026, 1, 1));
        });
    addTearDown(() async => r.db.close());

    expect(chipFinder, findsOneWidget);
    expect(
        r.container.read(cartPreorderSettlementProvider(kMainCartId)),
        isEmpty);

    await tester.tap(chipFinder);
    await tester.pumpAndSettle();

    expect(find.text('Pilih Pre-order untuk Dilunasi'), findsOneWidget);
    expect(find.text('Galon Aqua'), findsOneWidget);

    await tester.tap(find.text('Centang Semua'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    final entries =
        r.container.read(cartPreorderSettlementProvider(kMainCartId));
    expect(entries, hasLength(1));
    expect(entries.single.preorderEntryId, 'po1');
    expect(entries.single.amount, 20000);
    expect(entries.single.productName, 'Galon Aqua');

    // Baris entri muncul di daftar keranjang (bukan produk, tapi menyatu di
    // list yang sama).
    expect(find.text('Galon Aqua'), findsOneWidget);

    // Total naik = belanja (2 x 15000 = 30000) + DP 20000 = 50000.
    expect(find.text(formatRupiah(50000)), findsOneWidget);
  });

  testWidgets('tap baris entri di keranjang -> entri dihapus, Total turun',
      (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'owner',
        terimaPembayaran: true,
        customerId: 'c1',
        customerName: 'Sari',
        seed: (db) async {
          await seedCustomer(db, customerId: 'c1', customerName: 'Sari');
          await seedPreorder(db,
              customerId: 'c1',
              preorderEntryId: 'po1',
              txId: 'tx1',
              txLocalId: 'A1-0007',
              productName: 'Galon Aqua',
              originalPrice: 20000,
              createdAt: DateTime(2026, 1, 1));
        });
    addTearDown(() async => r.db.close());

    await tester.tap(chipFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Centang Semua'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    expect(
        r.container.read(cartPreorderSettlementProvider(kMainCartId)),
        hasLength(1));
    // Total = 30000 (belanja) + 20000 (DP) = 50000.
    expect(find.text(formatRupiah(50000)), findsOneWidget);

    await tester.tap(find.text('Galon Aqua'));
    await tester.pumpAndSettle();

    expect(
        r.container.read(cartPreorderSettlementProvider(kMainCartId)),
        isEmpty);
    expect(find.textContaining('Pelunasi Pre-order'), findsNothing);
  });
}
