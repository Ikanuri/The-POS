import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laci_meja/laci_meja_dashboard_screen.dart';

/// Item 52 susulan (permintaan user, screenshot device asli): barang
/// titip/ketinggalan dari NOTA YANG SAMA harus dikumpulkan jadi SATU
/// "frame" (Card), bukan baris rata terpisah — dan tiap baris menampilkan
/// qty + satuan produknya.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/laci-meja',
      routes: [
        GoRoute(
          path: '/laci-meja',
          builder: (_, __) => const LaciMejaDashboardScreen(),
        ),
        GoRoute(
          path: '/kasir/struk/:txId',
          builder: (_, state) => Scaffold(
              body: Text('Layar Struk ${state.pathParameters['txId']}')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  Future<void> seedTransaction(String id) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: id,
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
  }

  testWidgets(
      '2 barang dari NOTA SAMA dikumpulkan jadi 1 Card (frame); nota lain '
      'jadi Card terpisah', (tester) async {
    await seedTransaction('tx1');
    await seedTransaction('tx2');
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 2,
        priceAtSale: 5000,
        originalPrice: 5000,
        subtotal: 10000));
    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: 'tx1',
        itemName: 'Galon Aqua',
        jenis: 'titip',
        transactionItemId: 'i1');
    await db.addLeftBehindItem(
        id: 'l2', transactionId: 'tx1', itemName: 'Payung', jenis: 'ketinggalan');
    await db.addLeftBehindItem(
        id: 'l3', transactionId: 'tx2', itemName: 'Topi', jenis: 'titip');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNWidgets(2),
        reason: '2 nota berbeda -> 2 frame (Card), bukan 3 baris rata');

    // Card pertama (tx1) berisi 2 ListTile (Galon Aqua + Payung).
    final firstCard = find.byType(Card).first;
    expect(
        find.descendant(of: firstCard, matching: find.byType(ListTile)),
        findsNWidgets(2),
        reason: '2 barang dari nota yg SAMA harus 1 frame berisi 2 baris');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'barang yang tertaut transactionItemId menampilkan qty+satuan; yang '
      'tidak tertaut (entri lama) tidak menampilkan apa pun tambahan',
      (tester) async {
    await seedTransaction('tx1');
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Galon Aqua Produk'));
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(99), name: 'Pak'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1',
        productId: 'P1',
        isBaseUnit: const Value(true),
        unitTypeId: const Value(99)));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 3,
        priceAtSale: 5000,
        originalPrice: 5000,
        subtotal: 15000));

    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: 'tx1',
        itemName: 'Galon Aqua',
        jenis: 'titip',
        transactionItemId: 'i1');
    await db.addLeftBehindItem(
        id: 'l2',
        transactionId: 'tx1',
        itemName: 'Payung Lama',
        jenis: 'ketinggalan');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Galon Aqua ·'), findsOneWidget,
        reason: 'barang tertaut transactionItemId harus tampilkan qty+satuan');
    expect(find.text('Payung Lama'), findsOneWidget,
        reason: 'entri lama tanpa tautan tetap tampil apa adanya, tanpa qty');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('tombol "Ambil" (redesain minimalis) menandai barang diambil',
      (tester) async {
    await seedTransaction('tx1');
    await db.addLeftBehindItem(
        id: 'l1', transactionId: 'tx1', itemName: 'Galon Aqua', jenis: 'titip');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Sudah Diambil'), findsNothing,
        reason: 'label lama dihapus, redesain minimalis');
    expect(find.text('Ambil'), findsOneWidget);

    await tester.tap(find.text('Ambil'));
    await tester.pumpAndSettle();

    expect(find.text('Galon Aqua'), findsNothing,
        reason: 'setelah diambil, baris hilang dari daftar yg menggantung');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
