import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/pengaturan/sync_screen.dart';

/// Item 17 Fase 2 — 2 fitur UI baru: (1) tombol "Tolak" di antrian sync
/// sekarang WAJIB konfirmasi eksplisit sebelum eksekusi (reject sudah
/// PERMANEN, lihat dok `LanSyncService.rejectSync`); (2) tombol baru
/// "Sync Ulang Penuh" (reset watermark upload klien).
///
/// Pakai seam `debugSetDb`+`debugHostRunningOverride` (BUKAN `startHost()`
/// sungguhan — testWidgets + HttpServer asli terbukti hang, lihat dok seam
/// itu) supaya antrian `sync_upload_queue` bisa diisi & diuji end-to-end
/// tanpa socket sungguhan.
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
      'tombol Tolak WAJIB konfirmasi — Batal tidak menghapus, Tolak di '
      'dialog benar-benar menghapus dari antrian', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    LanSyncService.debugSetDb(db);
    LanSyncService.debugHostRunningOverride = true;

    await db.enqueueSyncUpload(
      id: 'q1',
      fromIp: '192.168.1.50',
      tablesJson: '{"transactions":[{"id":"tx1"}]}',
      since: DateTime(2026, 1, 1),
      tablesSummary: '1 transaksi',
    );

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = ownerDevice),
    ]);
    addTearDown(container.dispose);

    // Surface generus (pola sama spt pump_app.dart) — ListView di layar ini
    // lazy-build anak di luar viewport, default 800x600 flutter_test tidak
    // cukup utk kartu antrian + card host di atasnya.
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SyncScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('192.168.1.50'), findsOneWidget);

    // Tap "Tolak" → dialog konfirmasi muncul.
    await tester.tap(find.text('Tolak'));
    await tester.pumpAndSettle();
    expect(find.text('Tolak Data Sync?'), findsOneWidget);

    // "Batal" — item TIDAK boleh terhapus.
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.50'), findsOneWidget,
        reason: 'Batal di dialog tidak boleh menghapus antrian');
    expect(await db.listSyncUploadQueue(), hasLength(1));

    // Tap "Tolak" lagi → kali ini konfirmasi "Tolak" di dalam dialog.
    await tester.tap(find.text('Tolak'));
    await tester.pumpAndSettle();
    // Ada 2 "Tolak" di layar sekarang: tombol asli (tertutup dialog) +
    // tombol dialog — cari yg di dalam AlertDialog.
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Tolak')));
    await tester.pumpAndSettle();

    expect(find.text('192.168.1.50'), findsNothing,
        reason: 'setelah konfirmasi, item harus hilang dari antrian');
    expect(await db.listSyncUploadQueue(), isEmpty,
        reason: 'reject harus benar-benar menghapus baris dari DB (permanen)');
  });

  testWidgets(
      'tombol "Sync Ulang Penuh" mereset watermark upload setelah '
      'konfirmasi', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.setSetting(
        'last_sync_upload_confirmed_at', DateTime(2026, 1, 1).toIso8601String());

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          deviceProvider.overrideWith(
              (ref) => DeviceNotifier()..state = ownerDevice),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SyncScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sync Ulang Penuh'));
    await tester.pumpAndSettle();
    expect(find.text('Sync Ulang Penuh?'), findsOneWidget);

    await tester.tap(find.text('Ya, Reset'));
    await tester.pumpAndSettle();

    final watermark = await db.getSetting('last_sync_upload_confirmed_at');
    expect(watermark, isEmpty,
        reason: 'watermark upload harus direset (string kosong = fallback '
            'epoch di LanSyncService._loadUploadWatermark)');
  });
}
