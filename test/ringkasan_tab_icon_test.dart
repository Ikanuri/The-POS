import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/shell/main_shell.dart';

/// Susulan (permintaan user): ikon tab Ringkasan dulu `grid_view` (kotak-
/// kotak, tidak menggambarkan "ringkasan" apa pun) — diganti ikon kertas +
/// pensil.
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
            for (final p in const [
              '/ringkasan',
              '/kasir',
              '/produk',
              '/pelanggan',
              '/laporan',
              '/pengaturan'
            ])
              GoRoute(path: p, builder: (_, __) => Scaffold(body: Text('Layar $p'))),
          ],
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider.overrideWith((ref) => DeviceNotifier()
          ..state = const DeviceIdentity(
            storeUuid: 'u',
            storeKey: 'k',
            storeName: 'Toko Uji',
            deviceName: 'Owner Uji',
            deviceCode: 'K1',
            deviceRole: 'owner',
          )),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  testWidgets('tab Ringkasan pakai ikon kertas+pensil, bukan grid kotak-kotak',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.note_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_outlined), findsNothing,
        reason: 'ikon grid lama tidak boleh dipakai lagi di bottom nav');

    // Ikon terpilih (versi terisi) muncul begitu tab Ringkasan aktif.
    await tester.tap(find.text('Ringkasan'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.note_alt), findsOneWidget);
    expect(find.byIcon(Icons.grid_view), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
