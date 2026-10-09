import '../../../core/widgets/app_empty_state.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/chart_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/data_refresh_provider.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../stats/product_stats_screen.dart';

final _produkTabProvider =
    FutureProvider.family<List<ProductRevenueStat>, DateTimeRange>(
        (ref, range) async {
  // Lihat dok `dataSyncedTickProvider` — provider ini tidak reaktif thd DB.
  ref.watch(dataSyncedTickProvider);
  final db = ref.watch(databaseProvider);
  // Satu query JOIN + GROUP BY, bukan N+1 per transaksi.
  return db.getTopProductsByRevenue(range.start, range.end);
});

class ProdukTab extends ConsumerWidget {
  const ProdukTab({super.key, required this.range});
  final DateTimeRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(_produkTabProvider(range));
    final scheme = Theme.of(context).colorScheme;

    return dataAsync.when(
      data: (stats) {
        if (stats.isEmpty) {
          return const AppEmptyState('Tidak ada data untuk periode ini');
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (stats.length >= 2)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: _TopDonut(
                    slices: [
                      for (final s in stats.take(5))
                        _Slice(_short(s.name.isNotEmpty ? s.name : s.productId),
                            s.revenue),
                    ],
                    otherValue: stats.skip(5).fold(0, (a, s) => a + s.revenue),
                  ),
                ),
              ),
            Card(
              margin: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 60),
                  _row(context, scheme, stats[i], i),
                ],
              ]),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _row(
      BuildContext context, ColorScheme scheme, ProductRevenueStat s, int i) {
    final sold = s.qtySold % 1 == 0 ? s.qtySold.toInt() : s.qtySold;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            i == 0 ? scheme.primary : scheme.surfaceContainerHighest,
        child: Text(
          '${i + 1}',
          style: TextStyle(
              color: i == 0 ? scheme.onPrimary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 13),
        ),
      ),
      title: Text(s.name.isNotEmpty ? s.name : s.productId,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$sold terjual · Laba: ${formatRupiah(s.profit)}',
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        formatRupiah(s.revenue),
        style: AppTheme.numStyle(context,
            size: 14.5, weight: FontWeight.w600, color: scheme.primary),
      ),
      // Baris ini dulu BUNTU (tidak bisa diketuk sama sekali) — sekarang
      // membuka statistik detail produknya, rentang tanggal tab ikut
      // terbawa sbg rentang awal.
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProductStatsScreen(
            productId: s.productId,
            productName: s.name.isNotEmpty ? s.name : s.productId,
            initialRange: range,
          ),
        ),
      ),
    );
  }

  static String _short(String s) =>
      s.length <= 12 ? s : '${s.substring(0, 12)}…';
}

class _Slice {
  const _Slice(this.label, this.value);
  final String label;
  final int value;
}

/// Donut top-5 + "Lainnya". Dipakai bersama oleh tab produk & pelanggan.
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
    return AppDonut(
      size: 150,
      slices: [
        for (var i = 0; i < slices.length; i++)
          DonutSlice(slices[i].label, slices[i].value,
              topColors[i % topColors.length],
              onTopColors[i % onTopColors.length]),
        // "Lainnya" selalu abu-abu netral — beda jelas dari Top 1 (primary).
        if (otherValue > 0)
          DonutSlice('Lainnya', otherValue, scheme.surfaceContainerHighest,
              scheme.onSurfaceVariant),
      ],
    );
  }
}
