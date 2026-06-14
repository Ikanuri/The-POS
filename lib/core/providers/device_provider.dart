import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../services/crypto_service.dart';

/// Identitas device: store_key di FlutterSecureStorage (hardware-backed
/// keystore), identitas lain di SharedPreferences.
/// SharedPreferences tetap dipakai karena store_key dibutuhkan sebelum DB
/// bisa dibuka, tapi store_key sendiri sudah dipindah ke secure storage.
class DeviceIdentity {
  const DeviceIdentity({
    this.storeUuid,
    this.storeKey,
    this.storeName = '',
    this.deviceName = '',
    this.deviceCode = '',
    this.deviceRole = '',
    this.kdfDbVersion = 1,
  });

  final String? storeUuid;
  final String? storeKey;
  final String storeName;
  final String deviceName;
  final String deviceCode;
  final String deviceRole; // owner | kasir | asisten
  /// Versi KDF yang dipakai DB ini. 1 = 10k iter, 2 = 210k iter.
  final int kdfDbVersion;

  bool get isConfigured => storeUuid != null && storeKey != null;
  bool get isOwner => deviceRole == 'owner';
  bool get canSeeReports => deviceRole == 'owner' || deviceRole == 'asisten';
}

class DeviceNotifier extends StateNotifier<DeviceIdentity> {
  DeviceNotifier() : super(const DeviceIdentity());

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keys = (
    storeUuid: 'store_uuid',
    storeKey: 'store_key',
    storeName: 'store_name',
    deviceName: 'device_name',
    deviceCode: 'device_code',
    deviceRole: 'device_role',
  );

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Migrate store_key from SharedPreferences to FlutterSecureStorage if needed.
    final legacyKey = prefs.getString(_keys.storeKey);
    String? storeKey = await _secureStorage.read(key: _keys.storeKey);
    if (storeKey == null && legacyKey != null) {
      await _secureStorage.write(key: _keys.storeKey, value: legacyKey);
      await prefs.remove(_keys.storeKey);
      storeKey = legacyKey;
    }

    state = DeviceIdentity(
      storeUuid: prefs.getString(_keys.storeUuid),
      storeKey: storeKey,
      storeName: prefs.getString(_keys.storeName) ?? '',
      deviceName: prefs.getString(_keys.deviceName) ?? '',
      deviceCode: prefs.getString(_keys.deviceCode) ?? '',
      deviceRole: prefs.getString(_keys.deviceRole) ?? '',
      kdfDbVersion: prefs.getInt('kdf_db_version') ?? 1,
    );
  }

  /// Dipanggil oleh databaseProvider setelah migrasi KDF berhasil.
  Future<void> markKdfMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('kdf_db_version', 2);
    state = DeviceIdentity(
      storeUuid: state.storeUuid,
      storeKey: state.storeKey,
      storeName: state.storeName,
      deviceName: state.deviceName,
      deviceCode: state.deviceCode,
      deviceRole: state.deviceRole,
      kdfDbVersion: 2,
    );
  }

  /// Jalur "Setup Toko Baru" — device ini jadi Owner.
  Future<void> setupNewStore({
    required String storeName,
    required String deviceName,
    required String deviceCode,
  }) async {
    await _persist(DeviceIdentity(
      storeUuid: const Uuid().v4(),
      storeKey: CryptoService.generateStoreKey(),
      storeName: storeName,
      deviceName: deviceName,
      deviceCode: deviceCode,
      deviceRole: 'owner',
    ));
  }

  /// Jalur "Gabung Toko" — dari payload QR pairing.
  Future<void> joinStore({
    required String storeUuid,
    required String storeKey,
    required String storeName,
    required String role,
    required String deviceName,
    required String deviceCode,
  }) async {
    await _persist(DeviceIdentity(
      storeUuid: storeUuid,
      storeKey: storeKey,
      storeName: storeName,
      deviceName: deviceName,
      deviceCode: deviceCode,
      deviceRole: role,
    ));
  }

  Future<void> _persist(DeviceIdentity identity) async {
    final prefs = await SharedPreferences.getInstance();
    // store_key goes to hardware-backed secure storage.
    await _secureStorage.write(key: _keys.storeKey, value: identity.storeKey!);
    // Ensure no legacy plaintext copy remains.
    await prefs.remove(_keys.storeKey);
    await prefs.setString(_keys.storeUuid, identity.storeUuid!);
    await prefs.setString(_keys.storeName, identity.storeName);
    await prefs.setString(_keys.deviceName, identity.deviceName);
    await prefs.setString(_keys.deviceCode, identity.deviceCode);
    await prefs.setString(_keys.deviceRole, identity.deviceRole);
    state = identity;
  }
}

final deviceProvider =
    StateNotifierProvider<DeviceNotifier, DeviceIdentity>((ref) {
  return DeviceNotifier();
});

/// Database dibuka lazily setelah device terkonfigurasi.
/// B-5: saat kdf_db_version < 2, DB dibuka dengan key lama lalu di-rekey ke
/// key baru (210k iter). Proses ini transparan dan hanya sekali per device.
final databaseProvider = Provider<AppDatabase>((ref) {
  final device = ref.watch(deviceProvider);
  if (!device.isConfigured) {
    throw StateError('Database diakses sebelum setup selesai');
  }

  final storeKey = device.storeKey!;
  final newKey = CryptoService.deriveDbKeyHexV2(storeKey);
  final needsMigration = device.kdfDbVersion < 2;

  final db = AppDatabase.open(
    newKey,
    oldKeyForMigration: needsMigration ? deriveDatabaseKey(storeKey) : null,
  );

  if (needsMigration) {
    // Tandai migrasi selesai setelah DB berhasil dibuka.
    // Jika app crash sebelum ini, pada buka berikutnya migrasi diulang
    // (PRAGMA rekey idempotent karena key baru == key lama di DB yang sudah di-rekey).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deviceProvider.notifier).markKdfMigrated();
    });
  }

  ref.onDispose(db.close);
  return db;
});
