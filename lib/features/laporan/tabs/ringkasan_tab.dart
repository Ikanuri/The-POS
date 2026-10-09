import 'package:flutter/material.dart';
import '../../../core/widgets/chart_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/data_refresh_provider.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../report_widgets.dart';
import '../stats/stats_common.dart';
import '../stats/trend_aggregation.dart';

final _ringkasanTabProvider =
    FutureProvider.family<_RingkasanTabData, DateTimeRange>((ref, range) async {
  // Lihat dok `dataSyncedTickProvider` — provider ini tidak reaktif thd DB.
  ref.watch(dataSyncedTickProvider);
  final db = ref.watch(databaseProvider);
  // Baca dari ringkasan harian ter-materialisasi (O(hari)) alih-alih memindai
  // seluruh transaksi + item (O(transaksi)). Perbaiki-sendiri dulu entri yang
  // BASI di rentang ini — transaksi hasil sync/merge kadang tak ikut merebuild
  // cache ini, bikin laporan lebih kecil dari data sebenarnya walau baris
  // transaksi sudah sama antar-device.
  await db.rebuildStaleSummariesInRange(range.start, range.end);
  final summaries = await db.getDailySummaries(range.start, range.end);
  final expenses = await db.getNetProfitExpenseTotal(range.start, range.end);

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return dataAsync.when(
      data: (data) => ListView(
        // Akar masalah "jarak" yang dilaporkan user sebenarnya BUKAN padding
        // ini, melainkan TabBar(isScrollable: true) default Material 3
        // (tabAlignment: startOffset) yang menambah inset ~52dp sebelum tab
        // pertama — sudah diperbaiki di laporan_screen.dart (tabAlignment:
        // TabAlignment.start). Padding di sini dikembalikan ke nilai normal.
        padding: const EdgeInsets.all(16),
        children: [
          ReportHero(
            label: 'Laba Bersih',
            value: formatRupiah(data.netProfit),
            sub: '${data.txCount} transaksi',
            negative: data.netProfit < 0,
          ),
          const SizedBox(height: 12),
          _KpiRow(items: [
            _KpiItem('Omzet', formatRupiah(data.revenue), Icons.payments_rounded,
                AppTheme.changeFg(isDark), AppTheme.changeBg(isDark), null),
            _KpiItem('HPP', formatRupiah(data.cogs), Icons.inventory_2_rounded,
                AppTheme.scanFg(isDark), AppTheme.scanBg(isDark), null),
          ]),
          const SizedBox(height: 12),
          _KpiRow(items: [
            _KpiItem(
                'Laba Kotor',
                formatRupiah(data.profit),
                Icons.trending_up_rounded,
                AppTheme.changeFg(isDark),
                AppTheme.changeBg(isDark),
                data.profit >= 0 ? null : AppTheme.debtFg(isDark)),
            _KpiItem(
                'Pengeluaran',
                formatRupiah(data.expenses),
                Icons.north_east_rounded,
                AppTheme.debtFg(isDark),
                AppTheme.debtBg(isDark),
                data.expenses > 0 ? AppTheme.debtFg(isDark) : null),
          ]),
          const SizedBox(height: 12),
          // Selisih Kas Operasional = Omzet - Pengeluaran (TANPA kurangi
          // HPP) — beda dari Laba Bersih, jadi disendirikan barisnya biar
          // tak tertukar maknanya.
          _KpiRow(items: [
            _KpiItem(
                'Selisih Kas Operasional',
                formatRupiah(data.cashDifference),
                Icons.account_balance_wallet_rounded,
                AppTheme.antrianFg(isDark),
                AppTheme.antrianBg(isDark),
                data.cashDifference >= 0 ? null : AppTheme.debtFg(isDark)),
            _KpiItem('Transaksi', '${data.txCount}', Icons.receipt_long_rounded,
                AppTheme.riwayatFg(isDark), AppTheme.riwayatBg(isDark), null),
          ]),
          const SizedBox(height: 22),

          // Payment breakdown
          if (data.byMethod.isNotEmpty) ...[
            Text('Metode Pembayaran',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            if (data.byMethod.length >= 2)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child:
                      _PaymentDonut(byMethod: data.byMethod, total: data.revenue),
                ),
              ),
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
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // Daily chart
          if (data.daily.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('Penjualan Harian',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
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
    return AppDonut(
      size: 160,
      showLegend: false,
      slices: [
        for (final e in byMethod.entries)
          DonutSlice(_methodLabel(e.key), e.value, _methodColor(e.key, scheme),
              _methodOnColor(e.key, scheme)),
      ],
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.items});
  final List<_KpiItem> items;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: ReportKpiCard(
                label: items[i].label,
                value: items[i].value,
                icon: items[i].icon,
                fg: items[i].fg,
                bg: items[i].bg,
                valueColor: items[i].valueColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KpiItem {
  const _KpiItem(
      this.label, this.value, this.icon, this.fg, this.bg, this.valueColor);
  final String label;
  final String value;
  final IconData icon;
  final Color fg;
  final Color bg;
  final Color? valueColor;
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.daily});
  final Map<DateTime, int> daily;

  @override
  Widget build(BuildContext context) {
    final sorted = daily.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final scheme = Theme.of(context).colorScheme;
    // Susulan (permintaan user): ganti bar-per-hari (label tanggal tumpuk di
    // hari-hari akhir/rentang panjang, sama persis akar masalah yang sudah
    // diperbaiki di `StatsTrendChart` — lihat dok di sana) dgn chart garis
    // yang sama, dipakai ulang bukan reimplementasi baru.
    final points = <TrendPoint>[
      for (final e in sorted) (date: e.key, value: e.value),
    ];
    return StatsTrendChart(
      points: points,
      color: scheme.primary,
      valueLabel: (v) => formatRupiah(v.toInt()),
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

  /// Selisih Kas Operasional = Omzet − Pengeluaran (TANPA kurangi HPP).
  /// Berbeda dari Laba Bersih (yang sudah menghitung modal barang terjual)
  /// — metrik ini murni kas masuk (penjualan) dikurangi kas keluar
  /// (pengeluaran operasional), berguna sbg gambaran arus kas sederhana
  /// terlepas dari akurasi harga pokok yang ter-input.
  int get cashDifference => revenue - expenses;
}
