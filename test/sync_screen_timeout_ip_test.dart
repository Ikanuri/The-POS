import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/pengaturan/sync_screen.dart';

import 'helpers/pump_app.dart';

/// Item 39 — layar Sync WiFi: dropdown profil timeout (baru) & tombol
/// "Refresh IP" (baru, hanya muncul saat "Jadi Host" sedang aktif).
void main() {
  Future<AppDatabase> freshDb() async => AppDatabase(NativeDatabase.memory());

  const ownerDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Owner',
      deviceCode: 'O1',
      deviceRole: 'owner');

  testWidgets(
      'dropdown timeout default "Normal (default)" & tersimpan ke DB saat '
      'diganti', (tester) async {
    final db = await freshDb();
    await pumpWithFakeApp(tester, db: db, device: ownerDevice,
        child: const SyncScreen());

    expect(find.text('Normal (default)'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<SyncTimeoutProfile>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sangat Lambat (toko besar)').last);
    await tester.pumpAndSettle();

    final saved = await SyncTimeoutProfile.load(db);
    expect(saved, SyncTimeoutProfile.sangatLambat);

    await db.close();
  });

  testWidgets(
      'profil timeout yang sudah tersimpan sebelumnya ikut ter-load saat '
      'layar dibuka lagi', (tester) async {
    final db = await freshDb();
    await SyncTimeoutProfile.save(db, SyncTimeoutProfile.lambat);

    await pumpWithFakeApp(tester, db: db, device: ownerDevice,
        child: const SyncScreen());

    expect(find.text('Lambat (data besar/WiFi lemot)'), findsOneWidget);

    await db.close();
  });

  testWidgets(
      'tombol "Refresh IP" TIDAK muncul sebelum host dinyalakan (baru '
      'relevan setelah "Jadi Host" aktif)', (tester) async {
    final db = await freshDb();
    await LanSyncService.stopHost();

    await pumpWithFakeApp(tester, db: db, device: ownerDevice,
        child: const SyncScreen());

    expect(find.text('Refresh IP'), findsNothing);
    expect(find.text('Start Server'), findsOneWidget);

    await db.close();
  });

  // Catatan: alur PENUH tombol "Refresh IP" (start host sungguhan lewat
  // tap "Start Server" lalu tap "Refresh IP") SENGAJA tidak diuji lewat
  // testWidgets di sini — mem-bind HttpServer sungguhan (shelf_io.serve)
  // di dalam testWidgets terbukti bikin AppDatabase.close() sesudahnya
  // HANG tanpa batas waktu (ketahuan saat menulis test ini; kombinasi
  // TestWidgetsFlutterBinding + socket TCP asli, bukan bug di kode
  // produksi — lihat test DB-tier `startHost`+`refreshHostIp` polos
  // lewat plain `test()` di lan_sync_ip_detect_test.dart yang berjalan
  // normal tanpa widget). Perilaku start/refresh IP itu sendiri sudah
  // diverifikasi di level service (detectHostIp), bukan di level widget.
}
