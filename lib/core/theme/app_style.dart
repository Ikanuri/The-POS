import 'package:flutter/material.dart';

/// Token bentuk & bayangan "Gaya Landing" — satu sumber untuk seluruh app
/// (lihat docs/STYLE-UIUX.md). Warna tetap di [AppTheme].
class AppStyle {
  AppStyle._();

  static const double rPill = 999;
  static const double rCard = 18;
  static const double rPanel = 22;
  static const double rSheet = 30;
  static const double rField = 14;

  /// Gutter horizontal layar.
  static const double gutter = 14;

  /// Bayangan kartu: lembut & hangat.
  static List<BoxShadow> cardShadow(bool dark) => [
        BoxShadow(
          color: dark ? const Color(0x40000000) : const Color(0x155A3C1E),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ];

  /// Bayangan elemen melayang (cart bar, toast, popup).
  static List<BoxShadow> floatShadow(bool dark) => [
        BoxShadow(
          color: dark ? const Color(0x99000000) : const Color(0x385A3C1E),
          blurRadius: 22,
          offset: const Offset(0, 6),
        ),
      ];

  /// Bayangan tombol/logo beraksen.
  static const accentShadow = [
    BoxShadow(
      color: Color(0x59C96442),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];
}
