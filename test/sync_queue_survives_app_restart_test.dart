import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/sync_state_provider.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Bug nyata dilaporkan user: setelah app owner di-force-stop/clear cache
/// RAM, antrian sync yang belum sempat di-approve TAMPAK HILANG di layar
/// Sync — padahal baris `sync_upload_queue`-nya sendiri persisten di DB
/// (sudah dibuktikan `lan_sync_upload_queue_test.dart`). Akar masalah ada di
/// layer PROVIDER, bukan DB: `LanSyncService._db` adalah static field di
/// RAM (reset ke null saat proses app mati), dan `SyncStateNotifier.
/// _refreshQueue()` (versi lama) mengosongkan `state.queue` kalau
/// `!LanSyncService.isHostRunning` — jadi begitu app dibuka ulang, SEBELUM
/// owner sempat tap "Mulai Sebagai Host" lagi, antrian tampak kosong di
/// layar walau datanya masih ada.
///
/// Test ini mensimulasikan restart app SUNGGUHAN via file-backed DB
/// (tutup koneksi lama, buka baru ke file yang sama — sama seperti app
/// dibuka ulang oleh OS) + `ProviderContainer` BARU (setara app process
/// baru, bukan cuma widget rebuild) — TANPA pernah memanggil `startHost()`
/// atau `debugHostRunningOverride`, supaya sungguh-sungguh menyerupai
/// "app baru dibuka, host belum direstart owner".
void main() {
  const ownerDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Owner',
      deviceCode: 'O1',
      deviceRole: 'owner');

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pos_sync_queue_restart_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
      'antrian sync tetap tampil di syncStateProvider setelah "app restart" '
      '— walau host BELUM direstart owner (isHostRunning masih false)',
      () async {
    final dbPath = '${tempDir.path}/owner_restart.db';

    // Sesi app "sebelum di-kill": antrian masuk (simulasi via enqueue
    // langsung — proses HTTP sungguhan sudah ditest terpisah di
    // lan_sync_upload_queue_test.dart, di sini fokus ke layer provider).
    final dbBefore = AppDatabase(NativeDatabase(File(dbPath)));
    await dbBefore.enqueueSyncUpload(
      id: 'q1',
      fromIp: '192.168.1.50',
      tablesJson: '{"transactions":[{"id":"tx1"}]}',
      since: DateTime(2026, 1, 1),
      tablesSummary: '1 transaksi',
    );
    await dbBefore.close();

    // "App di-kill" — proses baru: koneksi DB baru ke file yang sama,
    // ProviderContainer baru (SyncStateNotifier baru dibuat dari nol, persis
    // seperti app dibuka ulang), TANPA startHost()/debugHostRunningOverride
    // sama sekali.
    final dbAfter = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(dbAfter.close);

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(dbAfter),
      deviceProvider.overrideWith(
          (ref) => DeviceNotifier()..state = ownerDevice),
    ]);
    addTearDown(container.dispose);

    expect(LanSyncService.isHostRunning, isFalse,
        reason: 'host SENGAJA belum direstart di test ini — antrian harus '
            'tetap tampil terlepas dari status ini');

    // Baca provider (memicu constructor SyncStateNotifier) lalu tunggu
    // refresh queue async selesai.
    container.read(syncStateProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(syncStateProvider);
    expect(state.queue, hasLength(1),
        reason: 'antrian sync harus tetap terbaca dari DB walau app baru '
            'saja "dibuka ulang" & host belum direstart manual — data '
            'TIDAK BOLEH tampak hilang dari sudut pandang owner');
    expect(state.queue.single.fromIp, '192.168.1.50');
  });
}
