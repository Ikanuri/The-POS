import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Item 25c — Gerbang aktivasi/lisensi offline. Lapis 1 (murni logika,
/// tanpa I/O) — persistensi & state ada di `license_provider.dart`.
///
/// Format kode aktivasi: `<payload base64url>.<tanda tangan base64url>`,
/// mirip token JWT yang disederhanakan. Payload = JSON `{"fp":"...",
/// "exp":"..."}` (fp = sidik jari device tujuan, exp = ISO8601 UTC atau
/// literal "selamanya"). Ditandatangani Ed25519 oleh alat generator offline
/// developer (`tools/license-generator.html`, TIDAK memakai private key
/// ini) — di sini HANYA verifikasi pakai public key.
class LicensePayload {
  const LicensePayload({required this.fingerprint, required this.exp});

  final String fingerprint;
  final String exp; // ISO8601 UTC, atau literal 'selamanya'.

  factory LicensePayload.fromJsonString(String s) {
    final map = jsonDecode(s) as Map<String, dynamic>;
    return LicensePayload(
      fingerprint: map['fp'] as String,
      exp: map['exp'] as String,
    );
  }
}

class LicenseVerifyResult {
  const LicenseVerifyResult.ok(this.payload) : error = null;
  const LicenseVerifyResult.fail(this.error) : payload = null;

  final LicensePayload? payload;
  final String? error;
  bool get isOk => payload != null;
}

class LicenseService {
  LicenseService._();

  /// Public key milik developer (Ed25519, 32 byte, Base64 standar).
  /// KOSONG berarti gerbang lisensi BELUM dikonfigurasi — [isConfigured]
  /// jadi false, dan seluruh gerbang HARUS dianggap nonaktif (tidak pernah
  /// mengunci siapa pun) sampai key sungguhan ditanam di sini. Isi dari
  /// public key yang ditampilkan `tools/license-generator.html` setelah
  /// developer generate pasangan kunci sendiri secara offline.
  static const publicKeyBase64 = 'a3KO8cpEAOOq+YoJPWQ++Pxkw+eWWVnSa02rYah22rY=';

  static bool get isConfigured => publicKeyBase64.isNotEmpty;

  static const _fingerprintBytes = 16;

  /// Sidik jari device baru: 16 byte acak (128-bit), TIDAK dari
  /// IMEI/identitas hardware (tidak bisa dibaca app biasa sejak Android 10,
  /// tidak pernah bisa di iOS). Heksadesimal — hindari Base32/64 supaya
  /// tidak ada karakter mirip-mirip kalau sesekali harus diketik manual.
  static String generateFingerprint() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(_fingerprintBytes, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Tampilan berkelompok utk layar aktivasi, mis. `9F3A-1B22-...`.
  static String formatFingerprint(String hex) {
    final groups = <String>[];
    for (var i = 0; i < hex.length; i += 4) {
      groups.add(hex.substring(i, min(i + 4, hex.length)));
    }
    return groups.join('-').toUpperCase();
  }

  static String _padBase64Url(String s) {
    final mod = s.length % 4;
    if (mod == 0) return s;
    return s + '=' * (4 - mod);
  }

  /// Verifikasi kode aktivasi. [publicKeyB64] & [deviceFingerprint] eksplisit
  /// sbg parameter (bukan langsung baca [publicKeyBase64]/device asli) —
  /// supaya testable dgn pasangan kunci palsu tanpa menyentuh key produksi.
  static Future<LicenseVerifyResult> verify(
    String code, {
    required String publicKeyB64,
    required String deviceFingerprint,
  }) async {
    final parts = code.trim().split('.');
    if (parts.length != 2) return const LicenseVerifyResult.fail('format');

    final List<int> payloadBytes;
    final List<int> sigBytes;
    try {
      payloadBytes = base64Url.decode(_padBase64Url(parts[0]));
      sigBytes = base64Url.decode(_padBase64Url(parts[1]));
    } catch (_) {
      return const LicenseVerifyResult.fail('decode');
    }

    try {
      final pubKeyBytes = base64.decode(publicKeyB64);
      final publicKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);
      final signature = Signature(sigBytes, publicKey: publicKey);
      final valid = await Ed25519().verify(payloadBytes, signature: signature);
      if (!valid) return const LicenseVerifyResult.fail('signature');
    } catch (_) {
      return const LicenseVerifyResult.fail('signature');
    }

    final LicensePayload payload;
    try {
      payload = LicensePayload.fromJsonString(utf8.decode(payloadBytes));
    } catch (_) {
      return const LicenseVerifyResult.fail('payload');
    }

    if (payload.fingerprint.toLowerCase() != deviceFingerprint.toLowerCase()) {
      return const LicenseVerifyResult.fail('fingerprint');
    }

    return LicenseVerifyResult.ok(payload);
  }
}
