import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/pengaturan/sync_screen.dart';
import 'package:the_pos/features/shell/sync_status_banner.dart';

/// Item 21 (Fase 1) — regresi: sebelumnya `_SyncScreenState.dispose()`
/// SELALU memanggil `LanSyncService.stopHost()` tanpa syarat, jadi begitu
/// owner meninggalkan layar Sync (pindah tab), server host mati TOTAL walau
/// belum sempat menerima/approve data dari kasir/asisten. Sekarang lifecycle
/// host dipegang `syncStateProvider` (hidup lepas dari widget manapun) —
/// meninggalkan layar Sync TIDAK LAGI mematikan server.
///
/// Pakai `LanSyncService.debugHostRunningOverride` (seam test-only), BUKAN
/// `startHost()` sungguhan — `testWidgets` + `HttpServer` asli terbukti
/// bikin `AppDatabase.close()` hang tanpa batas (lihat catatan di
/// `sync_screen_timeout_ip_test.dart`/HANDOFF), pola sama seperti
/// `debugAddProposal` di `sync_screen_proposal_layout_test.dart`.
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
    LanSyncService.debugClearProposals();
  });

  testWidgets(
      'meninggalkan layar Sync (widget di-dispose) TIDAK mematikan host — '
      'beda dari perilaku lama', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    LanSyncService.debugHostRunningOverride = true;

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = ownerDevice),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SyncScreen()),
        ),
      ),
    );
    expect(LanSyncService.isHostRunning, isTrue);

    // Simulasikan "pindah tab" — SyncScreen dibuang dari tree (widget
    // State-nya di-dispose) sepenuhnya, diganti widget lain, TANPA
    // membongkar ProviderContainer (persis situasi navigasi GoRouter:
    // provider global tetap hidup, widget layar dibuang & dibangun ulang).
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: Text('Tab Lain')),
        ),
      ),
    );

    expect(LanSyncService.isHostRunning, isTrue,
        reason: 'meninggalkan layar Sync TIDAK BOLEH mematikan host — '
            'sync yang sedang berlangsung/menunggu approval tidak boleh '
            'terputus hanya karena owner pindah tab');
  });

  testWidgets(
      'SyncStatusBanner tampil di widget tree LAIN (bukan SyncScreen) '
      'selama host aktif', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    LanSyncService.debugHostRunningOverride = true;

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = ownerDevice),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SyncStatusBanner()),
        ),
      ),
    );

    expect(find.textContaining('Host aktif'), findsOneWidget,
        reason: 'banner status sync harus tampil di layar manapun selama '
            'host aktif, bukan cuma persis di SyncScreen');
  });

  testWidgets(
      'SyncStatusBanner TIDAK tampil kalau tidak ada aktivitas sync sama '
      'sekali (host mati, antrian kosong, klien idle)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = ownerDevice),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SyncStatusBanner()),
        ),
      ),
    );

    expect(find.textContaining('Host aktif'), findsNothing);
    expect(find.textContaining('Sync'), findsNothing);
  });
}
