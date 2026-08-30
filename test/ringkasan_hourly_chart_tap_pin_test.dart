import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/ringkasan/ringkasan_screen.dart';

/// Susulan (permintaan user): rincian jam di chart "Penjualan Per Jam" harus
/// dibuka via TAP (bukan tekan-tahan `Tooltip` bawaan Flutter yang otomatis
/// hilang begitu jari dilepas) dan PERMANEN sampai user tap area lain atau
/// scroll — bukan cuma sekilas.
void main() {
  Future<ProviderContainer> seedAndPump(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    final now = DateTime.now();
    // Jam 10: satu transaksi 50rb. Jam 14: satu transaksi 30rb.
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx10',
          localId: 'K1-1',
          status: 'lunas',
          total: 50000,
          paid: 50000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(DateTime(now.year, now.month, now.day, 10, 0)),
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx14',
          localId: 'K1-2',
          status: 'lunas',
          total: 30000,
          paid: 30000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(DateTime(now.year, now.month, now.day, 14, 0)),
        ));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Kasir',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: RingkasanScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
      'tap satu bar -> rincian jam muncul & PERMANEN (tanpa perlu terus '
      'menekan)', (tester) async {
    await seedAndPump(tester);

    expect(find.textContaining('10:00'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('hour_bar_10')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3)); // simulasi jeda lama
    expect(
        find.textContaining('10:00 — ${formatRupiah(50000)}'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('tap bar lain -> rincian pindah ke jam yang baru ditap',
      (tester) async {
    await seedAndPump(tester);

    await tester.tap(find.byKey(const ValueKey('hour_bar_10')));
    await tester.pump();
    expect(
        find.textContaining('10:00 — ${formatRupiah(50000)}'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hour_bar_14')));
    await tester.pump();
    expect(find.textContaining('10:00'), findsNothing);
    expect(
        find.textContaining('14:00 — ${formatRupiah(30000)}'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('tap area kosong di layar -> rincian tertutup', (tester) async {
    await seedAndPump(tester);

    await tester.tap(find.byKey(const ValueKey('hour_bar_10')));
    await tester.pump();
    expect(
        find.textContaining('10:00 — ${formatRupiah(50000)}'), findsOneWidget);

    // Tap judul section lain (area kosong scr interaksi, bukan bar chart
    // ataupun tombol/kartu lain).
    await tester.tap(find.text('Penjualan Per Jam (Hari Ini)'));
    await tester.pump();
    expect(find.textContaining('10:00'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('scroll layar -> rincian tertutup', (tester) async {
    await seedAndPump(tester);

    await tester.tap(find.byKey(const ValueKey('hour_bar_10')));
    await tester.pump();
    expect(
        find.textContaining('10:00 — ${formatRupiah(50000)}'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(find.textContaining('10:00'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
