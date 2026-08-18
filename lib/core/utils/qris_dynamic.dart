/// Injeksi nominal ke payload QRIS statis -> "QRIS nominal terkunci"
/// (format EMVCo Merchant Presented Mode / QRIS).
///
/// **EKSPERIMENTAL** (Item 62 susulan). Payload hasil fungsi ini TIDAK
/// melalui server acquirer (GoPay/OVO/dst) — beda dari QRIS dinamis
/// resmi yang dibuat lewat aplikasi merchant, hasil di sini TIDAK
/// mendapat masa berlaku/pembatasan 1x-transaksi yang ditegakkan
/// server, dan aplikasi TIDAK bisa tahu otomatis kapan pelanggan sudah
/// bayar (tetap perlu konfirmasi manual, sama seperti alur checkout
/// yang sudah ada).
///
/// Tervalidasi terhadap 3 payload GoPay ASLI (1 statis + 2 dinamis,
/// toko nyata) sebelum fitur ini ditambahkan — lihat
/// `test/qris_dynamic_test.dart`. Perbedaan statis->dinamis persis 3
/// tag: `01` (`11`->`12`), `54` (nominal, disisipkan tepat setelah tag
/// `53`), `63` (CRC dihitung ulang). Field proprietary GoPay (tag `62`
/// sub-tag `50` — token+timestamp sisi server mereka) SENGAJA tidak
/// direplikasi — di luar spek EMVCo standar (rentang sub-tag `50-99`
/// memang reserved utk vendor), tidak memengaruhi keabsahan CRC/payload.
library;

/// Payload bukan QRIS/EMVCo TLV yang valid (rusak, terpotong, atau tidak
/// punya tag mata uang) — dilempar oleh [injectQrisAmount].
class QrisTlvException implements Exception {
  QrisTlvException(this.message);
  final String message;
  @override
  String toString() => 'QrisTlvException: $message';
}

/// CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) — algoritma resmi tag 63
/// EMVCo QR Code. Check value baku `crc16CcittFalse('123456789') == '29B1'`
/// (diverifikasi di test).
String crc16CcittFalse(String data) {
  var crc = 0xFFFF;
  for (final byte in data.codeUnits) {
    crc ^= byte << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0
          ? ((crc << 1) ^ 0x1021) & 0xFFFF
          : (crc << 1) & 0xFFFF;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}

/// Pecah payload jadi list tag-value berurutan (format tag(2)+len(2)+value).
/// Throws [QrisTlvException] kalau strukturnya malformed.
List<MapEntry<String, String>> parseQrisTlv(String payload) {
  final out = <MapEntry<String, String>>[];
  var i = 0;
  while (i < payload.length) {
    if (i + 4 > payload.length) {
      throw QrisTlvException('payload terpotong di posisi $i');
    }
    final tag = payload.substring(i, i + 2);
    final len = int.tryParse(payload.substring(i + 2, i + 4));
    if (len == null) {
      throw QrisTlvException('panjang bukan angka di tag $tag');
    }
    if (i + 4 + len > payload.length) {
      throw QrisTlvException('nilai tag $tag kurang panjang dari klaim');
    }
    out.add(MapEntry(tag, payload.substring(i + 4, i + 4 + len)));
    i += 4 + len;
  }
  return out;
}

String _buildQrisTlv(List<MapEntry<String, String>> fields) {
  final buf = StringBuffer();
  for (final f in fields) {
    buf
      ..write(f.key)
      ..write(f.value.length.toString().padLeft(2, '0'))
      ..write(f.value);
  }
  return buf.toString();
}

/// true bila CRC (tag 63) yang tertempel di [payload] cocok dgn hasil
/// hitung ulang — dipakai sbg guard sebelum payload dipercaya.
bool verifyQrisCrc(String payload) {
  if (payload.length < 8) return false;
  if (payload.substring(payload.length - 8, payload.length - 4) != '6304') {
    return false;
  }
  final body = payload.substring(0, payload.length - 4);
  final crc = payload.substring(payload.length - 4);
  return crc16CcittFalse(body).toUpperCase() == crc.toUpperCase();
}

/// Sisipkan nominal [amountRupiah] ke payload QRIS statis [staticPayload]:
/// ganti tag metode inisiasi (`01`) statis(`11`)->dinamis(`12`), sisipkan
/// tag `54` (nominal) tepat setelah tag `53` (mata uang), lalu hitung
/// ulang CRC (`63`). Throws [QrisTlvException] bila payload bukan
/// QRIS/EMVCo valid (mis. tag `53` tidak ada).
String injectQrisAmount(String staticPayload, int amountRupiah) {
  final fields = parseQrisTlv(staticPayload.trim());

  final out = <MapEntry<String, String>>[];
  for (final f in fields) {
    if (f.key == '63' || f.key == '54') continue; // dibuang, diisi ulang
    out.add(f.key == '01' ? const MapEntry('01', '12') : f);
    if (f.key == '53') {
      out.add(MapEntry('54', amountRupiah.toString()));
    }
  }
  if (!out.any((f) => f.key == '54')) {
    throw QrisTlvException(
        'tag 53 (mata uang) tidak ditemukan — bukan payload QRIS valid');
  }

  final body = '${_buildQrisTlv(out)}6304';
  return '$body${crc16CcittFalse(body)}';
}
