import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laci_meja/laci_meja_dashboard_screen.dart';

/// Item 52 susulan (koreksi user) — tap kartu di dashboard Laci Meja
/// redirect ke nota terkait, mekanisme SAMA PERSIS dgn Lacak Hutang
/// (HutangTab -> '/kasir/struk/:txId'), BUKAN sekadar menyimpan
/// transactionId tanpa jalur navigasi apa pun.
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

  Future<String> seedTransaction(String id) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: id,
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    return id;
  }

  testWidgets('tap kartu Titip/Ketinggalan -> redirect ke struk nota terkait',
      (tester) async {
    final txId = await seedTransaction('tx1');
    await db.addLeftBehindItem(
        id: 'l1', transactionId: txId, itemName: 'Payung', jenis: 'titip');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Payung'));
    await tester.pumpAndSettle();

    expect(find.text('Layar Struk tx1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('tap kartu Pinjaman -> redirect ke struk nota terkait',
      (tester) async {
    final txId = await seedTransaction('tx1');
    await db.addBorrowedItem(
        id: 'b1', transactionId: txId, itemName: 'Galon Aqua', qty: 2);

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pinjaman'));
    await tester.pumpAndSettle();

    // Redesain kartu: baris pinjaman sekarang "<barang> · Sisa x dari y",
    // jadi teksnya tidak lagi persis nama barang saja.
    await tester.tap(find.textContaining('Galon Aqua'));
    await tester.pumpAndSettle();

    expect(find.text('Layar Struk tx1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tap kartu Pre-order DENGAN transactionId -> redirect ke struk; '
      'TANPA transactionId (titip wadah saja) -> tidak ada aksi/tidak crash',
      (tester) async {
    final txId = await seedTransaction('tx1');
    await db.addPreorderEntry(
        id: 'p1',
        productId: 'prod1',
        productUnitId: 'unit1',
        customerName: 'Budi (ada nota)',
        qtyOrdered: 1,
        transactionId: txId);
    await db.addPreorderEntry(
        id: 'p2',
        productId: 'prod1',
        productUnitId: 'unit1',
        customerName: 'Ani (titip wadah saja)',
        qtyOrdered: 1);

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pre-order'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ani (titip wadah saja)'));
    await tester.pumpAndSettle();
    expect(find.text('Layar Struk tx1'), findsNothing,
        reason: 'tanpa transactionId, tap tidak boleh navigasi ke mana pun');
    expect(find.text('Pre-order'), findsOneWidget,
        reason: 'tetap di dashboard, bukan crash');

    await tester.tap(find.text('Budi (ada nota)'));
    await tester.pumpAndSettle();
    expect(find.text('Layar Struk tx1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
