import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/chart_utils.dart';

/// Item 49d — tab dedicated "Laporan Pengeluaran": rincian per jenis +
/// grafik tren harian. Beda dari kartu "Pengeluaran" di tab Ringkasan
/// (cuma total P&L, subset [AppDatabase.netProfitExpenseTypes]) — tab ini
/// breakdown SEMUA jenis pengeluaran yang tercatat, murni "ke mana saja
/// uang mengalir", bukan angka Laba Bersih.
final _pengeluaranTabProvider =
    FutureProvider.family<_PengeluaranTabData, DateTimeRange>(
        (ref, range) async {
  final db = ref.watch(databaseProvider);
  final byType = await db.getExpenseBreakdownByType(range.start, range.end);
  final daily = await db.getExpenseDailyTotals(range.start, range.end);
  return _PengeluaranTabData(byType: byType, daily: daily);
});

/// Label kategori pengeluaran (enum `Expenses.type`) — sama persis dgn
/// `_expenseTypeLabels` di `pengaturan/expenses_screen.dart` (privat per
/// file, pola yang sudah dipakai di app ini utk map label kecil serupa,
/// mis. `_methodLabel` yang juga terduplikasi antar-file).
const _expenseTypeLabels = {
  'daily_expense': 'Operasional',
  'owner_withdrawal': 'Ambil Pribadi (Owner)',
  'supplier_payment': 'Bayar Supplier',
  'change_given': 'Uang Keluar Laci',
};

String _typeLabel(String t) => _expenseTypeLabels[t] ?? t;

const _typeColors = [
  Color(0xFFD64545),
  Color(0xFFC96442),
  Color(0xFFCFA75A),
  Color(0xFF9C7A2E),
];

Color _typeColor(int index) => _typeColors[index % _typeColors.length];

class PengeluaranTab extends ConsumerWidget {
  const PengeluaranTab({super.key, required this.range});
  final DateTimeRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(_pengeluaranTabProvider(range));
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Domain Uang & Kas → hijau (konsisten dgn kartu Pengeluaran di tab
    // Ringkasan & sistem warna CLAUDE.md), foreground nominal tetap merah
    // (semantik "uang keluar").
    final uangBg = AppTheme.changeBg(isDark);

    return dataAsync.when(
      data: (data) {
        if (data.total == 0) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Belum ada pengeluaran tercatat pada rentang ini.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          );
        }
        final entries = data.byType.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: uangBg,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Pengeluaran',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(formatRupiah(data.total),
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: scheme.error)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Rincian per Jenis',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (entries.length >= 2)
              _ExpenseDonut(entries: entries, total: data.total),
            Card(
              color: uangBg,
              child: Column(
                children: entries.asMap().entries.map((indexed) {
                  final i = indexed.key;
                  final e = indexed.value;
                  final pct =
                      data.total > 0 ? (e.value / data.total * 100).round() : 0;
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _typeColor(i),
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(_typeLabel(e.key)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$pct%',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 12)),
                        const SizedBox(width: 8),
                        Text(formatRupiah(e.value),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            if (data.daily.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Tren Harian',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ExpenseDailyChart(daily: data.daily),
                ),
              ),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _ExpenseDonut extends StatelessWidget {
  const _ExpenseDonut({required this.entries, required this.total});
  final List<MapEntry<String, int>> entries;
  final int total;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: PieChart(
        PieChartData(
          centerSpaceRadius: 40,
          sectionsSpace: 2,
          sections: entries.asMap().entries.map((indexed) {
            final i = indexed.key;
            final e = indexed.value;
            final pct = total > 0 ? (e.value / total * 100) : 0.0;
            return PieChartSectionData(
              value: e.value.toDouble(),
              color: _typeColor(i),
              title: '${pct.round()}%',
              radius: 50,
              titleStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ExpenseDailyChart extends StatelessWidget {
  const _ExpenseDailyChart({required this.daily});
  final Map<DateTime, int> daily;

  @override
  Widget build(BuildContext context) {
    final sorted = daily.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final max = sorted.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;
    final total = sorted.length;

    return Column(
      children: [
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: sorted.map((e) {
              final h = clampedBarHeight(e.value, max);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Tooltip(
                    message:
                        '${e.key.day}/${e.key.month}\n${formatRupiah(e.value)}',
                    child: Container(
                      height: h,
                      decoration: BoxDecoration(
                        color: scheme.error,
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
          children: sorted.asMap().entries.map((entry) {
            final i = entry.key;
            final date = entry.value.key;
            final bool show = total <= 7
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
                style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant),
                overflow: TextOverflow.visible,
                softWrap: false,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _PengeluaranTabData {
  const _PengeluaranTabData({required this.byType, required this.daily});

  final Map<String, int> byType;
  final Map<DateTime, int> daily;

  int get total => byType.values.fold(0, (s, v) => s + v);
}
