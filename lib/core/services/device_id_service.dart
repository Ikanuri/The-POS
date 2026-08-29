import 'package:flutter/services.dart';

/// Susulan Item 25c (binding device fisik) — baca `Settings.Secure.
/// ANDROID_ID` via channel native (`MainActivity.kt`, method `getAndroidId`).
///
/// ANDROID_ID unik per (device fisik + signing key app) dan TIDAK ikut
/// ter-copy walau folder data privat aplikasi (termasuk SharedPreferences,
/// tempat fingerprint & status lisensi tersimpan) disalin ke device fisik
/// lain lewat tools "Pindah Data"/clone bawaan pabrikan (Xiaomi/Oppo/
/// Samsung dkk) — beda dari fingerprint acak (`LicenseService.
/// generateFingerprint`) yang MEMANG ikut ter-copy krn cuma tersimpan di
/// SharedPreferences biasa. Dipakai `LicenseNotifier._checkDeviceBinding`
/// utk mendeteksi kalau lisensi yang sama tiba-tiba jalan di device fisik
/// yang berbeda dari yang pertama merekamnya.
class DeviceIdService {
  DeviceIdService._();

  static const _channel = MethodChannel('com.thepos/device_id');

  /// Null kalau gagal (bukan Android, error platform channel, versi app
  /// lama sebelum native channel ini ada, dll) — caller WAJIB fail-open
  /// (jangan pernah mengunci krn ketidaktahuan).
  static Future<String?> getAndroidId() async {
    try {
      final id = await _channel.invokeMethod<String>('getAndroidId');
      return (id == null || id.isEmpty) ? null : id;
    } catch (_) {
      return null;
    }
  }
}
