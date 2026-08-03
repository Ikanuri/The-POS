import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/pengaturan/sync_screen.dart';

/// Susulan (permintaan user) — layar review usulan pelanggan client->host,
/// PARALEL dari review usulan produk (Item 40) & Laci Meja (Item 52) — pola
/// test sama: `debugAddCustomerProposal` (seam test-only, TANPA host/HTTP
/// sungguhan — lihat dok panjang di `sync_screen_host_lifecycle_test.dart`
/// soal `testWidgets` + `HttpServer` asli yang bikin hang).
void main() {
  const ownerDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Owner',
      deviceCode: 'O1',
      deviceRole: 'owner');

  tearDown(() {
    LanSyncService.debugHostRunningOverride = false;
    LanSyncService.debugClearCustomerProposals();
  });

  testWidgets(
      'kartu "Usulan Pelanggan" tampil di layar Sync, tap Tinjau -> baris '
      'muncul di layar review, Terapkan -> tertulis ke DB host & antrian '
      'kosong', (tester) async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);

    // Bangun usulan NYATA (row-set asli hasil dumpLocalCustomerProposals)
    // dari DB kasir simulasi, bukan data palsu.
    final kasirDb = AppDatabase(NativeDatabase.memory());
    await kasirDb.into(kasirDb.customers).insert(CustomersCompanion.insert(
          id: 'c1',
          name: 'Budi',
          phone: const Value('08123'),
          locallyModified: const Value(true),
        ));
    final rows = await kasirDb.dumpLocalCustomerProposals();
    await kasirDb.close();

    LanSyncService.debugHostRunningOverride = true;
    LanSyncService.debugAddCustomerProposal(PendingCustomerProposal(
      id: 'prop1',
      fromIp: '192.168.2.50',
      arrivedAt: DateTime.now(),
      rows: rows,
      customerCount: 1,
    ));

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(hostDb),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = ownerDevice),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SyncScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Usulan Pelanggan (1)'), findsOneWidget);
    expect(find.textContaining('1 pelanggan diusulkan'), findsOneWidget);

    await tester.tap(find.text('Tinjau'));
    await tester.pumpAndSettle();

    expect(find.text('Budi'), findsOneWidget);
    expect(find.text('08123'), findsOneWidget);

    await tester.tap(find.text('Terapkan (1 pelanggan)'));
    await tester.pumpAndSettle();

    // Kembali ke layar Sync, antrian usulan pelanggan sudah kosong.
    expect(find.textContaining('Usulan Pelanggan'), findsNothing);

    final hostRows = await hostDb.select(hostDb.customers).get();
    expect(hostRows, hasLength(1));
    expect(hostRows.single.name, 'Budi');
    expect(hostRows.single.locallyModified, isFalse,
        reason: 'owner sudah approve, flag usulan dilepas');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'uncheck pelanggan sebelum Terapkan -> TIDAK ikut tertulis ke DB host',
      (tester) async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);

    final kasirDb = AppDatabase(NativeDatabase.memory());
    await kasirDb.into(kasirDb.customers).insert(CustomersCompanion.insert(
          id: 'c1',
          name: 'Budi',
          locallyModified: const Value(true),
        ));
    await kasirDb.into(kasirDb.customers).insert(CustomersCompanion.insert(
          id: 'c2',
          name: 'Ani',
          locallyModified: const Value(true),
        ));
    final rows = await kasirDb.dumpLocalCustomerProposals();
    await kasirDb.close();

    LanSyncService.debugHostRunningOverride = true;
    LanSyncService.debugAddCustomerProposal(PendingCustomerProposal(
      id: 'prop1',
      fromIp: '192.168.2.50',
      arrivedAt: DateTime.now(),
      rows: rows,
      customerCount: 2,
    ));

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(hostDb),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = ownerDevice),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SyncScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tinjau'));
    await tester.pumpAndSettle();

    // Semua default tercentang -> uncheck "Ani".
    await tester.tap(find.text('Ani'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Terapkan (1 pelanggan)'));
    await tester.pumpAndSettle();

    final hostRows = await hostDb.select(hostDb.customers).get();
    expect(hostRows, hasLength(1));
    expect(hostRows.single.name, 'Budi');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
