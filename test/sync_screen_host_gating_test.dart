import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/pengaturan/sync_screen.dart';

import 'helpers/pump_app.dart';

/// Bug dilaporkan user: owner nyalakan izin "Izinkan Stok Minus" utk asisten,
/// tapi asisten tetap terblokir selamanya di device sungguhan (2 HP + sync
/// LAN). Root cause: layar Sync menampilkan "Jadi Host" utk `canSeeReports`
/// (owner ATAU asisten) — kalau ASISTEN yang jadi host & owner connect
/// sebagai klien ke asisten, perubahan master data (termasuk kasir_
/// permissions) yang dibuat owner TIDAK PERNAH sampai ke DB asisten, karena
/// arsitektur sync sengaja satu arah: klien cuma boleh upload append-only,
/// master data tidak pernah di-merge dari klien (lihat lan_sync_service.dart).
/// Owner harus SELALU jadi satu-satunya host supaya jadi sumber kebenaran
/// master data.
void main() {
  Future<AppDatabase> freshDb() async => AppDatabase(NativeDatabase.memory());

  testWidgets('OWNER melihat "Jadi Host"', (tester) async {
    final db = await freshDb();
    await pumpWithFakeApp(
      tester,
      db: db,
      device: const DeviceIdentity(
        storeUuid: 's', storeKey: 'k', storeName: 'Toko', deviceName: 'Owner',
        deviceCode: 'O1', deviceRole: 'owner'),
      child: const SyncScreen(),
    );
    expect(find.text('Jadi Host'), findsOneWidget);
    await db.close();
  });

  testWidgets(
      'ASISTEN TIDAK melihat "Jadi Host" — asisten wajib selalu jadi klien '
      'supaya perubahan master data dari owner (termasuk izin) bisa nyampe',
      (tester) async {
    final db = await freshDb();
    await pumpWithFakeApp(
      tester,
      db: db,
      device: const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Asisten',
          deviceCode: 'A1',
          deviceRole: 'asisten'),
      child: const SyncScreen(),
    );
    expect(find.text('Jadi Host'), findsNothing);
    await db.close();
  });

  testWidgets('KASIR TIDAK melihat "Jadi Host"', (tester) async {
    final db = await freshDb();
    await pumpWithFakeApp(
      tester,
      db: db,
      device: const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Kasir',
          deviceCode: 'K1',
          deviceRole: 'kasir'),
      child: const SyncScreen(),
    );
    expect(find.text('Jadi Host'), findsNothing);
    await db.close();
  });
}
