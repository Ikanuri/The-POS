import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Nada notifikasi — dipakai bersama oleh toast ([AppToast]), banner inline
/// ([InlineBanner]) dan kartu status sync ([SyncStatusBanner]) supaya satu
/// bahasa desain: kartu putih membulat + ikon bulat beraksen di kiri.
enum ToastTone { info, success, error, sync, warning }

/// Warna & ikon bawaan satu [ToastTone] (theme-aware light/dark).
class ToastToneStyle {
  const ToastToneStyle(this.fg, this.bg, this.icon);

  /// Warna ikon/aksen/tautan.
  final Color fg;

  /// Warna lingkaran ikon (lembut).
  final Color bg;
  final IconData icon;

  static ToastToneStyle of(ToastTone tone, bool isDark) => switch (tone) {
        ToastTone.info => (ToastToneStyle(
            AppTheme.accent,
            AppTheme.accent.withOpacity(isDark ? 0.20 : 0.13),
            Icons.info_rounded,
          )),
        ToastTone.success => ToastToneStyle(AppTheme.changeFg(isDark),
            AppTheme.changeBg(isDark), Icons.check_circle_rounded),
        ToastTone.error => ToastToneStyle(AppTheme.debtFg(isDark),
            AppTheme.debtBg(isDark), Icons.error_rounded),
        ToastTone.sync => ToastToneStyle(AppTheme.riwayatFg(isDark),
            AppTheme.riwayatBg(isDark), Icons.sync_rounded),
        ToastTone.warning => ToastToneStyle(AppTheme.antrianFg(isDark),
            AppTheme.antrianBg(isDark), Icons.warning_rounded),
      };
}

/// Kartu notifikasi: putih (gelap: kartu tema), radius 18, bayangan hangat
/// lembut (`0 6 24 rgba(90,60,30,.12)` dari acuan katalog HTML), ikon bulat
/// beraksen di kiri, [child] (teks) di tengah, [trailing] opsional di kanan.
class AppNoticeCard extends StatelessWidget {
  const AppNoticeCard({
    super.key,
    required this.tone,
    required this.child,
    this.icon,
    this.spinning = false,
    this.trailing,
    this.onTap,
  });

  final ToastTone tone;
  final Widget child;

  /// Menimpa ikon bawaan nada.
  final IconData? icon;

  /// Ganti ikon dengan spinner kecil (proses berjalan).
  final bool spinning;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = ToastToneStyle.of(tone, isDark);
    final cardColor = isDark ? const Color(0xFF2A2623) : Colors.white;
    final lineColor = isDark ? const Color(0xFF383330) : const Color(0xFFE7E2D7);
    final radius = BorderRadius.circular(18);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0x59000000)
                : const Color(0x1F5A3C1E), // rgba(90,60,30,.12)
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: isDark ? const Color(0x33000000) : const Color(0x14000000),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: lineColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  key: const Key('notice_icon_circle'),
                  width: 32,
                  height: 32,
                  decoration:
                      BoxDecoration(color: style.bg, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: spinning
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: style.fg),
                        )
                      : Icon(icon ?? style.icon, size: 18, color: style.fg),
                ),
                const SizedBox(width: 10),
                Expanded(child: child),
                if (trailing != null) ...[
                  const SizedBox(width: 6),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
