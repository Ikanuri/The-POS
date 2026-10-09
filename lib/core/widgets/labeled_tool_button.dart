import 'package:flutter/material.dart';

/// Tombol toolbar berupa kotak ikon kecil + keterangan di bawahnya —
/// dipakai toolbar layar Kasir (asal widget ini, dulu `_TbBtn` privat di
/// `kasir_screen.dart`) dan header tab Produk & sub-fiturnya (Item 92:
/// tombol header yang hanya ikon membingungkan, nama fungsi baru muncul
/// lewat tooltip tahan-lama).
class LabeledToolButton extends StatelessWidget {
  const LabeledToolButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
    this.label,
    this.tooltip,
    this.fg,
    this.bg,
    this.labelWidth = 44,
    this.round = false,
  });

  final IconData icon;

  /// null = tombol nonaktif (diredupkan).
  final VoidCallback? onTap;
  final int badgeCount;

  /// Keterangan opsional di bawah ikon (mis. 'Antrian'). Boleh berisi '\n'
  /// untuk memaksa dua baris. Lebar dibatasi agar tidak menabrak tombol lain.
  final String? label;

  /// Tooltip opsional (tahan-lama) — dipertahankan di header Produk supaya
  /// aksesibilitas/pencarian tombol lewat nama tetap jalan.
  final String? tooltip;

  /// Item 33 — aksen soft per-fungsi (mis. `AppTheme.scanFg`/`scanBg`).
  /// Null = netral.
  final Color Function(bool isDark)? fg;
  final Color Function(bool isDark)? bg;

  /// Lebar area label (default 44 = toolbar kasir). Label panjang di header
  /// lain boleh sedikit lebih lebar supaya tetap muat 2 baris.
  final double labelWidth;

  /// Gaya landing: lingkaran 46dp + label 11sp (default: kotak 36 + label 8.5).
  final bool round;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onTap != null;
    final iconColor = (fg?.call(isDark) ?? cs.onSurfaceVariant)
        .withOpacity(enabled ? 1 : 0.38);
    final bgColor = bg?.call(isDark) ?? cs.surface;
    final child = Icon(icon, size: round ? 21 : 18, color: iconColor);
    final box = Container(
      width: round ? 46 : 36,
      height: round ? 46 : 36,
      decoration: BoxDecoration(
        color: bgColor,
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: round ? null : BorderRadius.circular(10),
        border: round
            ? null
            : Border.all(color: cs.outlineVariant, width: 0.75),
      ),
      alignment: Alignment.center,
      child: badgeCount > 0
          ? Badge(label: Text('$badgeCount'), child: child)
          : child,
    );
    final button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          box,
          if (label != null)
            Padding(
              padding: EdgeInsets.only(top: round ? 5 : 2),
              child: SizedBox(
                width: labelWidth,
                child: Text(
                  label!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: round ? 11 : 8.5,
                    height: 1.05,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Baris tombol [LabeledToolButton] untuk `AppBar.actions` — rapat, rata
/// tengah vertikal, dgn jarak kecil antar tombol & di tepi kanan. Pakai
/// bersama `AppBar(toolbarHeight: kLabeledToolbarHeight)` supaya label
/// dua baris tidak terpotong.
class LabeledToolbarActions extends StatelessWidget {
  const LabeledToolbarActions({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Tinggi AppBar utk header berlabel (kotak 36 + label 2 baris).
const double kLabeledToolbarHeight = 64;
