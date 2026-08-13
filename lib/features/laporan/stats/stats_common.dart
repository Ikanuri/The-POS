import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/chart_utils.dart';

/// Potongan UI yang dipakai BERSAMA oleh layar statistik produk & pelanggan.
///
/// Sengaja dibagi supaya angka & tampilan tidak pernah menyimpang antara
/// dua layar itu — dan antara layar detail vs tab ringkas di Laporan yang
/// jadi pintu masuknya.

/// Bar rentang tanggal — pola sama header Laporan (`_pickRange`), tapi
/// state-nya LOKAL per layar detail (bukan `dateRangeProvider` global):
/// mengubah rentang saat menelusuri satu produk/pelanggan TIDAK boleh
/// ikut mengubah rentang tab Laporan yang ditinggalkan di belakang.
class StatsRangeBar extends StatelessWidget {
  const StatsRangeBar({
    super.key,
    required this.range,
    required this.onChanged,
  });

  final DateTimeRange range;
  final ValueChanged<DateTimeRange> onChanged;

  static String fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pick(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: range,
    );
    if (picked == null) return;
    onChanged(DateTimeRange(
      start: DateTime(picked.start.year, picked.start.month, picked.start.day),
      end: DateTime(
          picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => _pick(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.date_range_outlined,
                  size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${fmt(range.start)} – ${fmt(range.end)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text('Ubah',
                  style: TextStyle(fontSize: 12, color: scheme.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu angka ringkas (dipakai berjajar 2 kolom di atas layar statistik).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.numStyle(context,
                  size: 15, weight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Judul seksi di dalam layar statistik.
class StatsSectionTitle extends StatelessWidget {
  const StatsSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );
}

/// Grafik batang tren harian — pola SAMA `_ExpenseDailyChart`
/// (`pengeluaran_tab.dart`): tinggi bar lewat [clampedBarHeight] supaya nilai
/// negatif/kosong tidak bikin bar hilang atau meluber, label tanggal
/// dijarangkan mengikuti banyaknya titik.
class StatsDailyBarChart extends StatelessWidget {
  const StatsDailyBarChart({
    super.key,
    required this.points,
    required this.color,
    required this.tooltipOf,
  });

  /// Sudah TERURUT menaik by tanggal (query `getProductDailySales` sudah
  /// `ORDER BY d`).
  final List<({DateTime date, num value})> points;
  final Color color;
  final String Function(({DateTime date, num value}) p) tooltipOf;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final max = points.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final total = points.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: points.map((p) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message: tooltipOf(p),
                      child: Container(
                        height: clampedBarHeight(p.value, max),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: points.asMap().entries.map((entry) {
              final i = entry.key;
              final date = entry.value.date;
              final show = total <= 7
                  ? true
                  : total <= 14
                      ? i % 2 == 0
                      : total <= 31
                          ? i % 3 == 0 || i == total - 1
                          : i % 7 == 0 || i == total - 1;
              return Expanded(
                child: Text(
                  show ? '${date.day}/${date.month}' : '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 8, color: scheme.onSurfaceVariant),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// Pesan kosong seragam untuk seksi yang tidak punya data di rentang ini.
class StatsEmptyHint extends StatelessWidget {
  const StatsEmptyHint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

/// Format qty: buang ".0" untuk bilangan bulat (pola dipakai di seluruh app,
/// mis. daftar varian & riwayat opname).
String fmtQty(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();
