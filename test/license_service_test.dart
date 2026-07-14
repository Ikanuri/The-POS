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
}
