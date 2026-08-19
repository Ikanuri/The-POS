import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/chart_utils.dart';

/// Tab Arus Kas — uang yang BENAR-BENAR berpindah dalam rentang.
///
/// Sengaja BEDA dari kartu "Selisih Kas Operasional" di tab Ringkasan
/// (Omzet - Pengeluaran), yang bukan arus kas karena omzet memuat nota
/// tempo yang belum dibayar dan pelunasan hutang tidak jatuh di tanggal
/// uangnya diterima. Lihat dok [AppDatabase.getCashInByMethod].
final _cashFlowProvider =
    FutureProvider.family<_CashFlowData, DateTimeRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final summary = await db.getCashFlowSummary(range.start, range.end);
  final daily = await db.getCashFlowDaily(range.start, range.end);
  return (summary: summary, daily: daily);
});

typedef _CashFlowData = ({
  CashFlowSummary summary,
  List<CashFlowDaily> daily,
});

// Kunci di sini adalah nilai MENTAH `transaction_payments.method`
// (`getCashInByMethod` GROUP BY langsung dari kolom itu) — 'bank', bukan
// 'transfer'. String 'transfer' tidak pernah ada di data nyata (lihat dok
// `AppDatabase._paymentBucket`); dulu key ini salah, jadi metode Transfer
// Bank tampil sbg "bank" mentah (fallback `?? e.key`) di tab Arus Kas.
const _methodLabels = {
  'tunai': 'Tunai',
  'bank': 'Transfer',
  'qris': 'QRIS',
  'ewallet': 'E-Wallet',
  'retur': 'Retur (kembalian)',
  'edit': 'Koreksi item (kembalian)',
};

const _expenseTypeLabels = {
  'daily_expense': 'Operasional',
  'owner_withdrawal': 'Ambil Pribadi (Owner)',
  'supplier_payment': 'Bayar Supplier',
  'change_given': 'Uang Keluar Laci',
};

class ArusKasTab extends ConsumerWidget {
  const ArusKasTab({super.key, required this.range});
  final DateTimeRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(_cashFlowProvider(range));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (d) {
        final s = d.summary;
        final totalIn = s.cashIn + s.nonCashIn;
        final net = totalIn - s.cashOut;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(
                  child: _Tile(
                      label: 'Kas masuk',
                      value: totalIn,
                      color: scheme.tertiary)),
              const SizedBox(width: 8),
              Expanded(
                  child: _Tile(
                      label: 'Kas keluar',
                      value: s.cashOut,
                      color: scheme.error)),
            ]),
            const SizedBox(height: 8),
            _Tile(
              label: 'Arus kas bersih',
              value: net,
              color: net >= 0 ? scheme.tertiary : scheme.error,
              big: true,
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              color: scheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Dihitung dari uang yang BENAR-BENAR berpindah pada '
                  'rentang ini: nota tempo yang belum dibayar tidak dihitung, '
                  'dan pelunasan hutang nota lama dihitung di tanggal '
                  'uangnya diterima. Kembalian yang diserahkan sudah '
                  'dikurangkan.',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            const _SectionTitle('Rincian kas masuk'),
            _Row(label: 'Tunai', value: s.cashIn),
            _Row(label: 'Non-tunai', value: s.nonCashIn),
            if (s.inByMethod.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final e in _sorted(s.inByMethod))
                if (e.key != 'tempo')
                  _Row(
                    label: '  ${_methodLabels[e.key] ?? e.key}',
                    value: e.value,
                    dim: true,
                  ),
            ],
            const _SectionTitle('Rincian kas keluar'),
            if (s.outByType.isEmpty)
              Text('Tidak ada pengeluaran di rentang ini',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant))
            else
              for (final e in _sorted(s.outByType))
                _Row(
                  label: _expenseTypeLabels[e.key] ?? e.key,
                  value: e.value,
                  color: scheme.error,
                ),
            if (d.daily.isNotEmpty) ...[
              const _SectionTitle('Tren harian'),
              _CashFlowChart(daily: d.daily),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Legend(color: scheme.tertiary, label: 'Masuk'),
                  const SizedBox(width: 16),
                  _Legend(color: scheme.error, label: 'Keluar'),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  static List<MapEntry<String, int>> _sorted(Map<String, int> m) =>
      m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.color,
    this.big = false,
  });
  final String label;
  final int value;
  final Color color;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              formatRupiah(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.numStyle(context,
                  size: big ? 20 : 15,
                  weight: FontWeight.w700,
                  color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.color,
    this.dim = false,
  });
  final String label;
  final int value;
  final Color? color;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: dim ? 11 : 12,
                    color: dim ? scheme.onSurfaceVariant : null)),
          ),
          Text(
            formatRupiah(value),
            style: AppTheme.numStyle(context,
                size: dim ? 11 : 13,
                weight: dim ? FontWeight.w500 : FontWeight.w600,
                color: color),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}

/// Batang berpasangan masuk/keluar per hari — skala bar dibagi bersama
/// (nilai maksimum dari KEDUA seri) supaya tinggi masuk vs keluar bisa
/// dibandingkan langsung secara visual.
class _CashFlowChart extends StatelessWidget {
  const _CashFlowChart({required this.daily});
  final List<CashFlowDaily> daily;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = daily
        .expand((e) => [e.cashIn, e.cashOut])
        .fold<int>(0, (a, b) => a > b ? a : b);
    final total = daily.length;

    return Column(
      children: [
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: daily.map((e) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Tooltip(
                    message: '${e.date.day}/${e.date.month}\n'
                        'Masuk: ${formatRupiah(e.cashIn)}\n'
                        'Keluar: ${formatRupiah(e.cashOut)}',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Container(
                            height: clampedBarHeight(e.cashIn, max),
                            decoration: BoxDecoration(
                              color: scheme.tertiary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(width: 1),
                        Expanded(
                          child: Container(
                            height: clampedBarHeight(e.cashOut, max),
                            decoration: BoxDecoration(
                              color: scheme.error,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: daily.asMap().entries.map((entry) {
            final i = entry.key;
            final date = entry.value.date;
            final show = total <= 7
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
                style:
                    TextStyle(fontSize: 8, color: scheme.onSurfaceVariant),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
