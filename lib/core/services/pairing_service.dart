import 'dart:convert';

/// Payload QR pairing antar device. QR = base64url(json).
/// Hanya untuk setup awal, bukan transfer data — tidak dienkripsi,
/// tapi expired 5 menit.
///
/// PERINGATAN KEAMANAN (Item 41 B.1, risiko diterima sadar — belum ada
/// mitigasi): QR ini membawa `store_key` MASTER dalam bentuk polos. Siapa
/// pun yang sempat MEMOTRET layar QR mendapat kunci turunan database
/// SQLCipher & kunci sync SELAMANYA — expiry 5 menit hanya dicek di sisi
/// klien app (payload tidak ditandatangani), TIDAK menghapus nilai kunci
/// yang sudah terlanjur terlihat. Belum ada mekanisme un-pair / rotasi
/// storeKey utk mencabut device (HP kasir hilang, pegawai keluar) — fitur
/// "rotasi kunci toko" (rekey DB + re-pair semua device) masih rencana di
/// PLAN.md. Sampai itu ada: tampilkan QR hanya saat layar benar-benar
/// diawasi owner, dan anggap kunci bocor = harus Alihkan Owner ke
/// identitas toko baru.
class PairingPayload {
  const PairingPayload({
    required this.storeUuid,
    required this.storeKey,
    required this.storeName,
    required this.role,
    required this.expiresAt,
  });

  final String storeUuid;
  final String storeKey;
  final String storeName;
  final String role; // kasir | asisten
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  // Catatan: payload TIDAK membawa nama/kode device. Identitas perangkat
  // (prefix nomor nota + penanda kasir) diisi sendiri oleh perangkat yang
  // bergabung, agar tiap device punya kode unik dan nomor nota tidak bentrok.
  String encode() => base64UrlEncode(utf8.encode(jsonEncode({
        'store_uuid': storeUuid,
        'store_key': storeKey,
        'store_name': storeName,
        'role': role,
        'expires_at': expiresAt.toIso8601String(),
      })));

  static PairingPayload? decode(String qrData) {
    try {
      final json =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(qrData))))
              as Map<String, dynamic>;
      return PairingPayload(
        storeUuid: json['store_uuid'] as String,
        storeKey: json['store_key'] as String,
        storeName: json['store_name'] as String? ?? '',
        role: json['role'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}

class PairingService {
  PairingService._();

  static const validRoles = {'kasir', 'asisten'};
  static const ttl = Duration(minutes: 5);

  static PairingPayload generate({
    required String storeUuid,
    required String storeKey,
    required String storeName,
    required String role,
  }) {
    assert(validRoles.contains(role));
    return PairingPayload(
      storeUuid: storeUuid,
      storeKey: storeKey,
      storeName: storeName,
      role: role,
      expiresAt: DateTime.now().toUtc().add(ttl),
    );
  }

  /// null = QR tidak valid; throw [PairingExpiredException] jika expired.
  static PairingPayload? validate(String qrData) {
    final payload = PairingPayload.decode(qrData);
    if (payload == null) return null;
    if (!validRoles.contains(payload.role)) return null;
    if (payload.isExpired) throw PairingExpiredException();
    return payload;
  }
}

class PairingExpiredException implements Exception {
  @override
  String toString() => 'QR pairing sudah kedaluwarsa. Minta owner generate ulang.';
}
