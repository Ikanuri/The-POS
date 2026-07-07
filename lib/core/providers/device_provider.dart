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
  });

  final String? storeUuid;
  final String? storeKey;
  final String storeName;
  final String deviceName;
  final String deviceCode;
  final String deviceRole; // owner | kasir | asisten

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

  Future<void> updateStoreName(String storeName) async {
    await _persist(DeviceIdentity(
      storeUuid: state.storeUuid,
      storeKey: state.storeKey,
      storeName: storeName,
      deviceName: state.deviceName,
      deviceCode: state.deviceCode,
      deviceRole: state.deviceRole,
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
/// Kunci DB diturunkan dari store_key (256-bit acak), sehingga 10k iterasi
/// PBKDF2 sudah lebih dari cukup — menaikkan iterasi tidak menambah keamanan
/// untuk input ber-entropi tinggi, hanya memperlambat startup.
final databaseProvider = Provider<AppDatabase>((ref) {
  // HANYA bergantung pada storeKey (via select) — kalau me-watch seluruh
  // deviceProvider, perubahan identitas apa pun (mis. ganti nama toko di
  // Pengaturan) ikut me-rebuild provider ini: koneksi SQLCipher lama ditutup
  // di tengah sesi dan query/stream yang sedang berjalan bisa error.
  final storeKey =
      ref.watch(deviceProvider.select((device) => device.storeKey));
  if (storeKey == null) {
    throw StateError('Database diakses sebelum setup selesai');
  }
  final db = AppDatabase.open(deriveDatabaseKey(storeKey));
  ref.onDispose(db.close);
  return db;
});
