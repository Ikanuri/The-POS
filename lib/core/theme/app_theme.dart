import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // Terracotta clay accent — from mockup --accent token
  static const accent = Color(0xFFC96442);

  // ── Warna semantik kasir (konsisten light & dark) ──────────────────
  // Hutang / sisa bayar → MERAH di semua mode.
  // Kembalian → HIJAU soft di semua mode.
  static Color debtFg(bool isDark) =>
      isDark ? const Color(0xFFFF8A8A) : const Color(0xFFD64545);
  static Color debtBg(bool isDark) =>
      isDark ? const Color(0x4DFF6B6B) : const Color(0xFFFCE9E9);
  static Color changeFg(bool isDark) =>
      isDark ? const Color(0xFF74E0AC) : const Color(0xFF1E7E4F);
  static Color changeBg(bool isDark) =>
      isDark ? const Color(0x4D5FD39A) : const Color(0xFFE3F4EA);

  /// SnackBar dengan warna yang benar di light & dark. Untuk pesan error,
  /// pakai [isError] agar latar/ikon merah konsisten (tidak pink kontras buruk).
  static void showSnack(BuildContext context, String message,
      {bool isError = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? _dCard : _lInk;
    final fg = isDark ? _dInk : _lCanvas;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: bg,
        content: Row(
          children: [
            if (isError) ...[
              Icon(Icons.error_outline, size: 18, color: debtFg(isDark)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(message, style: TextStyle(color: fg)),
            ),
          ],
        ),
      ));
  }

  // Light palette — exact mockup CSS tokens
  static const _lCanvas = Color(0xFFEBE8E0);
  static const _lPanel  = Color(0xFFFBFAF7);
  static const _lCard   = Color(0xFFFFFFFF);
  static const _lLine   = Color(0xFFE7E2D7);
  static const _lField  = Color(0xFFF1EEE7);
  static const _lInk    = Color(0xFF2A2824);
  static const _lInk2   = Color(0xFF6C685F);
  static const _lInk3   = Color(0xFF9D988B);

  // Dark palette
  static const _dCanvas = Color(0xFF161412);
  static const _dPanel  = Color(0xFF211E1C);
  static const _dCard   = Color(0xFF2A2623);
  static const _dLine   = Color(0xFF383330);
  static const _dField  = Color(0xFF1C1917);
  static const _dInk    = Color(0xFFECE7DD);
  static const _dInk2   = Color(0xFFA8A298);
  static const _dInk3   = Color(0xFF726C63);

  // Warm-tinted shadows: rgba(48,36,22,…)
  static const _sh1L = Color(0x0F302416); // light .06
  static const _sh1D = Color(0x4D000000); // dark  .30

  static ThemeData light() => _build(false);
  static ThemeData dark()  => _build(true);

  /// Warna latar terdalam (scaffold background) untuk mode yang diberikan.
  /// Dipakai untuk mewarnai system navigation bar Android agar mengikuti tema.
  static Color canvasColor(bool isDark) => isDark ? _dCanvas : _lCanvas;

  /// Newsreader serif style — use for all monetary/numeric values.
  static TextStyle numStyle(
    BuildContext context, {
    double size = 17,
    FontWeight weight = FontWeight.w600,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GoogleFonts.newsreader(
      fontSize: size,
      fontWeight: weight,
      color: color ?? cs.onSurface,
      letterSpacing: -0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static ThemeData _build(bool isDark) {
    final canvas = isDark ? _dCanvas : _lCanvas;
    final panel  = isDark ? _dPanel  : _lPanel;
    final card   = isDark ? _dCard   : _lCard;
    final line   = isDark ? _dLine   : _lLine;
    final field  = isDark ? _dField  : _lField;
    final ink    = isDark ? _dInk    : _lInk;
    final ink3   = isDark ? _dInk3   : _lInk3;
    final sh1    = isDark ? _sh1D    : _sh1L;

    var scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: isDark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: accent,
      surface: panel,
      surfaceContainerLowest: canvas,
      onSurface: ink,
      outlineVariant: line,
    );

    // Di dark mode, container M3 (primaryContainer/tertiaryContainer) terlalu
    // redup untuk chip "Uang Pas", metode bayar terpilih, & kartu "Bayar Nanti".
    // Naikkan sedikit kecerahannya dengan tint di atas kartu gelap + teks terang.
    if (isDark) {
      scheme = scheme.copyWith(
        primaryContainer: Color.alphaBlend(accent.withOpacity(0.42), card),
        onPrimaryContainer: ink,
        tertiaryContainer:
            Color.alphaBlend(scheme.tertiary.withOpacity(0.40), card),
        onTertiaryContainer: ink,
      );
    }

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
    );

    return base.copyWith(
      textTheme: GoogleFonts.hankenGroteskTextTheme(base.textTheme).apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      cardTheme: CardTheme(
        elevation: 1.5,
        shadowColor: sh1,
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: line, width: 0.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          minimumSize: const Size(double.infinity, 48),
          textStyle: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          minimumSize: const Size(double.infinity, 48),
          side: BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: TextStyle(color: ink3, fontSize: 13.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: panel,
        indicatorColor: accent.withOpacity(0.12),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 64,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: accent, size: 22);
          }
          return IconThemeData(color: ink3, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.hankenGrotesk(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: accent,
            );
          }
          return GoogleFonts.hankenGrotesk(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: ink3,
          );
        }),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: panel,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: sh1,
        centerTitle: false,
        titleTextStyle: GoogleFonts.hankenGrotesk(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        iconTheme: IconThemeData(color: isDark ? _dInk2 : _lInk2),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 0.5),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: line, width: 0.75),
        backgroundColor: field,
        labelStyle: TextStyle(fontSize: 11.5, color: isDark ? _dInk2 : _lInk2),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? _dCard : _lInk,
        contentTextStyle: GoogleFonts.hankenGrotesk(color: isDark ? _dInk : _lCanvas),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        behavior: SnackBarBehavior.floating,
      ),
      // Preserve warm shadow for all elevated surfaces
      shadowColor: sh1,
    );
  }
}

/// Format Rupiah: 1234567 → "Rp 1.234.567"
String formatRupiah(num value) {
  final s = value.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${value < 0 ? '-' : ''}Rp $buf';
}
