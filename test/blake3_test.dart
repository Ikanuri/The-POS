import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/utils/blake3.dart';

/// BLAKE3 murni-Dart — dibandingkan dgn implementasi referensi (paket
/// `blake3` Python) utk berbagai panjang input: kosong, batas blok 64,
/// batas chunk 1024, dan multi-chunk (pohon tak seimbang). Pola byte:
/// `(i*7+3) % 251`.
void main() {
  Uint8List pattern(int n) =>
      Uint8List.fromList([for (var i = 0; i < n; i++) (i * 7 + 3) % 251]);

  test('cocok dgn referensi di semua panjang uji', () {
    const vectors = <(int, String)>[
      (0, 'af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262'),
      (1, 'e1e0e81d6ea39b0cf8b86ffd440921011f57400cbc3f76a8a171906a9b8d7505'),
      (63, 'd24fb797708be34389a85d96c1a9db21582fe8f24840b27b9859fd4ea4ca4c10'),
      (64, 'b83e47b6a178a4e2e3e1c08b8fbe870efe1f829e4fd44dfa3470007abd6fdc3b'),
      (65, '03078b49cce3fff54a65a2eaa33dad8d9782798bd51e1cd4a1483283a0268873'),
      (
        1023,
        '562194b1fcae7c0933be0d66067011f544047a677a044cb8cccb0dcebb74169f'
      ),
      (
        1024,
        '1d299b433a99665838fd11e1a5f18148613ac6984dc9d184e527b17c05a1989f'
      ),
      (
        1025,
        '23ba53947a167867e27e1bbc63f790143128af06fbc970e899e2d579fa7c7e05'
      ),
      (
        2048,
        '107fb6c5cec897cfec1cfd42b671187789866677249ab06ac1a0430754cf012d'
      ),
      (
        2049,
        '9cce7f21aa060406fb92a2e9a47b48584e2981206564cdc72b686508a041cdd9'
      ),
      (
        3072,
        'be84487feb117833fb0d40744b20974ae2f7fe1a17e3904ed7be08aa8c4653f4'
      ),
      (
        5000,
        'df139b7fd2ec074a72e4435a136fbbc801ba540ee8e3872ded444615e7e0fce2'
      ),
      (
        8192,
        '622b30c6ac13f985786b41c21619b82e13ba8bcff5f10e11ce1a9d2e2258a02d'
      ),
      (
        30001,
        '88357f7f18b4338a923520d097509a3450070e89a596681a4233cacd7e4ba44d'
      ),
      (
        70000,
        'a828ccf2403fd70d604109fb97764d9aa99308dfecda8fe89766e247e43f5007'
      ),
    ];
    for (final (n, expected) in vectors) {
      expect(blake3Hex(pattern(n)), expected, reason: 'panjang $n');
    }
  });
}
