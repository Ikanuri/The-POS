import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'press_scale.dart';

/// Chip kategori/filter gaya Kasir: pil, aktif = terracotta penuh + teks putih
/// tebal, tidak aktif = latar surface + garis tipis. Dipakai bersama di
/// Ringkasan, Laporan, dst.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PressScale(
      depth: 0.05,
      child: FilterChip(
        label: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                color: selected ? Colors.white : null,
                fontWeight: selected ? FontWeight.w600 : null)),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        selectedColor: AppTheme.accent,
        backgroundColor: cs.surface,
        showCheckmark: false,
        shape: const StadiumBorder(),
        side: BorderSide(color: selected ? AppTheme.accent : cs.outlineVariant),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
