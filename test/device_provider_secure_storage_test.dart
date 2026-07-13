import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/services/crash_log_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.externalPath);
  final String externalPath;

  @override
  Future<String?> getExternalStoragePath() async => externalPath;
}

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Diagnosis crash HP tertentu (mis. Infinix Smart 8): install sukses, tapi
/// force-close instan saat dibuka. Dugaan utama — `FlutterSecureStorage`
/// (Android Keystore) melempar exception saat `DeviceNotifier.load()` baca
/// `store_key`, dan TANPA try/catch itu menjatuhkan seluruh `main()`
/// SEBELUM `runApp()` sempat dipanggil (tidak ada layar error sama sekali,
/// persis gejala yang dilaporkan). Test ini membuktikan `load()` sekarang
/// TIDAK melempar walau baca secure storage gagal total.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pos_device_provider_');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  test(
      'load() TIDAK melempar walau FlutterSecureStorage.read() melempar '
      'exception (mis. Android Keystore rusak di HP tertentu)', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
      if (call.method == 'read') {
        throw PlatformException(
            code: 'Unexpected security exception',
            message: 'Android Keystore gagal (simulasi)');
      }
      return null;
    });

    final notifier = DeviceNotifier();
    // Sebelum fix ini, exception di atas akan lolos tak tertangkap sampai
    // ke pemanggil load() — persis skenario yang menjatuhkan main().
    await notifier.load();

    // App tetap hidup (tidak throw) — device dianggap belum terkonfigurasi
    // (storeKey null, tidak ada data lama di SharedPreferences) alih-alih
    // crash total.
    expect(notifier.state.isConfigured, isFalse);
  });

  test(
      'load() jatuh ke legacyKey di SharedPreferences kalau secure storage '
      'gagal TAPI ada data lama (device sudah pernah dipakai)', () async {
    SharedPreferences.setMockInitialValues({
      'store_uuid': 'u1',
      'store_key': 'kunci-lama-belum-migrasi',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
      if (call.method == 'read') {
        throw PlatformException(code: 'err', message: 'gagal baca');
      }
      return null;
    });

    final notifier = DeviceNotifier();
    await notifier.load();

    expect(notifier.state.storeKey, 'kunci-lama-belum-migrasi',
        reason: 'jangan sampai device yang sudah punya data jadi '
            'kehilangan akses gara-gara satu baca storage gagal');
  });

  test(
      'load() yang gagal baca secure storage tercatat ke CrashLogService '
      '(bisa dibaca via File Manager walau app force-close berikutnya)',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
      if (call.method == 'read') {
        throw PlatformException(code: 'err', message: 'gagal baca simulasi');
      }
      return null;
    });

    await DeviceNotifier().load();

    final log = await CrashLogService.readAll();
    expect(log, isNotNull);
    expect(log, contains('DeviceNotifier.load secureStorage'));
  });
}
