import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/chart_utils.dart';

final _ringkasanProvider = FutureProvider<_RingkasanData>((ref) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = todayStart.add(const Duration(days: 1));
  final weekStart = now.subtract(Duration(days: now.weekday - 1));
  final weekStartDay =
      DateTime(weekStart.year, weekStart.month, weekStart.day);
  final monthStart = DateTime(now.year, now.month, 1);

  final todayTx = await (db.select(db.transactions)
        ..where((t) =>
            t.status.isNotValue('void') &
            t.createdAt.isBiggerOrEqualValue(todayStart) &
            t.createdAt.isSmallerOrEqualValue(todayEnd)))
      .get();

  final weekTx = await (db.select(db.transactions)
        ..where((t) =>
            t.status.isNotValue('void') &
            t.createdAt.isBiggerOrEqualValue(weekStartDay)))
      .get();

  final monthTx = await (db.select(db.transactions)
        ..where((t) =>
            t.status.isNotValue('void') &
            t.createdAt.isBiggerOrEqualValue(monthStart)))
      .get();

  // Hourly breakdown untuk hari ini
  final hourly = List<int>.filled(24, 0);
  for (final tx in todayTx) {
    hourly[tx.createdAt.hour] += tx.total;
  }

  // Top products hari ini
  final todayItems = <String, _ProductStat>{};
  for (final tx in todayTx) {
    final items = await (db.select(db.transactionItems)
          ..where((t) => t.transactionId.equals(tx.id)))
        .get();
    for (final item in items) {
      final stat = todayItems.putIfAbsent(
          item.productId, () => _ProductStat(item.productId));
      stat.sold += item.qty;
      stat.revenue += item.subtotal;
    }
  }
  final topProds = todayItems.values.toList()
    ..sort((a, b) => b.revenue.compareTo(a.revenue));

  // Load product names for top products
  for (final s in topProds.take(5)) {
    final p = await (db.select(db.products)
          ..where((t) => t.id.equals(s.productId)))
        .getSingleOrNull();
    if (p != null) s.name = p.name;
  }

  return _RingkasanData(
    todayRevenue: todayTx.fold(0, (s, t) => s + t.total),
    todayTransactions: todayTx.length,
    weekRevenue: weekTx.fold(0, (s, t) => s + t.total),
    monthRevenue: monthTx.fold(0, (s, t) => s + t.total),
    hourly: hourly,
    topProducts: topProds.take(5).toList(),
  );
});

class RingkasanScreen extends ConsumerWidget {
  const RingkasanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider);
    final dataAsync = ref.watch(_ringkasanProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(device.storeName.isNotEmpty ? device.storeName : 'Ringkasan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () => ref.invalidate(_ringkasanProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_ringkasanProvider),
        child: dataAsync.when(
          data: (data) => _RingkasanBody(data: data),
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }
}

class _RingkasanBody extends StatelessWidget {
  const _RingkasanBody({required this.data});
  final _RingkasanData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // KPI Cards
        Row(
          children: [
            Expanded(
                child: _KpiCard(
              label: 'Hari Ini',
              value: formatRupiah(data.todayRevenue),
              sub: '${data.todayTransactions} transaksi',
              icon: Icons.today_outlined,
              color: scheme.primary,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _KpiCard(
              label: 'Minggu Ini',
              value: formatRupiah(data.weekRevenue),
              icon: Icons.date_range_outlined,
              color: scheme.secondary,
            )),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _KpiCard(
              label: 'Bulan Ini',
              value: formatRupiah(data.monthRevenue),
              icon: Icons.calendar_month_outlined,
              color: scheme.tertiary,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _KpiCard(
              label: 'Rata-rata/Hari',
              value: formatRupiah(data.monthRevenue ~/
                  DateTime.now().day.clamp(1, 31)),
              icon: Icons.trending_up_outlined,
              color: scheme.onSurfaceVariant,
            )),
          ],
        ),
        const SizedBox(height: 20),

        // Hourly chart
        Text('Penjualan Per Jam (Hari Ini)',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _HourlyChart(hourly: data.hourly),
          ),
        ),
        const SizedBox(height: 20),

        // Top products
        if (data.topProducts.isNotEmpty) ...[
          Text('Produk Terlaris Hari Ini',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: data.topProducts.asMap().entries.map((e) {
                final rank = e.key + 1;
                final prod = e.value;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: rank == 1
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    child: Text(
                      '$rank',
                      style: TextStyle(
                          color: rank == 1
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                  ),
                  title: Text(
                      prod.name.isNotEmpty ? prod.name : prod.productId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${prod.sold % 1 == 0 ? prod.sold.toInt() : prod.sold} terjual',
                      style:
                          TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
                  trailing: Text(
                    formatRupiah(prod.revenue),
                    style: TextStyle(
                        color: scheme.primary, fontWeight: FontWeight.w600),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    this.sub,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color)),
            if (sub != null)
              Text(sub!,
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _HourlyChart extends StatelessWidget {
  const _HourlyChart({required this.hourly});
  final List<int> hourly;

  @override
  Widget build(BuildContext context) {
    final max = hourly.reduce((a, b) => a > b ? a : b);
    if (max == 0) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Belum ada penjualan hari ini',
            style: TextStyle(fontSize: 12)),
      );
    }
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: hourly.asMap().entries.map((e) {
              final h = e.key;
              final v = e.value;
              final height = clampedBarHeight(v, max, emptyHeight: 0);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Tooltip(
                    message: '$h:00\n${formatRupiah(v)}',
                    child: Container(
                      height: height + 2,
                      decoration: BoxDecoration(
                        color: v > 0
                            ? scheme.primary
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
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
          children: hourly.asMap().entries.map((e) {
            final h = e.key;
            final label = h % 6 == 0 ? h.toString().padLeft(2, '0') : '';
            return Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 8, color: scheme.onSurfaceVariant),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _RingkasanData {
  _RingkasanData({
    required this.todayRevenue,
    required this.todayTransactions,
    required this.weekRevenue,
    required this.monthRevenue,
    required this.hourly,
    required this.topProducts,
  });

  final int todayRevenue;
  final int todayTransactions;
  final int weekRevenue;
  final int monthRevenue;
  final List<int> hourly;
  final List<_ProductStat> topProducts;
}

class _ProductStat {
  _ProductStat(this.productId);
  final String productId;
  String name = '';
  double sold = 0;
  int revenue = 0;
}
