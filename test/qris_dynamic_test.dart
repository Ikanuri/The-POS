import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/utils/qris_dynamic.dart';

/// Item 62 susulan — injeksi nominal ke QRIS statis (fitur EKSPERIMENTAL,
/// lihat dok library `qris_dynamic.dart`). Fixture di sini adalah payload
/// GoPay ASLI dari toko nyata (dikirim user langsung dari HP-nya: 1
/// statis, 2 dinamis Rp 17.000 & Rp 20.000) — bukan data sintetis.
void main() {
  const static = '00020101021126610014COM.GO-JEK.WWW01189360091434648855360'
      '210G4648855360303UMI51440014ID.CO.QRIS.WWW0215ID102657224253903'
      '03UMI5204549953033605802ID5920Toko Berkah, BNY NYR6011PROBOLIN'
      'GGO61056727562070703A0163043165';
  const dynamic17k =
      '00020101021226610014COM.GO-JEK.WWW01189360091434648855360210G4'
      '648855360303UMI51440014ID.CO.QRIS.WWW0215ID102657224253903'
      '03UMI5204549953033605405170005802ID5920Toko Berkah, BNY NYR'
      '6011PROBOLINGGO61056727562395028A120260818025055rNt8gS9Lx9ID'
      '0703A016304174B';
  const dynamic20k =
      '00020101021226610014COM.GO-JEK.WWW01189360091434648855360210G4'
      '648855360303UMI51440014ID.CO.QRIS.WWW0215ID102657224253903'
      '03UMI5204549953033605405200005802ID5920Toko Berkah, BNY NYR'
      '6011PROBOLINGGO61056727562395028A120260818025109DUwv5q4b8ZID'
      '0703A0163042969';

  test('crc16CcittFalse cocok dgn check value baku ("123456789" -> 29B1)',
      () {
    expect(crc16CcittFalse('123456789'), '29B1');
  });

  test('CRC ketiga payload ASLI (statis + 2 dinamis) valid saat dihitung ulang',
      () {
    expect(verifyQrisCrc(static), isTrue);
    expect(verifyQrisCrc(dynamic17k), isTrue);
    expect(verifyQrisCrc(dynamic20k), isTrue);
  });

  test(
      'injectQrisAmount(static, 17000) hasilkan tag 01/54/63 SAMA PERSIS '
      'dgn payload dinamis 17k asli (minus token proprietary tag 62 sub-50)',
      () {
    final result = injectQrisAmount(static, 17000);
    expect(verifyQrisCrc(result), isTrue);

    final got = Map.fromEntries(parseQrisTlv(result));
    final want = Map.fromEntries(parseQrisTlv(dynamic17k));

    expect(got['01'], want['01']); // '12'
    expect(got['54'], want['54']); // '17000'
    // Field lain (merchant/NMID/nama toko/kota) HARUS identik dgn payload
    // dinamis asli — pembuktian bahwa injeksi tidak merusak apa pun selain
    // tag yang memang dimaksud diubah.
    for (final tag in ['00', '26', '51', '52', '53', '58', '59', '60', '61']) {
      expect(got[tag], want[tag], reason: 'tag $tag harus identik');
    }
    // tag 62 SENGAJA beda (token proprietary GoPay tidak direplikasi) —
    // versi kita cuma warisan apa adanya dari static (tanpa sub-tag 50).
    expect(got['62'], Map.fromEntries(parseQrisTlv(static))['62']);
  });

  test('injectQrisAmount(static, 20000) juga match tag 01/54 dgn dinamis 20k asli',
      () {
    final result = injectQrisAmount(static, 20000);
    expect(verifyQrisCrc(result), isTrue);
    final got = Map.fromEntries(parseQrisTlv(result));
    final want = Map.fromEntries(parseQrisTlv(dynamic20k));
    expect(got['01'], want['01']);
    expect(got['54'], want['54']);
  });

  test('injectQrisAmount payload rusak (tag 53 tak ada) -> QrisTlvException',
      () {
    const noCurrency =
        '0002010102110208ID5802ID63041234'; // sengaja tanpa tag 53
    expect(() => injectQrisAmount(noCurrency, 1000),
        throwsA(isA<QrisTlvException>()));
  });

  test('injectQrisAmount payload terpotong -> QrisTlvException, TIDAK crash',
      () {
    expect(() => injectQrisAmount('0002010', 1000),
        throwsA(isA<QrisTlvException>()));
  });
}
