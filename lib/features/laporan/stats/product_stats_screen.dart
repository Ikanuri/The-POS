import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'stats_common.dart';

/// Statistik detail SATU produk, bisa difilter rentang tanggal.
///
/// Dibuka dari tab Produk di Laporan (barisnya dulu BUNTU — tidak bisa
/// diketuk sama sekali). Rentang awal diwarisi dari header Laporan, lalu
/// bisa diubah LOKAL di sini tanpa mengubah rentang tab yang ditinggalkan
/// (lihat dok [StatsRangeBar]).
class ProductStatsScreen extends ConsumerStatefulWidget {
  const ProductStatsScreen({
    super.key,
    required this.productId,
    required this.productName,
    required this.initialRange,
  });

  final String productId;
  final String productName;
  final DateTimeRange initialRange;

  @override
  ConsumerState<ProductStatsScreen> createState() => _ProductStatsScreenState();
}

typedef _ProductStatsData = ({
  ProductStatsSummary summary,
  List<ProductDailySales> daily,
  List<ProductBuyerStat> buyers,
});

class _ProductStatsScreenState extends ConsumerState<ProductStatsScreen> {
  late DateTimeRange _range = widget.initialRange;

  Future<_ProductStatsData> _load() async {
    final db = ref.read(databaseProvider);
    final summary = await db.getProductStatsSummary(
        widget.productId, _range.start, _range.end);
    final daily = await db.getProductDailySales(
        widget.productId, _range.start, _range.end);
    final buyers = await db.getProductTopBuyers(
        widget.productId, _range.start, _range.end);
    return (summary: summary, daily: daily, buyers: buyers);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.productName,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          StatsRangeBar(
            range: _range,
            onChanged: (r) => setState(() => _range = r),
          ),
          Expanded(
            child: FutureBuilder<_ProductStatsData>(
              // `_range` masuk ke key supaya FutureBuilder benar-benar
              // memuat ulang saat rentang diganti — tanpa ini widget yang
              // sama dipakai lagi & future lama yang sudah selesai tetap
              // dipakai (angkanya tidak berubah walau tanggal sudah diubah).
              key: ValueKey(_range),
              future: _load(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final d = snap.data!;
                final s = d.summary;
                if (s.txCount == 0) {
                  return Center(
                    child: Text('Belum ada penjualan di rentang ini',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Column(
                        children: [
                          Row(children: [
                            Expanded(
                                child: StatTile(
                                    label: 'Terjual',
                                    value: fmtQty(s.qtySold))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: StatTile(
                                    label: 'Jumlah nota',
                                    value: '${s.txCount}')),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                                child: StatTile(
                                    label: 'Omzet',
                                    value: formatRupiah(s.revenue))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: StatTile(
                              label: 'Laba',
                              value: formatRupiah(s.revenue - s.cogs),
                              color: (s.revenue - s.cogs) >= 0
                                  ? scheme.tertiary
                                  : scheme.error,
                            )),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                                child: StatTile(
                              label: 'Harga jual rata-rata',
                              value: s.qtySold == 0
                                  ? '-'
                                  : formatRupiah(
                                      (s.revenue / s.qtySold).round()),
                            )),
                            const SizedBox(width: 8),
                            Expanded(
                                child: StatTile(
                              label: 'HPP terpakai',
                              value: formatRupiah(s.cogs),
                            )),
                          ]),
                        ],
                      ),
                    ),
                    if (d.daily.isNotEmpty) ...[
                      const StatsSectionTitle('Tren penjualan (qty)'),
                      StatsTrendChart(
                        points: [
                          for (final p in d.daily)
                            (date: p.date, value: p.qty),
                        ],
                        color: scheme.primary,
                        valueLabel: (v) => '${fmtQty(v.toDouble())} terjual',
                      ),
                    ],
                    const StatsSectionTitle('Pembeli teratas'),
                    if (d.buyers.isEmpty)
                      const StatsEmptyHint(
                          'Belum ada pembelian oleh pelanggan terdaftar di '
                          'rentang ini (pembeli umum tidak dihitung).')
                    else
                      for (final b in d.buyers)
                        ListTile(
                          dense: true,
                          title: Text(b.name,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${fmtQty(b.qty)} terjual',
                              style: const TextStyle(fontSize: 11)),
                          trailing: Text(
                            formatRupiah(b.revenue),
                            style: AppTheme.numStyle(context, size: 13),
                          ),
                        ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
