import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';

final _ringkasanTabProvider =
    FutureProvider.family<_RingkasanTabData, DateTimeRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final txList = await (db.select(db.transactions)
        ..where((t) =>
            t.status.isNotValue('void') &
            t.createdAt.isBiggerOrEqualValue(range.start) &
            t.createdAt.isSmallerOrEqualValue(range.end))
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
      .get();

  final revenue = txList.fold(0, (s, t) => s + t.total);
  final txCount = txList.length;

  // Payment method breakdown
  final byMethod = <String, int>{};
  for (final tx in txList) {
    byMethod[tx.paymentMethod] = (byMethod[tx.paymentMethod] ?? 0) + tx.total;
  }

  // COGS
  int totalCogs = 0;
  for (final tx in txList) {
    final items = await (db.select(db.transactionItems)
          ..where((t) => t.transactionId.equals(tx.id)))
        .get();
    totalCogs += items.fold<int>(0, (s, i) => s + (i.costAtSale * i.qty).round());
  }

  // Daily breakdown for chart
  final daily = <DateTime, int>{};
  for (final tx in txList) {
    final day = DateTime(
        tx.createdAt.year, tx.createdAt.month, tx.createdAt.day);
    daily[day] = (daily[day] ?? 0) + tx.total;
  }

  return _RingkasanTabData(
    revenue: revenue,
    txCount: txCount,
    cogs: totalCogs,
    profit: revenue - totalCogs,
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
          const SizedBox(height: 20),

          // Payment breakdown
          if (data.byMethod.isNotEmpty) ...[
            Text('Metode Pembayaran',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: data.byMethod.entries.map((e) {
                  final pct = data.revenue > 0
                      ? (e.value / data.revenue * 100).round()
                      : 0;
                  return ListTile(
                    dense: true,
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

  String _methodLabel(String m) => switch (m) {
        'tunai' => 'Tunai',
        'transfer' => 'Transfer Bank',
        'qris' => 'QRIS',
        'ewallet' => 'E-Wallet',
        'tempo' => 'Tempo',
        _ => m,
      };
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

    return SizedBox(
      height: 80,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: sorted.map((e) {
          final h = max > 0 ? (e.value / max * 70) : 2.0;
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
    );
  }
}

class _RingkasanTabData {
  const _RingkasanTabData({
    required this.revenue,
    required this.txCount,
    required this.cogs,
    required this.profit,
    required this.byMethod,
    required this.daily,
  });

  final int revenue;
  final int txCount;
  final int cogs;
  final int profit;
  final Map<String, int> byMethod;
  final Map<DateTime, int> daily;
}
