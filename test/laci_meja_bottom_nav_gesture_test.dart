import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laci_meja/laci_meja_dashboard_screen.dart';
import 'package:the_pos/features/shell/main_shell.dart';

/// Item 52 ("Laci Meja") — gesture tekan-tahan tab "Kasir" di bottom nav
/// (ala Telegram): tap SINGKAT tetap navigasi normal (perilaku lama tidak
/// berubah), tekan-TAHAN membuka menu "Buka Kasir"/"Buka Laci Meja", dan
/// badge jumlah gabungan selalu terlihat di ikon Kasir tanpa perlu ditahan.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/kasir',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(
                path: '/ringkasan',
                builder: (_, __) => const Scaffold(body: Text('Layar Ringkasan'))),
            GoRoute(
                path: '/kasir',
                builder: (_, __) => const Scaffold(body: Text('Layar Kasir'))),
            GoRoute(
                path: '/produk',
                builder: (_, __) => const Scaffold(body: Text('Layar Produk'))),
            GoRoute(
                path: '/pelanggan',
                builder: (_, __) => const Scaffold(body: Text('Layar Pelanggan'))),
            GoRoute(
                path: '/laporan',
                builder: (_, __) => const Scaffold(body: Text('Layar Laporan'))),
            GoRoute(
                path: '/pengaturan',
                builder: (_, __) => const Scaffold(body: Text('Layar Pengaturan'))),
          ],
        ),
        GoRoute(
          path: '/laci-meja',
          builder: (_, __) => const LaciMejaDashboardScreen(),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider.overrideWith((ref) => DeviceNotifier()
          ..state = const DeviceIdentity(
            storeUuid: 'test-store-uuid',
            storeKey: 'test-store-key',
            storeName: 'Toko Uji',
            deviceName: 'Owner Uji',
            deviceCode: 'K1',
            deviceRole: 'owner',
          )),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    );
  }

  testWidgets('tap SINGKAT tab lain tetap navigasi normal (tidak dimakan '
      'gesture long-press)', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.text('Layar Kasir'), findsOneWidget);

    await tester.tap(find.text('Produk'));
    await tester.pumpAndSettle();
    expect(find.text('Layar Produk'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tap SINGKAT tab Kasir dari tab LAIN tetap navigasi normal — segmen '
      'overlay long-press yg menutupi ikon Kasir TIDAK BOLEH menelan tap '
      'biasa (harus HitTestBehavior.translucent, bukan opaque)', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Produk'));
    await tester.pumpAndSettle();
    expect(find.text('Layar Produk'), findsOneWidget);

    await tester.tap(find.text('Kasir'));
    await tester.pumpAndSettle();
    expect(find.text('Layar Kasir'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tekan-TAHAN tab Kasir membuka menu, "Buka Laci Meja" navigasi ke '
      'dashboard', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Kasir'));
    await tester.pumpAndSettle();

    expect(find.text('Buka Kasir'), findsOneWidget);
    expect(find.text('Buka Laci Meja'), findsOneWidget);

    await tester.tap(find.text('Buka Laci Meja'));
    await tester.pumpAndSettle();

    expect(find.text('Laci Meja'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tekan-TAHAN lalu pilih "Buka Kasir" tetap di tab Kasir (menu tertutup, '
      'bukan navigasi ganda)', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Kasir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buka Kasir'));
    await tester.pumpAndSettle();

    expect(find.text('Layar Kasir'), findsOneWidget);
    expect(find.text('Buka Kasir'), findsNothing, reason: 'menu harus tertutup');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'badge jumlah gabungan tampil di ikon Kasir tanpa perlu ditahan dulu, '
      'begitu ada entri Laci Meja aktif', (tester) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'tx1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.addLeftBehindItem(
        id: 'l1', transactionId: 'tx1', itemName: 'Payung', jenis: 'titip');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget,
        reason: 'badge angka 1 harus terlihat tanpa tap/tahan apa pun');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
