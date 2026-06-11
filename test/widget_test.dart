import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/services/crypto_service.dart';
import 'package:the_pos/core/services/pairing_service.dart';

void main() {
  group('CryptoService', () {
    test('generateStoreKey menghasilkan 32 byte base64url', () {
      final key = CryptoService.generateStoreKey();
      expect(key.length, greaterThanOrEqualTo(43));
      expect(CryptoService.generateStoreKey(), isNot(equals(key)));
    });

    test('deriveDbKeyHex deterministik, 64 char hex', () {
      const storeKey = 'dGVzdC1zdG9yZS1rZXktMzItYnl0ZXMtcGFkZGluZyE=';
      final a = CryptoService.deriveDbKeyHex(storeKey);
      final b = CryptoService.deriveDbKeyHex(storeKey);
      expect(a, equals(b));
      expect(a.length, 64);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(a), isTrue);
    });

    test('encrypt/decrypt roundtrip', () {
      final key = CryptoService.deriveSyncKey('store-key', 'ABC123');
      const plain = '{"transactions":[{"id":"x","total":212000}]}';
      final cipher = CryptoService.encryptText(plain, key);
      expect(CryptoService.decryptText(cipher, key), equals(plain));
    });

    test('decrypt dengan key salah gagal', () {
      final key1 = CryptoService.deriveSyncKey('store-key', 'ABC123');
      final key2 = CryptoService.deriveSyncKey('store-key', 'XYZ789');
      final cipher = CryptoService.encryptText('rahasia', key1);
      expect(() => CryptoService.decryptText(cipher, key2),
          throwsA(anything));
    });
  });

  group('PairingService', () {
    test('generate -> encode -> validate roundtrip', () {
      final payload = PairingService.generate(
        storeUuid: 'uuid-1234',
        storeKey: 'key-base64',
        storeName: 'Berkah Grosir',
        role: 'kasir',
        deviceName: 'Kasir 1',
        deviceCode: 'K1',
      );
      final decoded = PairingService.validate(payload.encode());
      expect(decoded, isNotNull);
      expect(decoded!.storeUuid, 'uuid-1234');
      expect(decoded.role, 'kasir');
      expect(decoded.deviceCode, 'K1');
    });

    test('QR sampah ditolak', () {
      expect(PairingService.validate('bukan-qr-valid!!'), isNull);
    });

    test('payload expired ditolak', () {
      final expired = PairingPayload(
        storeUuid: 'u',
        storeKey: 'k',
        storeName: 's',
        role: 'kasir',
        deviceName: 'd',
        deviceCode: 'K1',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );
      expect(() => PairingService.validate(expired.encode()),
          throwsA(isA<PairingExpiredException>()));
    });

    test('role tidak valid ditolak', () {
      final bad = PairingPayload(
        storeUuid: 'u',
        storeKey: 'k',
        storeName: 's',
        role: 'owner', // owner tidak boleh di-pair via QR
        deviceName: 'd',
        deviceCode: 'O2',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      );
      expect(PairingService.validate(bad.encode()), isNull);
    });
  });
}
