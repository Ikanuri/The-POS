import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/sync_state_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/shell/sync_status_banner.dart';

/// User lapor 2 hal soal `SyncStatusBanner` (setelah Item 21/Item 17 Fase 2):
/// (1) begitu antrian disetujui/ditolak, banner tetap MENETAP selamanya
/// menampilkan "Host aktif · [] menunggu persetujuan" selama host masih
/// hidup — padahal seharusnya tidak ada lagi yang perlu dipantau; (2) minta
/// bentuk kartu notifikasi inline (bukan bar status polos), dan kalau ada
/// notifikasi lain (di sini: event approve/tolak) muncul BERSAMAAN dgn
/// antrian lain yg masih menunggu, kartu antrian lama itu jangan hilang
/// total — tumpuk sebagai garis aksen tipis ("Compact Strip", varian yg
/// dipilih user dari mockup) di belakang kartu notifikasi baru.
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
  });

  testWidgets(
      'setelah TOLAK & tidak ada antrian lain — banner tampilkan konfirmasi '
      'sekali-tampil lalu benar-benar HILANG (bukan menetap sbg "Host '
      'aktif")', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    LanSyncService.debugSetDb(db);
    LanSyncService.debugHostRunningOverride = true;

    await db.enqueueSyncUpload(
      id: 'q1',
      fromIp: '192.168.1.50',
      tablesJson: '{"transactions":[]}',
      since: DateTime(2026, 1, 1),
      tablesSummary: '0 baris',
    );

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
    await tester.pumpAndSettle();

    expect(find.textContaining('Host aktif'), findsOneWidget,
        reason: 'antrian masih 1 — banner ongoing harus tampil');

    await container.read(syncStateProvider.notifier).rejectSync('q1');
    await tester.pump();

    expect(find.textContaining('Data sync ditolak'), findsOneWidget,
        reason: 'konfirmasi sekali-tampil harus muncul begitu ditolak');
    expect(find.textContaining('Host aktif'), findsNothing,
        reason: 'antrian sudah kosong — tidak ada lagi status ongoing utk '
            'ditampilkan berdampingan');

    // Habiskan timer auto-dismiss konfirmasi (4 detik).
    await tester.pump(const Duration(seconds: 5));

    expect(find.textContaining('Data sync ditolak'), findsNothing,
        reason: 'konfirmasi harus hilang sendiri — TIDAK boleh menetap '
            'selamanya walau host masih aktif (laporan nyata user)');
    expect(find.byType(SyncStatusBanner), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing,
        reason: 'banner harus benar-benar kosong (SizedBox.shrink), bukan '
            'cuma teksnya yang berubah');
  });

  testWidgets(
      'TOLAK satu item PADAHAL antrian lain masih menunggu — kartu ongoing '
      'lama TIDAK hilang, tertumpuk sbg garis aksen tipis di belakang kartu '
      'konfirmasi baru (Compact Strip)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    LanSyncService.debugSetDb(db);
    LanSyncService.debugHostRunningOverride = true;

    await db.enqueueSyncUpload(
      id: 'q-a',
      fromIp: '192.168.1.50',
      tablesJson: '{"transactions":[]}',
      since: DateTime(2026, 1, 1),
      tablesSummary: '0 baris',
    );
    await db.enqueueSyncUpload(
      id: 'q-b',
      fromIp: '192.168.1.60',
      tablesJson: '{"transactions":[]}',
      since: DateTime(2026, 1, 1),
      tablesSummary: '0 baris',
    );

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
    await tester.pumpAndSettle();
    expect(find.textContaining('2 menunggu persetujuan'), findsOneWidget);

    // Tolak SATU item saja — q-b masih menunggu.
    await container.read(syncStateProvider.notifier).rejectSync('q-a');
    await tester.pump();

    // Kartu depan: konfirmasi "ditolak". Strip belakang: ongoing "1
    // menunggu persetujuan" TETAP ada, bukan lenyap.
    expect(find.textContaining('Data sync ditolak'), findsOneWidget);
    expect(find.byKey(const Key('sync_ongoing_strip')), findsOneWidget,
        reason: 'strip aksen tipis harus ada selama masih ada antrian LAIN '
            'yang menunggu di belakang kartu konfirmasi');

    // Setelah konfirmasi habis waktu, ongoing utk q-b harus kembali tampil
    // penuh (bukan ikut hilang).
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('1 menunggu persetujuan'), findsOneWidget,
        reason: 'antrian q-b yang belum ditolak harus tetap terlihat setelah '
            'kartu konfirmasi q-a hilang');
  });
}
