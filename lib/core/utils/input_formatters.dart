import 'package:flutter/services.dart';

/// Memformat input angka dengan pemisah ribuan (titik), gaya Indonesia.
/// Contoh: "150000" → "150.000". Hanya menerima digit.
class ThousandsSeparatorFormatter extends TextInputFormatter {
  const ThousandsSeparatorFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final formatted = _group(digits);
    // Selalu letakkan cursor di akhir — sederhana dan dapat diprediksi untuk
    // field harga yang umumnya diisi dari nol.
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  static String _group(String digits) {
    final buf = StringBuffer();
    final n = digits.length;
    for (var i = 0; i < n; i++) {
      if (i > 0 && (n - i) % 3 == 0) buf.write('.');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  /// Format nilai integer menjadi string berpemisah ribuan (tanpa "Rp").
  static String format(int value) => _group(value.toString());

  /// Ambil nilai integer dari string terformat ("150.000" → 150000).
  /// Item 41 A.7 — input digit sangat panjang (field tanpa maxLength, mis.
  /// dialog Ubah Total) dulu bikin `int.parse` melempar FormatException tak
  /// tertangani (>19 digit melewati batas int 64-bit). Dipotong ke 15 digit
  /// (ratusan triliun — jauh di atas nominal wajar) alih-alih throw.
  static int parseValue(String formatted) {
    var digits = formatted.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    if (digits.length > 15) digits = digits.substring(0, 15);
    return int.parse(digits);
  }
}
