import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/chart_utils.dart';

final _ringkasanTabProvider =
    FutureProvider.family<_RingkasanTabData, DateTimeRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  // Baca dari ringkasan harian ter-materialisasi (O(hari)) alih-alih memindai
  // seluruh transaksi + item (O(transaksi)).
  final summaries = await db.getDailySummaries(range.start, range.end);
  final expenses =
      await db.getNetProfitExpenseTotal(range.start, range.end);

  var revenue = 0;
  var cogs = 0;
  var txCount = 0;
  final byMethod = <String, int>{};
  final daily = <DateTime, int>{};

  for (final s in summaries) {
    revenue += s.omzet;
    cogs += s.hpp;
    txCount += s.jumlahTransaksi;
    if (s.pembayaranTunai > 0) {
      byMethod['tunai'] = (byMethod['tunai'] ?? 0) + s.pembayaranTunai;
    }
    if (s.pembayaranQris > 0) {
      byMethod['qris'] = (byMethod['qris'] ?? 0) + s.pembayaranQris;
    }
    if (s.pembayaranTransfer > 0) {
      byMethod['transfer'] = (byMethod['transfer'] ?? 0) + s.pembayaranTransfer;
    }
    if (s.pembayaranLainnya > 0) {
      byMethod['lainnya'] = (byMethod['lainnya'] ?? 0) + s.pembayaranLainnya;
    }
    final parts = s.date.split('-').map(int.parse).toList();
    daily[DateTime(parts[0], parts[1], parts[2])] = s.omzet;
  }

  return _RingkasanTabData(
    revenue: revenue,
    txCount: txCount,
    cogs: cogs,
    profit: revenue - cogs,
    expenses: expenses,
    byMethod: byMethod,
    daily: daily,
  );
});

class RingkasanTab extends ConsumerWidget {
  const RingkasanTab({super.key, required this.range});
  final DateTimeRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(_ringkasanTabProvider(range));
    final scheme = Theme.of(context).colorScheme;

    return dataAsync.when(
      data: (data) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Main KPIs
          _KpiRow(
            items: [
              _KpiItem('Omzet', formatRupiah(data.revenue), scheme.primary),
              _KpiItem('Transaksi', '${data.txCount}', scheme.secondary),
            ],
          ),
          const SizedBox(height: 12),
          _KpiRow(
            items: [
              _KpiItem('HPP', formatRupiah(data.cogs), scheme.onSurfaceVariant),
              _KpiItem('Laba Kotor', formatRupiah(data.profit),
                  data.profit >= 0 ? scheme.tertiary : scheme.error),
            ],
          ),
          const SizedBox(height: 12),
          _KpiRow(
            items: [
              _KpiItem('Pengeluaran', formatRupiah(data.expenses),
                  data.expenses > 0 ? scheme.error : scheme.onSurfaceVariant),
              _KpiItem('Laba Bersih', formatRupiah(data.netProfit),
                  data.netProfit >= 0 ? scheme.tertiary : scheme.error),
            ],
          ),
          const SizedBox(height: 20),

          // Payment breakdown
          if (data.byMethod.isNotEmpty) ...[
            Text('Metode Pembayaran',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (data.byMethod.length >= 2)
              _PaymentDonut(byMethod: data.byMethod, total: data.revenue),
            Card(
              child: Column(
                children: data.byMethod.entries.map((e) {
                  final pct = data.revenue > 0
                      ? (e.value / data.revenue * 100).round()
                      : 0;
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _methodColor(e.key, scheme),
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(_methodLabel(e.key)),
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
          ],

          // Daily chart
          if (data.daily.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Penjualan Harian',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _DailyChart(daily: data.daily),
              ),
            ),
          ],
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

String _methodLabel(String m) => switch (m) {
      'tunai' => 'Tunai',
      'transfer' => 'Transfer Bank',
      'qris' => 'QRIS',
      'ewallet' => 'E-Wallet',
      'tempo' => 'Tempo',
      'lainnya' => 'Lainnya',
      _ => m,
    };

Color _methodColor(String m, ColorScheme scheme) => switch (m) {
      'tunai' => scheme.primary,
      'qris' => scheme.secondary,
      'transfer' => scheme.tertiary,
      _ => scheme.surfaceContainerHighest,
    };

Color _methodOnColor(String m, ColorScheme scheme) => switch (m) {
      'tunai' => scheme.onPrimary,
      'qris' => scheme.onSecondary,
      'transfer' => scheme.onTertiary,
      _ => scheme.onSurfaceVariant,
    };

class _PaymentDonut extends StatelessWidget {
  const _PaymentDonut({required this.byMethod, required this.total});
  final Map<String, int> byMethod;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = byMethod.entries.toList();
    return SizedBox(
      height: 180,
      child: PieChart(
        PieChartData(
          centerSpaceRadius: 40,
          sectionsSpace: 2,
          sections: entries.map((e) {
            final pct = total > 0 ? (e.value / total * 100) : 0.0;
            return PieChartSectionData(
              value: e.value.toDouble(),
              color: _methodColor(e.key, scheme),
              title: '${pct.round()}%',
              radius: 50,
              titleStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _methodOnColor(e.key, scheme),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.items});
  final List<_KpiItem> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items
          .map((item) => Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label,
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text(item.value,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: item.color)),
                      ],
                    ),
                  ),
                ),
              ))
          .expand((w) => [w, const SizedBox(width: 12)])
          .toList()
        ..removeLast(),
    );
  }
}

class _KpiItem {
  const _KpiItem(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.daily});
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
                        color: scheme.primary,
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
                style: TextStyle(
                    fontSize: 8, color: scheme.onSurfaceVariant),
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

class _RingkasanTabData {
  const _RingkasanTabData({
    required this.revenue,
    required this.txCount,
    required this.cogs,
    required this.profit,
    required this.expenses,
    required this.byMethod,
    required this.daily,
  });

  final int revenue;
  final int txCount;
  final int cogs;
  final int profit;

  /// Pengeluaran yang mengurangi Laba Bersih (daily_expense + change_given).
  final int expenses;
  final Map<String, int> byMethod;
  final Map<DateTime, int> daily;

  /// Laba Bersih = Laba Kotor − Pengeluaran.
  int get netProfit => profit - expenses;
}
