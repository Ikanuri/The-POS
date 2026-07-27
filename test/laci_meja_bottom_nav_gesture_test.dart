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
              builder: (_, __) => const Scaffold(body: Text('Layar Kasir')),
              routes: [
                GoRoute(
                  path: 'laci-meja',
                  builder: (_, __) => const LaciMejaDashboardScreen(),
                ),
              ],
            ),
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
      'tekan-TAHAN tab Kasir membuka menu ikon, "Laci Meja" navigasi ke '
      'dashboard', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Kasir'));
    await tester.pumpAndSettle();

    // Menu redesain: HANYA ikon (tanpa label teks), dicari lewat tooltip.
    expect(find.byTooltip('Buka Kasir'), findsOneWidget);
    expect(find.byTooltip('Buka Laci Meja'), findsOneWidget);

    await tester.tap(find.byTooltip('Buka Laci Meja'));
    await tester.pumpAndSettle();

    expect(find.text('Laci Meja'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tekan-TAHAN lalu pilih ikon Kasir tetap di tab Kasir (menu tertutup, '
      'bukan navigasi ganda)', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Kasir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Buka Kasir'));
    await tester.pumpAndSettle();

    expect(find.text('Layar Kasir'), findsOneWidget);
    expect(find.byTooltip('Buka Kasir'), findsNothing,
        reason: 'menu harus tertutup');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'redesain menu (permintaan user): HANYA ikon, tanpa label teks '
      '"Buka Kasir"/"Buka Laci Meja"', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Kasir'));
    await tester.pumpAndSettle();

    expect(find.text('Buka Kasir'), findsNothing,
        reason: 'label teks HARUS dihilangkan, sisakan ikon saja');
    expect(find.text('Buka Laci Meja'), findsNothing);
    expect(find.byTooltip('Buka Kasir'), findsOneWidget);
    expect(find.byTooltip('Buka Laci Meja'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'redesain menu: muncul DI ATAS tab Kasir (bukan di samping), sudut '
      'rounded', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Kasir'));
    await tester.pumpAndSettle();

    final menuTop = tester.getTopLeft(find.byTooltip('Buka Kasir')).dy;
    final barTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
    expect(menuTop, lessThan(barTop),
        reason: 'menu wajib muncul DI ATAS bottom bar, bukan menimpa/di '
            'samping bar itu sendiri');

    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    final radius = clip.borderRadius as BorderRadius;
    expect(radius.topLeft.x, greaterThanOrEqualTo(16),
        reason: 'sudut menu harus rounded (bukan kotak persegi bawaan '
            'PopupMenuItem)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'redesain: delay tekan-tahan dipercepat — 300ms (di bawah 500ms '
      'bawaan Flutter) sudah cukup membuka menu', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(find.text('Kasir')));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byTooltip('Buka Kasir'), findsOneWidget,
        reason: 'delay tekan-tahan WAJIB lebih cepat dari 500ms bawaan '
            'Flutter (GestureDetector polos) — 300ms sudah harus cukup');

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
