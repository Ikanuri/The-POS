import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/pengaturan/kategori_harga_screen.dart';
import 'package:the_pos/features/pengaturan/pengaturan_screen.dart';
import 'package:the_pos/features/produk/produk_list_screen.dart';

import 'helpers/pump_app.dart';

/// Revisi 3 (permintaan user): menu "Kategori Harga" PINDAH dari layar
/// Pengaturan ke layar Produk — lebih dekat konteksnya. Route-nya sendiri
/// TETAP `/pengaturan/kategori-harga` (URL internal), cuma entry point yang
/// pindah.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  testWidgets(
      'menu "Kategori Harga" TIDAK LAGI ada di layar Pengaturan',
      (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const PengaturanScreen());

    expect(find.text('Kategori Harga'), findsNothing);
    expect(
        find.text('Kelompokkan produk & atur margin per produk'),
        findsNothing);

    await drain(tester);
  });

  testWidgets(
      'layar Produk punya entry point "Kategori Harga" yang membuka '
      'KategoriHargaScreen (lintas-tab, route tetap /pengaturan/'
      'kategori-harga, sama pola dgn push antar-tab lain di app ini)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/produk',
      routes: [
        GoRoute(
          path: '/produk',
          builder: (_, __) => const ProdukListScreen(),
        ),
        GoRoute(
          path: '/pengaturan/kategori-harga',
          builder: (_, __) => const KategoriHargaScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Kategori Harga'), findsOneWidget,
        reason: 'entry point baru ada di AppBar layar Produk');

    await tester.tap(find.byTooltip('Kategori Harga'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Kategori Harga'), findsOneWidget,
        reason: 'tap membuka KategoriHargaScreen (route tidak berubah, '
            'cuma entry point-nya)');

    await drain(tester);
  });
}
