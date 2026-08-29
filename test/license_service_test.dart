import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/providers/license_provider.dart';
import 'package:the_pos/core/services/license_service.dart';

const _fp = '9f3a1b2277ce804aa1f09c3e5b7d2e41';

String _b64Url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Bangun kode aktivasi asli (self-signed dgn pasangan kunci sekali-pakai) —
/// meniru persis wire format yang dipakai `tools/license-generator.html`,
/// supaya test ini murni menguji `LicenseService.verify` tanpa bergantung
/// pada alat HTML-nya (yang sudah diverifikasi interop-nya secara manual
/// terhadap JS Web Crypto API saat implementasi).
Future<({String code, String pubKeyB64})> _buildCode({
  required String fingerprint,
  required String exp,
}) async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final pubKey = await keyPair.extractPublicKey();
  final pubKeyB64 = base64.encode(pubKey.bytes);

  final payloadStr = '{"fp":"$fingerprint","exp":"$exp"}';
  final payloadBytes = utf8.encode(payloadStr);
  final signature = await algorithm.sign(payloadBytes, keyPair: keyPair);
  final code = '${_b64Url(payloadBytes)}.${_b64Url(signature.bytes)}';
  return (code: code, pubKeyB64: pubKeyB64);
}

void main() {
  group('LicenseService.verify', () {
    test('kode valid diterima & payload sesuai', () async {
      final built =
          await _buildCode(fingerprint: _fp, exp: '2099-01-01T00:00:00Z');
      final result = await LicenseService.verify(built.code,
          publicKeyB64: built.pubKeyB64, deviceFingerprint: _fp);
      expect(result.isOk, isTrue);
      expect(result.payload!.fingerprint, _fp);
      expect(result.payload!.exp, '2099-01-01T00:00:00Z');
    });

    test('payload yang diubah SETELAH ditandatangani ditolak', () async {
      final built = await _buildCode(fingerprint: _fp, exp: 'selamanya');
      final parts = built.code.split('.');
      final flipped = parts[0][5] == 'A' ? 'B' : 'A';
      final tamperedPayload =
          parts[0].substring(0, 5) + flipped + parts[0].substring(6);
      final tampered = '$tamperedPayload.${parts[1]}';
      expect(tampered, isNot(built.code));

      final result = await LicenseService.verify(tampered,
          publicKeyB64: built.pubKeyB64, deviceFingerprint: _fp);
      expect(result.isOk, isFalse);
      expect(result.error, 'signature');
    });

    test('kode utk device lain ditolak walau tanda tangan valid', () async {
      final built = await _buildCode(fingerprint: _fp, exp: 'selamanya');
      final result = await LicenseService.verify(built.code,
          publicKeyB64: built.pubKeyB64,
          deviceFingerprint: 'ffffffffffffffffffffffffffffffff');
      expect(result.isOk, isFalse);
      expect(result.error, 'fingerprint');
    });

    test('public key yang salah ditolak', () async {
      final built = await _buildCode(fingerprint: _fp, exp: 'selamanya');
      final other = await Ed25519().newKeyPair();
      final wrongPub = base64.encode((await other.extractPublicKey()).bytes);
      final result = await LicenseService.verify(built.code,
          publicKeyB64: wrongPub, deviceFingerprint: _fp);
      expect(result.isOk, isFalse);
      expect(result.error, 'signature');
    });

    test('format tanpa titik pemisah ditolak', () async {
      final result = await LicenseService.verify('bukan-kode-valid',
          publicKeyB64: 'AAAA', deviceFingerprint: _fp);
      expect(result.isOk, isFalse);
      expect(result.error, 'format');
    });

    test('base64 rusak ditolak dgn rapi (tidak throw)', () async {
      final result = await LicenseService.verify('!!!.!!!',
          publicKeyB64: 'AAAA', deviceFingerprint: _fp);
      expect(result.isOk, isFalse);
      expect(result.error, 'decode');
    });
  });

  group('LicenseService.generateFingerprint / formatFingerprint', () {
    test('generateFingerprint() 32 karakter heksadesimal lowercase', () {
      final fp1 = LicenseService.generateFingerprint();
      expect(fp1.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(fp1), isTrue);
    });

    test('formatFingerprint() kelompok 4 karakter dipisah dash', () {
      expect(
        LicenseService.formatFingerprint(_fp),
        '9F3A-1B22-77CE-804A-A1F0-9C3E-5B7D-2E41',
      );
    });
  });

  group('LicenseState — kill-switch & ratchet (logika murni)', () {
    // Gerbang SUDAH aktif (public key developer sudah ditanam) — grup ini
    // sekarang membuktikan properti sebaliknya dari sebelumnya: begitu
    // dikonfigurasi, `isLocked` benar-benar menegakkan tiap syarat (belum
    // aktivasi/expired/revoked/jam mundur), BUKAN selalu false lagi.
    test('isConfigured true — public key developer sudah ditanam', () {
      expect(LicenseService.isConfigured, isTrue,
          reason: 'gerbang lisensi sudah diaktifkan sengaja oleh developer, '
              'lihat LicenseService.publicKeyBase64');
    });

    test('isLocked true kalau BELUM pernah aktivasi', () {
      const belumAktivasi = LicenseState(fingerprint: _fp);
      expect(belumAktivasi.isLocked, isTrue);
    });

    test('isLocked true kalau sudah aktivasi TAPI tanggal exp sudah lewat',
        () {
      final expired = LicenseState(
        fingerprint: _fp,
        exp: '2000-01-01T00:00:00Z',
        lastSeen: DateTime(2000, 1, 2),
      );
      expect(expired.isLocked, isTrue);
    });

    test('isLocked true kalau fingerprint masuk daftar revoked', () {
      const revoked =
          LicenseState(fingerprint: _fp, exp: 'selamanya', revoked: true);
      expect(revoked.isLocked, isTrue);
    });

    test(
        'isLocked false kalau sudah aktivasi valid, belum expired, tidak '
        'revoked, jam tidak dimundurkan', () {
      final aktif = LicenseState(
        fingerprint: _fp,
        exp: 'selamanya',
        lastSeen: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(aktif.isLocked, isFalse);
    });

    test('isExpired true kalau tanggal exp sudah lewat', () {
      const s = LicenseState(fingerprint: _fp, exp: '2000-01-01T00:00:00Z');
      expect(s.isExpired, isTrue);
    });

    test('isExpired false utk exp "selamanya"', () {
      const s = LicenseState(fingerprint: _fp, exp: 'selamanya');
      expect(s.isExpired, isFalse);
    });

    test('isExpired false kalau exp masih jauh di depan', () {
      const s = LicenseState(fingerprint: _fp, exp: '2099-01-01T00:00:00Z');
      expect(s.isExpired, isFalse);
    });

    test('isClockRewound true kalau sekarang < waktu terakhir tersimpan', () {
      final s = LicenseState(
        fingerprint: _fp,
        exp: 'selamanya',
        lastSeen: DateTime.now().add(const Duration(days: 1)),
      );
      expect(s.isClockRewound, isTrue);
    });

    test('isClockRewound false utk waktu terakhir yang wajar (di masa lalu)',
        () {
      final s = LicenseState(
        fingerprint: _fp,
        exp: 'selamanya',
        lastSeen: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(s.isClockRewound, isFalse);
    });

    test('daysUntilExpiry menghitung sisa hari, null utk "selamanya"', () {
      final s = LicenseState(
        fingerprint: _fp,
        exp: DateTime.now().add(const Duration(days: 5)).toIso8601String(),
      );
      expect(s.daysUntilExpiry, anyOf(4, 5));

      const forever = LicenseState(fingerprint: _fp, exp: 'selamanya');
      expect(forever.daysUntilExpiry, isNull);
    });
  });

  group('LicenseNotifier.computeRevoked — sakelar darurat "lockAll" (Lapis 3)',
      () {
    test('lockAll false & fingerprint TIDAK di daftar → tidak revoked', () {
      expect(
        LicenseNotifier.computeRevoked(
            lockAll: false, dicabut: const [], fingerprint: _fp),
        isFalse,
      );
    });

    test('lockAll false & fingerprint ADA di daftar → revoked', () {
      expect(
        LicenseNotifier.computeRevoked(
            lockAll: false, dicabut: [_fp], fingerprint: _fp),
        isTrue,
      );
    });

    test(
        'lockAll TRUE → SEMUA device revoked, walau fingerprint TIDAK ada '
        'di daftar `dicabut` sama sekali (skenario darurat)', () {
      expect(
        LicenseNotifier.computeRevoked(
            lockAll: true, dicabut: const [], fingerprint: _fp),
        isTrue,
      );
    });

    test('perbandingan fingerprint tidak case-sensitive', () {
      expect(
        LicenseNotifier.computeRevoked(
            lockAll: false,
            dicabut: [_fp.toUpperCase()],
            fingerprint: _fp),
        isTrue,
      );
    });
  });

  group('LicenseNotifier.shouldBlockReactivation — fix susulan: device '
      'revoked tidak boleh "membuka diri sendiri" via kode yang sama', () {
    test(
        'fetch live BERHASIL & fingerprint MASIH revoked → blokir, walau '
        'cache lama bilang tidak revoked', () {
      expect(
        LicenseNotifier.shouldBlockReactivation(
            liveRevoked: true, cachedRevoked: false),
        isTrue,
      );
    });

    test('fetch live BERHASIL & fingerprint SUDAH TIDAK revoked → boleh',
        () {
      expect(
        LicenseNotifier.shouldBlockReactivation(
            liveRevoked: false, cachedRevoked: true),
        isFalse,
        reason: 'live check menang atas cache lama begitu bisa dikonfirmasi',
      );
    });

    test(
        'fetch GAGAL (null, offline) & cache SUDAH revoked → tetap blokir '
        '(fail-safe, TIDAK boleh diam-diam membuka gerbang)', () {
      expect(
        LicenseNotifier.shouldBlockReactivation(
            liveRevoked: null, cachedRevoked: true),
        isTrue,
      );
    });

    test(
        'fetch GAGAL (null, offline) & cache belum pernah revoked → boleh '
        '(tidak menghalangi aktivasi pertama kali yang genuinely offline)',
        () {
      expect(
        LicenseNotifier.shouldBlockReactivation(
            liveRevoked: null, cachedRevoked: false),
        isFalse,
      );
    });
  });

  group('LicenseNotifier.computeClockManipulated — deteksi jam device '
      'dimundurkan SEKALI sebelum riwayat ada (celah `isClockRewound` tak '
      'terjangkau)', () {
    test('device jauh di BELAKANG jam server (>24 jam) → dimanipulasi', () {
      final deviceNow = DateTime.utc(2020, 1, 1);
      const dateHeader = 'Sat, 29 Aug 2026 08:00:00 GMT';
      expect(
        LicenseNotifier.computeClockManipulated(
            dateHeaderValue: dateHeader, deviceTimeUtc: deviceNow),
        isTrue,
        reason: 'device thn 2020 vs server 2026 — jelas dimundurkan',
      );
    });

    test('device sedikit meleset (di bawah toleransi 24 jam) → BUKAN '
        'manipulasi (jam belum sempat NTP sync dianggap wajar)', () {
      final deviceNow = DateTime.utc(2026, 8, 29, 7, 0, 0);
      const dateHeader = 'Sat, 29 Aug 2026 08:00:00 GMT'; // beda 1 jam
      expect(
        LicenseNotifier.computeClockManipulated(
            dateHeaderValue: dateHeader, deviceTimeUtc: deviceNow),
        isFalse,
      );
    });

    test('device LEBIH MAJU dari server → BUKAN manipulasi (tidak membantu '
        'bypass expiry, bukan vektor yg relevan)', () {
      final deviceNow = DateTime.utc(2030, 1, 1);
      const dateHeader = 'Sat, 29 Aug 2026 08:00:00 GMT';
      expect(
        LicenseNotifier.computeClockManipulated(
            dateHeaderValue: dateHeader, deviceTimeUtc: deviceNow),
        isFalse,
      );
    });

    test('header `Date` null (mis. server tidak kirim) → null, fail-open',
        () {
      expect(
        LicenseNotifier.computeClockManipulated(
            dateHeaderValue: null, deviceTimeUtc: DateTime.now().toUtc()),
        isNull,
      );
    });

    test('header `Date` format tidak bisa diparse → null, fail-open', () {
      expect(
        LicenseNotifier.computeClockManipulated(
            dateHeaderValue: 'bukan-tanggal-valid',
            deviceTimeUtc: DateTime.now().toUtc()),
        isNull,
      );
    });
  });

  group('LicenseNotifier.computeDeviceMismatch — deteksi data lisensi '
      'dipindah ke device fisik lain (mis. tools clone/pindah-data OEM)',
      () {
    test('ANDROID_ID sekarang SAMA dgn yang tercatat → tidak mismatch', () {
      expect(
        LicenseNotifier.computeDeviceMismatch(
            storedAndroidId: 'abc123', currentAndroidId: 'abc123'),
        isFalse,
      );
    });

    test('ANDROID_ID sekarang BEDA dari yang tercatat → mismatch', () {
      expect(
        LicenseNotifier.computeDeviceMismatch(
            storedAndroidId: 'abc123', currentAndroidId: 'xyz789'),
        isTrue,
      );
    });

    test('belum ada baseline tersimpan (null) → BUKAN mismatch (baseline '
        'baru direkam terpisah oleh caller, bukan tugas fungsi murni ini)',
        () {
      expect(
        LicenseNotifier.computeDeviceMismatch(
            storedAndroidId: null, currentAndroidId: 'xyz789'),
        isFalse,
      );
    });

    test('ANDROID_ID sekarang tak terbaca (null, mis. iOS/error channel) → '
        'fail-open, BUKAN mismatch', () {
      expect(
        LicenseNotifier.computeDeviceMismatch(
            storedAndroidId: 'abc123', currentAndroidId: null),
        isFalse,
      );
    });
  });

  group('LicenseState.isLocked — 2 kondisi kunci baru ikut menutup gerbang',
      () {
    test('clockManipulated true (nota lain sudah lunas/normal) → terkunci',
        () {
      const s = LicenseState(
          fingerprint: _fp, exp: 'selamanya', clockManipulated: true);
      expect(s.isLocked, isTrue);
    });

    test('deviceMismatch true → terkunci', () {
      const s = LicenseState(
          fingerprint: _fp, exp: 'selamanya', deviceMismatch: true);
      expect(s.isLocked, isTrue);
    });

    test('semua flag baru false & lisensi selamanya valid → TIDAK terkunci',
        () {
      const s = LicenseState(
        fingerprint: _fp,
        exp: 'selamanya',
        clockManipulated: false,
        deviceMismatch: false,
      );
      expect(s.isLocked, isFalse);
    });
  });
}
