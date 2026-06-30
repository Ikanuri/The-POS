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
    // Palet mencolok untuk Top item. Warna ke-5 (biru) ditambahkan agar saat
    // ada 5 Top + "Lainnya", slice Lainnya tidak meminjam ulang warna Top 1.
    final topColors = <Color>[
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.error,
      const Color(0xFF4C7DBF),
    ];
    final onTopColors = <Color>[
      scheme.onPrimary,
      scheme.onTertiary,
      scheme.onSecondary,
      scheme.onError,
      Colors.white,
    ];
    // "Lainnya" selalu abu-abu netral — beda jelas dari Top 1 (primary).
    final otherColor = scheme.surfaceContainerHighest;
    final onOtherColor = scheme.onSurfaceVariant;

    final hasOther = otherValue > 0;
    final all = [
      ...slices,
      if (hasOther) _Slice('Lainnya', otherValue),
    ];
    final total = all.fold(0, (a, s) => a + s.value);

    bool isOther(int i) => hasOther && i == all.length - 1;
    Color colorFor(int i) =>
        isOther(i) ? otherColor : topColors[i % topColors.length];
    Color onColorFor(int i) =>
        isOther(i) ? onOtherColor : onTopColors[i % onTopColors.length];

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < all.length; i++) {
      final double pct = total > 0 ? all[i].value / total * 100 : 0;
      // Slice kecil (<8%) → angka tidak muat di dalam ring; dorong ke luar
      // ring (lurus dengan porsinya) memakai warna teks netral agar terbaca.
      final small = pct < 8;
      sections.add(PieChartSectionData(
        value: all[i].value.toDouble(),
        color: colorFor(i),
        title: total > 0 ? '${pct.round()}%' : '',
        radius: 27,
        titlePositionPercentageOffset: small ? 1.4 : 0.5,
        titleStyle: TextStyle(
          fontSize: small ? 9 : 10.5,
          fontWeight: FontWeight.w700,
          color: small ? scheme.onSurface : onColorFor(i),
        ),
      ));
    }

    return Row(
      children: [
        SizedBox(
          width: 150,
          height: 150,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 30,
              sectionsSpace: 2,
              sections: sections,
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
                          color: colorFor(i),
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
