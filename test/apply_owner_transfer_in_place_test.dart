import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Item 27 "Alihkan Owner" — `DeviceNotifier.applyOwnerTransferInPlace()`
/// dipakai device yang SUDAH ada datanya (kasir/asisten/owner toko lain)
/// menerima transfer identitas dari file BPOT1. Harus: (1) ganti
/// storeUuid/storeKey/storeName/role jadi milik toko yang ditransfer, (2)
/// TERAPKAN deviceName/deviceCode BARU yang diberikan pemanggil (BUKAN
/// otomatis warisi punya lama — bug ditemukan user via testing device asli:
/// device eks-kasir/asisten toko lain tampil tetap "Asisten"/"K1" walau
/// sudah jadi Owner, & `deviceCode` lama berisiko tabrakan dgn device lain
/// yg sudah pairing ke toko tujuan), (3) panggil rekey SEBELUM identitas
/// diganti (urutan terbalik = app tidak bisa buka DB lagi setelah restart).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final store = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
      switch (call.method) {
        case 'write':
          store[call.arguments['key'] as String] =
              call.arguments['value'] as String;
          return null;
        case 'read':
          return store[call.arguments['key'] as String];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  test(
      'menerapkan storeUuid/storeKey/storeName/role/deviceName/deviceCode '
      'BARU — TIDAK warisi deviceName/deviceCode lama device ini', () async {
    final notifier = DeviceNotifier();
    // Device ini sudah aktif sebagai kasir toko LAIN sebelum menerima transfer.
    await notifier.joinStore(
      storeUuid: 'uuid-toko-lama',
      storeKey: 'key-toko-lama',
      storeName: 'Toko Lama',
      role: 'kasir',
      deviceName: 'Kasir 1 - Fisik',
      deviceCode: 'K1',
    );

    final db = AppDatabase(NativeDatabase.memory());
    await notifier.applyOwnerTransferInPlace(
      db: db,
      storeUuid: 'uuid-toko-baru',
      storeKey: 'key-toko-baru',
      storeName: 'Toko Baru (Alihan)',
      deviceName: 'Owner',
      deviceCode: 'O1',
    );
    await db.close();

    expect(notifier.state.storeUuid, 'uuid-toko-baru');
    expect(notifier.state.storeKey, 'key-toko-baru');
    expect(notifier.state.storeName, 'Toko Baru (Alihan)');
    expect(notifier.state.deviceRole, 'owner',
        reason: 'device penerima SELALU jadi owner, terlepas dari role lama');
    expect(notifier.state.deviceName, 'Owner',
        reason: 'deviceName BARU dari pemanggil, BUKAN warisan "Kasir 1 - Fisik"');
    expect(notifier.state.deviceCode, 'O1',
        reason: 'deviceCode BARU, BUKAN warisan "K1" (cegah tabrakan prefix nota)');
  });

  test('persist ke SharedPreferences/SecureStorage benar2 tersimpan (bukan cuma state in-memory)',
      () async {
    final notifier = DeviceNotifier();
    await notifier.joinStore(
      storeUuid: 'u-lama',
      storeKey: 'k-lama',
      storeName: 'Lama',
      role: 'asisten',
      deviceName: 'Asisten Toko',
      deviceCode: 'A1',
    );
    final db = AppDatabase(NativeDatabase.memory());
    await notifier.applyOwnerTransferInPlace(
      db: db,
      storeUuid: 'u-baru',
      storeKey: 'k-baru',
      storeName: 'Baru',
      deviceName: 'Owner Baru',
      deviceCode: 'O1',
    );
    await db.close();

    // load() ulang dari storage — simulasikan device di-restart.
    final reloaded = DeviceNotifier();
    await reloaded.load();
    expect(reloaded.state.storeUuid, 'u-baru');
    expect(reloaded.state.storeKey, 'k-baru');
    expect(reloaded.state.deviceRole, 'owner');
    expect(reloaded.state.deviceName, 'Owner Baru');
    expect(reloaded.state.deviceCode, 'O1');
  });
}
