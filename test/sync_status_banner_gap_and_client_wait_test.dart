import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/sync_state_provider.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/pengaturan/pengaturan_screen.dart';
import 'package:the_pos/features/shell/sync_status_banner.dart';

/// 2 follow-up laporan user pasca reposisi `SyncStatusBanner` (Task #8):
///
/// (1) Ada celah kosong aneh di atas kartu banner (dibanding notifikasi
/// inline lain, mis. "Pesanan ditahan" di Kasir) — akar masalah: widget ini
/// masih dibungkus `SafeArea(bottom:false)` peninggalan desain LAMA (dulu
/// dipasang di ATAS segalanya di `MainShell`, sebelum AppBar mana pun,
/// makanya butuh SafeArea sendiri). Sekarang SELALU dipasang DI BAWAH
/// AppBar/toolbar (yang sudah mengonsumsi area status bar), jadi SafeArea
/// di sini jadi inset GANDA. Fix: SafeArea dihapus total.
///
/// (2) Di device KLIEN (bukan host), banner/tahap sync selalu "infinite
/// loading" (spinner "menunggu persetujuan owner…" TIDAK PERNAH berhenti)
/// walau owner sudah membuat keputusan (approve/tolak) — akar masalah:
/// `ClientSyncPhase.waitingApproval` dianggap `clientSyncing` (masih
/// "syncing aktif"), padahal protokol sync itu connectionless — begitu
/// respons host diterima, TIDAK ADA proses aktif apa pun lagi yang bisa
/// dipantau; app ini juga TIDAK PUNYA kanal utk tahu KAPAN/APAKAH owner
/// akhirnya memutuskan (client tidak polling ke host). Fix: `waitingApproval`
/// dikeluarkan dari `clientSyncing`, diganti konfirmasi sekali-tampil
/// ("Terkirim — menunggu peninjauan owner") yang otomatis hilang.
Future<T> _withRealHttp<T>(Future<T> Function() body) => HttpOverrides.runZoned(
      body,
      createHttpClient: (context) => Zone.root.run(() {
        final prevGlobal = HttpOverrides.current;
        HttpOverrides.global = null;
        try {
          return HttpClient(context: context);
        } finally {
          HttpOverrides.global = prevGlobal;
        }
      }),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/network_info'),
          (call) async => call.method == 'wifiIPAddress' ? '127.0.0.1' : null);

  tearDown(() {
    LanSyncService.debugClearProposals();
  });

  test(
      'SyncState.clientSyncing TIDAK menganggap waitingApproval sbg proses '
      'aktif (akar bug infinite loading)', () {
    const s = SyncState(clientPhase: ClientSyncPhase.waitingApproval);
    expect(s.clientSyncing, isFalse,
        reason: 'begitu respons host diterima, tidak ada proses aktif lagi '
            'yang bisa dipantau dari sisi app ini — TIDAK BOLEH dianggap '
            '"masih syncing"');
    expect(const SyncState(clientPhase: ClientSyncPhase.sending).clientSyncing,
        isTrue,
        reason: 'tahap network AKTIF tetap harus dianggap syncing');
  });

  testWidgets(
      'SyncStatusBanner TIDAK dibungkus SafeArea lagi (akar celah kosong '
      'di atas kartu — sekarang selalu di bawah AppBar yg sudah konsumsi '
      'area status bar)', (tester) async {
    LanSyncService.debugAddProposal(PendingProductProposal(
      id: 'p1',
      fromIp: '192.168.1.50',
      arrivedAt: DateTime.now(),
      rows: const {},
      productCount: 1,
    ));

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const ownerDevice = DeviceIdentity(
        storeUuid: 's',
        storeKey: 'k',
        storeName: 'Toko',
        deviceName: 'Owner',
        deviceCode: 'O1',
        deviceRole: 'owner');
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
          home: const PengaturanScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SyncStatusBanner), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(SyncStatusBanner), matching: find.byType(SafeArea)),
        findsNothing,
        reason: 'SafeArea peninggalan desain lama (dulu di atas segalanya) '
            'bikin inset ganda sekarang widget ini selalu di bawah AppBar');
  });

  test(
      'Setelah owner setuju/tolak & klien sync ulang — banner TIDAK '
      'nampilkan spinner "menunggu…" selamanya, konfirmasi sekali-tampil '
      'muncul lalu status kembali idle', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');
    addTearDown(LanSyncService.stopHost);

    const clientDevice = DeviceIdentity(
        storeUuid: 's',
        storeKey: 'shared-store-key',
        storeName: 'Toko',
        deviceName: 'Kasir',
        deviceCode: 'K1',
        deviceRole: 'kasir');
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(clientDb),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = clientDevice),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(syncStateProvider.notifier);
    await _withRealHttp(() => notifier.sync(ip: '127.0.0.1', token: token));

    final state = container.read(syncStateProvider);
    expect(state.clientPhase, ClientSyncPhase.waitingApproval,
        reason: 'protokol SELALU antre approval — lihat dok B-4');
    expect(state.clientSyncing, isFalse,
        reason: 'permintaan klien sudah SELESAI teknis; tidak ada proses '
            'aktif tersisa utk ditunggu, jadi HARUS bukan "syncing"');
    expect(state.transientMessage, contains('menunggu peninjauan owner'),
        reason: 'konfirmasi sekali-tampil harus muncul menggantikan spinner '
            'permanen lama');
  });
}
