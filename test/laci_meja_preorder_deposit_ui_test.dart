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

/// Permintaan user: begitu pre-order (LPG jaminan belum bayar, nota sudah
/// lunas utk item lain) DIPENUHI dari dashboard Laci Meja, kasir harus
/// langsung ditawari mengumpulkan DP/jaminan yang tadinya dikunci Rp 0.
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

  Future<void> seed() async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Gas LPG 3kg'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'tx1',
          status: 'lunas',
          total: 30000,
          paid: 30000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti_lain',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 30000,
          originalPrice: 30000,
          subtotal: 30000,
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti_lpg',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 0,
          originalPrice: 20000,
          subtotal: 0,
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: 'tx1', amount: 30000, method: 'tunai'));
    await db.addPreorderEntry(
        id: 'po1',
        productId: 'P1',
        productUnitId: 'U1',
        customerName: 'Umum',
        qtyOrdered: 1,
        transactionId: 'tx1',
        transactionItemId: 'ti_lpg');
  }

  testWidgets(
      'tap "Penuhi" -> muncul sheet DP/jaminan -> konfirmasi -> subtotal '
      'nota naik & preorder tercatat lunas', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seed();

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pre-order'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Penuhi'));
    await tester.pumpAndSettle();

    expect(find.textContaining('DP/Jaminan'), findsOneWidget,
        reason: 'sheet kumpul DP harus terbuka otomatis stlh dipenuhi');

    // Tepat satu FilledButton di dalam sheet = tombol Bayar.
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    final item = await (db.select(db.transactionItems)
          ..where((t) => t.id.equals('ti_lpg')))
        .getSingle();
    expect(item.subtotal, 20000);

    final entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(entry.paid, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tap "Penuhi" pada pre-order yang tidak ada DP tertunda -> tidak '
      'ada sheet yang muncul', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Gas LPG 3kg'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'tx1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    // Tidak ada transactionItemId -> tidak ada apa pun yg perlu dikumpulkan.
    await db.addPreorderEntry(
        id: 'po1',
        productId: 'P1',
        productUnitId: 'U1',
        customerName: 'Umum',
        qtyOrdered: 1,
        transactionId: 'tx1');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pre-order'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Penuhi'));
    await tester.pumpAndSettle();

    expect(find.textContaining('DP/Jaminan'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
