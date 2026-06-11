import 'dart:convert';

/// Payload QR pairing antar device. QR = base64url(json).
/// Hanya untuk setup awal, bukan transfer data — tidak dienkripsi,
/// tapi expired 5 menit.
class PairingPayload {
  const PairingPayload({
    required this.storeUuid,
    required this.storeKey,
    required this.storeName,
    required this.role,
    required this.deviceName,
    required this.deviceCode,
    required this.expiresAt,
  });

  final String storeUuid;
  final String storeKey;
  final String storeName;
  final String role; // kasir | asisten
  final String deviceName;
  final String deviceCode;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  String encode() => base64UrlEncode(utf8.encode(jsonEncode({
        'store_uuid': storeUuid,
        'store_key': storeKey,
        'store_name': storeName,
        'role': role,
        'device_name': deviceName,
        'device_code': deviceCode,
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
        deviceName: json['device_name'] as String,
        deviceCode: json['device_code'] as String,
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
    required String deviceName,
    required String deviceCode,
  }) {
    assert(validRoles.contains(role));
    return PairingPayload(
      storeUuid: storeUuid,
      storeKey: storeKey,
      storeName: storeName,
      role: role,
      deviceName: deviceName,
      deviceCode: deviceCode,
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
