import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'product_stats_screen.dart';
import 'stats_common.dart';

/// Statistik belanja SATU pelanggan, bisa difilter rentang tanggal.
///
/// Permintaan user: bisa dibuka dari DUA tempat — (a) detail/pengaturan
/// pelanggan (`PelangganFormScreen`), (b) tab Pelanggan di Laporan. Kedua
/// pintu masuk memakai layar & query yang SAMA supaya angkanya tidak pernah
/// berbeda.
///
/// Pelanggan umum/ad-hoc (nota tanpa `customer_id`) TIDAK punya layar ini —
/// keputusan user: statistik hanya untuk pelanggan terdaftar.
class CustomerStatsScreen extends ConsumerStatefulWidget {
  const CustomerStatsScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.initialRange,
  });

  final String customerId;
  final String customerName;
  final DateTimeRange initialRange;

  /// Rentang bawaan saat dibuka dari layar yang TIDAK punya konteks tanggal
  /// (mis. detail pelanggan): 1 tahun terakhir — cukup lebar untuk langsung
  /// terlihat berisi, tanpa perlu user mengatur dulu.
  static DateTimeRange defaultRange() {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year - 1, now.month, now.day),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
    );
  }

  @override
  ConsumerState<CustomerStatsScreen> createState() =>
      _CustomerStatsScreenState();
}

typedef _CustomerStatsData = ({
  CustomerStatsSummary summary,
  List<ProductRevenueStat> topProducts,
  List<Transaction> transactions,
});

class _CustomerStatsScreenState extends ConsumerState<CustomerStatsScreen> {
  late DateTimeRange _range = widget.initialRange;

  Future<_CustomerStatsData> _load() async {
    final db = ref.read(databaseProvider);
    final summary = await db.getCustomerStatsSummary(
        widget.customerId, _range.start, _range.end);
    final topProducts = await db.getCustomerTopProducts(
        widget.customerId, _range.start, _range.end);
    final txs = await db.getCustomerTransactions(
        widget.customerId, _range.start, _range.end);
    return (summary: summary, topProducts: topProducts, transactions: txs);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customerName,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          StatsRangeBar(
            range: _range,
            onChanged: (r) => setState(() => _range = r),
          ),
          Expanded(
            child: FutureBuilder<_CustomerStatsData>(
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
                    child: Text('Belum ada belanja di rentang ini',
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
                                    label: 'Total belanja',
                                    value: formatRupiah(s.totalSpent))),
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
                                    label: 'Rata-rata per nota',
                                    value: formatRupiah(s.avgPerTx))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: StatTile(
                                    label: 'Total barang',
                                    value: fmtQty(s.itemQty))),
                          ]),
                        ],
                      ),
                    ),
                    const StatsSectionTitle('Barang yang sering dibeli'),
                    if (d.topProducts.isEmpty)
                      const StatsEmptyHint('Belum ada barang di rentang ini.')
                    else
                      for (final p in d.topProducts)
                        ListTile(
                          dense: true,
                          title: Text(p.name,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${fmtQty(p.qtySold)} dibeli',
                              style: const TextStyle(fontSize: 11)),
                          trailing: Text(
                            formatRupiah(p.revenue),
                            style: AppTheme.numStyle(context, size: 13),
                          ),
                          // Nyambung ke statistik produknya, rentang tanggal
                          // ikut terbawa supaya konteksnya tidak hilang.
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ProductStatsScreen(
                                productId: p.productId,
                                productName: p.name,
                                initialRange: _range,
                              ),
                            ),
                          ),
                        ),
                    const StatsSectionTitle('Riwayat nota'),
                    for (final t in d.transactions)
                      ListTile(
                        dense: true,
                        title: Text(t.localId,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          '${StatsRangeBar.fmt(t.createdAt)} · ${t.status}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Text(
                          formatRupiah(t.total),
                          style: AppTheme.numStyle(context, size: 13),
                        ),
                        // Pola sama Buku Hutang (`/laporan` -> push
                        // `/kasir/struk/:txId`) yang sudah lama dipakai.
                        onTap: () => context.push('/kasir/struk/${t.id}'),
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
