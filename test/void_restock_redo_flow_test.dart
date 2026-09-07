import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_prabayar_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

/// "Batalkan & Susun Ulang" (fitur baru, disetujui user) — end-to-end Tier 2
/// (widget) dari layar Struk: tombol Batalkan → dialog dgn opsi tambahan
/// "Batalkan & Susun Ulang" → nota divoid, keranjang KASIR AKTIF terisi
/// ulang, meta menandai `replacesTxId`, & (bila nota sudah ada pembayaran)
/// ditawari bawa sbg Pra-Bayar.
void main() {
  const fakeOwner = DeviceIdentity(
    storeUuid: 'test-store-uuid',
    storeKey: 'test-store-key',
    storeName: 'Toko Uji',
    deviceName: 'Kasir Uji',
    deviceCode: 'K1',
    deviceRole: 'owner',
  );

  Future<ProviderContainer> pumpReceipt(
      WidgetTester tester, AppDatabase db, String txId,
      {DeviceIdentity device = fakeOwner}) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = device),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/kasir/struk/$txId',
      routes: [
        GoRoute(path: '/kasir', builder: (_, __) => const Scaffold()),
        GoRoute(
          path: '/kasir/struk/:txId',
          builder: (_, state) =>
              ReceiptScreen(transactionId: state.pathParameters['txId']!),
        ),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> seedTxWithItem(AppDatabase db, String txId,
      {int paid = 20000,
      String status = 'lunas',
      String? internalNote,
      String? customerId}) async {
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Kopi Sachet'));
    await db.into(db.productUnits).insert(
        ProductUnitsCompanion.insert(id: 'u1', productId: 'p1'));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: txId,
          status: status,
          total: 20000,
          paid: paid,
          changeAmount: 0,
          paymentMethod: 'tunai',
          // Pola nyata `payment_screen.dart`: pelanggan TERDAFTAR ->
          // customerName SENGAJA null (customerId satu-satunya sumber
          // kebenaran) — lihat dok kolom di `transaction_tables.dart`.
          customerId: customerId == null
              ? const Value.absent()
              : Value(customerId),
          internalNote: internalNote == null
              ? const Value.absent()
              : Value(internalNote),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: '$txId-i1',
        transactionId: txId,
        productId: 'p1',
        productUnitId: 'u1',
        qty: 2,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 20000));
  }

  testWidgets(
      'nota LUNAS: tap "Batalkan & Susun Ulang" -> nota void, keranjang '
      'kasir terisi ulang, meta.replacesTxId terisi, ditawari & terima '
      'Pra-Bayar', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await seedTxWithItem(db, 'tx1');

    final container = await pumpReceipt(tester, db, 'tx1');

    await tester.tap(find.text('Batalkan'));
    await tester.pumpAndSettle();
    expect(find.text('Batalkan & Susun Ulang'), findsOneWidget,
        reason: 'nota lunas biasa (bukan retur/void) harus ditawari opsi ini');

    await tester.tap(find.text('Batalkan & Susun Ulang'));
    await tester.pumpAndSettle();

    // Ditawari bawa Pra-Bayar (nota SUDAH lunas, paid=20000 > 0).
    expect(find.text('Bawa Pembayaran Lama?'), findsOneWidget);
    await tester.tap(find.text('Ya, Bawa sbg Pra-Bayar'));
    await tester.pumpAndSettle();

    final txRow = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(txRow.status, 'void', reason: 'nota lama TETAP dibatalkan permanen');

    final cart = container.read(cartProvider(kMainCartId));
    expect(cart, hasLength(1));
    expect(cart.single.productId, 'p1');
    expect(cart.single.qty, 2);

    final meta = container.read(cartMetaProvider(kMainCartId));
    expect(meta.replacesTxId, 'tx1');

    final prabayar = container.read(cartPrabayarProvider(kMainCartId));
    expect(prabayar, hasLength(1));
    expect(prabayar.single.amount, 20000);
  });

  testWidgets(
      'nota TEMPO murni (paid=0) -> TIDAK ditawari Pra-Bayar sama sekali',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await seedTxWithItem(db, 'tx2', paid: 0, status: 'tempo');

    await pumpReceipt(tester, db, 'tx2');

    await tester.tap(find.text('Batalkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batalkan & Susun Ulang'));
    await tester.pumpAndSettle();

    expect(find.text('Bawa Pembayaran Lama?'), findsNothing,
        reason: 'nota tempo murni belum ada uang masuk sama sekali');
  });

  testWidgets(
      'nota dgn PELANGGAN TERDAFTAR: "Batalkan & Susun Ulang" harus '
      'membawa customerId + customerName (resolve dari tabel customers, '
      'BUKAN tx.customerName mentah yg sengaja null) -> meta.hasCustomer '
      'true & label chip pelanggan terisi', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'cust1',
          name: 'Bu Sari',
        ));
    await seedTxWithItem(db, 'tx4', customerId: 'cust1');

    final container = await pumpReceipt(tester, db, 'tx4');

    await tester.tap(find.text('Batalkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batalkan & Susun Ulang'));
    await tester.pumpAndSettle();
    // Nota lunas -> ditawari Pra-Bayar dulu, lewati saja (fokus tes pelanggan).
    if (find.text('Bawa Pembayaran Lama?').evaluate().isNotEmpty) {
      await tester.tap(find.text('Lewati'));
      await tester.pumpAndSettle();
    }

    final meta = container.read(cartMetaProvider(kMainCartId));
    expect(meta.customerId, 'cust1');
    expect(meta.customerName, 'Bu Sari',
        reason: 'nama HARUS di-resolve dari tabel customers via customerId, '
            'bukan dibawa mentah dari tx.customerName (yg sengaja null utk '
            'pelanggan terdaftar)');
    expect(meta.hasCustomer, isTrue,
        reason: '`hasCustomer` cuma cek customerName -> kalau nama kosong, '
            'chip pelanggan di cart bar tampil seakan tidak ada pelanggan '
            'sama sekali, walau customerId sudah benar terisi');
  });

  testWidgets(
      'nota RETUR -> opsi "Batalkan & Susun Ulang" TIDAK ditawarkan sama '
      'sekali (guard isRetur)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await seedTxWithItem(db, 'tx3', internalNote: 'RETUR:tx-asal');

    await pumpReceipt(tester, db, 'tx3');

    // Nota retur TIDAK punya tombol "Batalkan" sama sekali di Struk (guard
    // !isRetur yg sudah ada) — jadi tidak ada apa pun utk ditap di sini.
    expect(find.text('Batalkan'), findsNothing);
  });
}
