import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/providers/license_provider.dart';

/// Item 14 — user minta sisa waktu lisensi ditampilkan di Pengaturan,
/// "menyesuaikan sisa waktu" (auto-scale unit: hari → jam → menit, satuan
/// terkecil menit — BUKAN selalu tampil dalam menit mentah).
void main() {
  LicenseState stateWithExp(DateTime exp) => LicenseState(
        fingerprint: 'fp',
        exp: exp.toIso8601String(),
      );

  test('sisa > 1 hari → ditampilkan dalam satuan HARI', () {
    final state = stateWithExp(
        DateTime.now().add(const Duration(days: 5, seconds: 10)));
    expect(state.remainingLabel, '5 hari lagi');
  });

  test('sisa < 1 hari tapi > 1 jam → ditampilkan dalam satuan JAM', () {
    final state = stateWithExp(
        DateTime.now().add(const Duration(hours: 3, seconds: 10)));
    expect(state.remainingLabel, '3 jam lagi');
  });

  test('sisa < 1 jam → ditampilkan dalam satuan MENIT (satuan terkecil)', () {
    final state = stateWithExp(
        DateTime.now().add(const Duration(minutes: 20, seconds: 10)));
    expect(state.remainingLabel, '20 menit lagi');
  });

  test('sudah lewat exp → "Kadaluarsa"', () {
    final state =
        stateWithExp(DateTime.now().subtract(const Duration(minutes: 5)));
    expect(state.remainingLabel, 'Kadaluarsa');
  });

  test('exp "selamanya" → remainingLabel null, licenseStatusLabel "Selamanya"',
      () {
    const state = LicenseState(fingerprint: 'fp', exp: 'selamanya');
    expect(state.remainingLabel, isNull);
    expect(state.licenseStatusLabel, 'Selamanya');
  });

  test('belum aktivasi (exp null) → licenseStatusLabel null (tidak tampil)',
      () {
    const state = LicenseState(fingerprint: 'fp');
    expect(state.licenseStatusLabel, isNull);
  });
}
