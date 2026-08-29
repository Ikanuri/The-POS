import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/providers/license_provider.dart';

/// Integrasi `LicenseNotifier.load()` × binding ANDROID_ID (susulan Item
/// 25c) — beda dari `license_service_test.dart` yang cuma menguji fungsi
/// murni `computeDeviceMismatch` di luar konteks I/O, di sini kita buktikan
/// `_checkDeviceBinding` (private, dipanggil dari `load()`) BENAR
/// menyimpan/membaca SharedPreferences & memanggil platform channel
/// `com.thepos/device_id` sesuai skenario.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.thepos/device_id');

  void mockAndroidId(String? id) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAndroidId') return id;
      return null;
    });
  }

  void mockAndroidIdThrows() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'UNAVAILABLE');
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
      'fresh install (belum ada baseline ANDROID_ID tersimpan) → device '
      'SEKARANG direkam sbg baseline, BUKAN mismatch', () async {
    SharedPreferences.setMockInitialValues({});
    mockAndroidId('device-A');

    final notifier = LicenseNotifier();
    await notifier.load();

    expect(notifier.state.deviceMismatch, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('license_android_id'), 'device-A',
        reason: 'baseline device pertama HARUS direkam supaya load() '
            'berikutnya punya acuan pembanding');
  });

  test(
      'ANDROID_ID sekarang SAMA dgn baseline tersimpan (device normal, '
      'bukan hasil clone) → tidak mismatch', () async {
    SharedPreferences.setMockInitialValues({'license_android_id': 'device-A'});
    mockAndroidId('device-A');

    final notifier = LicenseNotifier();
    await notifier.load();

    expect(notifier.state.deviceMismatch, isFalse);
  });

  test(
      'ANDROID_ID sekarang BEDA dari baseline tersimpan → mismatch '
      '(indikasi data lisensi dipindah ke device fisik lain, mis. tools '
      'clone/pindah-data OEM)', () async {
    SharedPreferences.setMockInitialValues({'license_android_id': 'device-A'});
    mockAndroidId('device-B');

    final notifier = LicenseNotifier();
    await notifier.load();

    expect(notifier.state.deviceMismatch, isTrue);
    expect(notifier.state.isLocked, isTrue,
        reason: 'mismatch harus benar-benar menutup gerbang lewat isLocked, '
            'bukan cuma tersimpan tanpa efek');
  });

  test(
      'platform channel gagal (mis. iOS / error) → fail-open, TIDAK PERNAH '
      'mismatch walau ada baseline berbeda tersimpan', () async {
    SharedPreferences.setMockInitialValues({'license_android_id': 'device-A'});
    mockAndroidIdThrows();

    final notifier = LicenseNotifier();
    await notifier.load();

    expect(notifier.state.deviceMismatch, isFalse);
  });

  group(
      'LicenseNotifier.rebindDeviceId — bug produksi ditemukan user (real '
      'device): reaktivasi valid dulu TIDAK PERNAH membersihkan '
      'deviceMismatch, device jujur bisa terkunci PERMANEN', () {
    test(
        'device SUDAH ter-flag mismatch, tapi reaktivasi (disimulasikan via '
        'rebindDeviceId) berhasil baca ANDROID_ID sekarang → baseline '
        'ditimpa & deviceMismatch dibersihkan', () async {
      SharedPreferences.setMockInitialValues(
          {'license_android_id': 'device-lama-palsu'});
      mockAndroidId('device-real-sekarang');

      final notifier = LicenseNotifier();
      await notifier.load(); // deviceMismatch jadi true (baseline beda)
      expect(notifier.state.deviceMismatch, isTrue,
          reason: 'prasyarat skenario: device HARUS sudah terkunci dulu');

      final prefs = await SharedPreferences.getInstance();
      final newMismatch = await notifier.rebindDeviceId(prefs);

      expect(newMismatch, isFalse,
          reason: 'ini yang dulu TIDAK terjadi — reaktivasi valid harus '
              'membuka gerbang lagi, bukan terkunci selamanya');
      expect(prefs.getString('license_android_id'), 'device-real-sekarang',
          reason: 'baseline direkam ulang ke device yang SEDANG dipakai');
    });

    test(
        'ANDROID_ID gagal terbaca saat rebind (mis. error channel) → '
        'fail-open, pertahankan status deviceMismatch LAMA apa adanya '
        '(tidak diam-diam disimpulkan aman)', () async {
      SharedPreferences.setMockInitialValues(
          {'license_android_id': 'device-lama-palsu'});
      mockAndroidId('device-real-sekarang');
      final notifier = LicenseNotifier();
      await notifier.load();
      expect(notifier.state.deviceMismatch, isTrue);

      mockAndroidIdThrows(); // channel tiba2 error pas rebind dipanggil
      final prefs = await SharedPreferences.getInstance();
      final newMismatch = await notifier.rebindDeviceId(prefs);

      expect(newMismatch, isTrue,
          reason: 'gagal baca -> pertahankan status lama (masih true), '
              'BUKAN diasumsikan false begitu saja');
    });
  });
}
