import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/pengaturan/alih_owner_screen.dart';

import 'helpers/pump_app.dart';

/// Item 27 "Alihkan Owner" — bagian "Buat File Alihan" (ekspor) HANYA utk
/// owner (cuma owner boleh mengekspor seluruh identitas toko), sedangkan
/// "Terima Alihan" (impor) tampil utk SEMUA role — sesuai keputusan user:
/// device MANAPUN (termasuk kasir/asisten aktif) boleh jadi penerima.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets('OWNER melihat "Buat File Alihan" DAN "Terima Alihan"',
      (tester) async {
    await pumpWithFakeApp(
      tester,
      db: db,
      device: const DeviceIdentity(
        storeUuid: 's',
        storeKey: 'k',
        storeName: 'Toko',
        deviceName: 'Owner',
        deviceCode: 'O1',
        deviceRole: 'owner',
      ),
      child: const AlihOwnerScreen(),
    );

    // "Buat File Alihan" muncul 2x (judul kartu + label tombol).
    expect(find.text('Buat File Alihan'), findsNWidgets(2));
    expect(find.text('Terima Alihan'), findsOneWidget);
  });

  testWidgets(
      'KASIR TIDAK melihat "Buat File Alihan", TAPI tetap melihat "Terima Alihan"',
      (tester) async {
    await pumpWithFakeApp(
      tester,
      db: db,
      device: const DeviceIdentity(
        storeUuid: 's',
        storeKey: 'k',
        storeName: 'Toko',
        deviceName: 'Kasir 1',
        deviceCode: 'K1',
        deviceRole: 'kasir',
      ),
      child: const AlihOwnerScreen(),
    );

    expect(find.text('Buat File Alihan'), findsNothing);
    expect(find.text('Terima Alihan'), findsOneWidget);
  });
}
