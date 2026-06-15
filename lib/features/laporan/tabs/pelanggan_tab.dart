import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';

final _pelangganTabProvider = FutureProvider.family<List<CustomerRevenueStat>,
    DateTimeRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  // Satu query JOIN + GROUP BY, bukan N+1 per transaksi.
  return db.getTopCustomersByRevenue(range.start, range.end);
});

class PelangganTab extends ConsumerWidget {
  const PelangganTab({super.key, required this.range});
  final DateTimeRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(_pelangganTabProvider(range));
    final scheme = Theme.of(context).colorScheme;

    return dataAsync.when(
      data: (stats) {
        if (stats.isEmpty) {
          return Center(
            child: Text('Tidak ada transaksi pelanggan terdaftar',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (stats.length >= 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _TopDonut(
                  slices: [
                    for (final s in stats.take(5))
                      _Slice(s.name.isNotEmpty ? s.name : 'Umum', s.totalSpent),
                  ],
                  otherValue:
                      stats.skip(5).fold(0, (a, s) => a + s.totalSpent),
                ),
              ),
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 60),
              _row(scheme, stats[i], i),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _row(ColorScheme scheme, CustomerRevenueStat s, int i) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: i == 0 ? scheme.primary : scheme.primaryContainer,
        child: Text(
          s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
          style: TextStyle(
              color: i == 0 ? scheme.onPrimary : scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(s.name.isNotEmpty ? s.name : s.customerId,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${s.txCount} transaksi · ${s.loyaltyPoints} poin',
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        formatRupiah(s.totalSpent),
        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Slice {
  const _Slice(this.label, this.value);
  final String label;
  final int value;
}

/// Donut top-5 + "Lainnya".
class _TopDonut extends StatelessWidget {
  const _TopDonut({required this.slices, required this.otherValue});
  final List<_Slice> slices;
  final int otherValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.error,
      scheme.surfaceContainerHighest,
    ];
    final onPalette = [
      scheme.onPrimary,
      scheme.onSecondary,
      scheme.onTertiary,
      scheme.onError,
      scheme.onSurfaceVariant,
    ];
    final all = [
      ...slices,
      if (otherValue > 0) _Slice('Lainnya', otherValue),
    ];
    final total = all.fold(0, (a, s) => a + s.value);

    return Row(
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 32,
              sectionsSpace: 2,
              sections: [
                for (var i = 0; i < all.length; i++)
                  PieChartSectionData(
                    value: all[i].value.toDouble(),
                    color: palette[i % palette.length],
                    title: total > 0
                        ? '${(all[i].value / total * 100).round()}%'
                        : '',
                    radius: 38,
                    titleStyle: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: onPalette[i % onPalette.length],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < all.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: palette[i % palette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(all[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
