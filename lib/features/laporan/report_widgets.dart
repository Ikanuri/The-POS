import 'package:flutter/material.dart';

import '../../core/theme/app_style.dart';
import '../../core/theme/app_theme.dart';

/// Kartu utama laporan (gradien terracotta; merah tua bila [negative]).
class ReportHero extends StatelessWidget {
  const ReportHero({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.negative = false,
    this.icon = Icons.insights_rounded,
  });

  final String label;
  final String value;
  final String? sub;
  final bool negative;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('report-hero'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppStyle.rPanel),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: negative
              ? const [Color(0xFFD9625A), Color(0xFFB8423C)]
              : const [Color(0xFFD97757), Color(0xFFC96442)],
        ),
        boxShadow: AppStyle.accentShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70)),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: AppTheme.numStyle(context,
                    size: 30, weight: FontWeight.w600, color: Colors.white)),
          ),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(sub!,
                style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
          ],
        ],
      ),
    );
  }
}

/// Kartu angka putih: ikon bulat berwarna fungsi + label + nominal serif.
class ReportKpiCard extends StatelessWidget {
  const ReportKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.fg,
    required this.bg,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color fg;
  final Color bg;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
              child: Icon(icon, size: 16, color: fg),
            ),
            const SizedBox(height: 10),
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: AppTheme.numStyle(context,
                      size: 15.5, weight: FontWeight.w600, color: valueColor)),
            ),
          ],
        ),
      ),
    );
  }
}
