import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/input_formatters.dart';

const _idMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
];
String _fmtTgl(String yyyymmdd) {
  final p = yyyymmdd.split('-');
  if (p.length != 3) return yyyymmdd;
  return '${int.parse(p[2])} ${_idMonths[int.parse(p[1]) - 1]} ${p[0]}';
}

String _todayKey() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

final _todayRecapProvider =
    FutureProvider.autoDispose<({int cash, int nonCash, int txCount})>((ref) {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day);
  return ref.watch(databaseProvider).getTodayCashRecap(from, now);
});

final _closingHistoryProvider =
    StreamProvider.autoDispose<List<CashClosing>>((ref) {
  return ref.watch(databaseProvider).watchCashClosings();
});

/// Item 15 — Tutup Kasir harian: rekap kas sistem vs fisik, hitung selisih,
/// simpan satu entri per device per hari + riwayat.
class TutupKasirScreen extends ConsumerStatefulWidget {
  const TutupKasirScreen({super.key});

  @override
  ConsumerState<TutupKasirScreen> createState() => _TutupKasirScreenState();
}

class _TutupKasirScreenState extends ConsumerState<TutupKasirScreen> {
  final _physicalCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _physicalCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(int systemCash, int nonCash, int txCount) async {
    final physical = ThousandsSeparatorFormatter.parseValue(_physicalCtrl.text);
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final date = _todayKey();
    await db.saveCashClosing(CashClosingsCompanion(
      id: Value('${date}_${device.deviceCode}'), // deterministik → upsert/hari
      date: Value(date),
      deviceCode: Value(device.deviceCode),
      systemCash: Value(systemCash),
      systemNonCash: Value(nonCash),
      txCount: Value(txCount),
      physicalCash: Value(physical),
      difference: Value(physical - systemCash),
      note: Value(_noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim()),
    ));
    ref.invalidate(_closingHistoryProvider);
    if (!mounted) return;
    messenger.showSnackBar(
        const SnackBar(content: Text('Tutup kasir tersimpan')));
    _physicalCtrl.clear();
    _noteCtrl.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final recapAsync = ref.watch(_todayRecapProvider);
    final historyAsync = ref.watch(_closingHistoryProvider);

    final physical = ThousandsSeparatorFormatter.parseValue(_physicalCtrl.text);

    return Scaffold(
      appBar: AppBar(title: const Text('Tutup Kasir')),
      body: recapAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (recap) {
          final diff = physical - recap.cash;
          final diffColor = diff == 0
              ? AppTheme.changeFg(isDark)
              : (diff < 0 ? AppTheme.debtFg(isDark) : scheme.tertiary);
          final diffLabel = diff == 0
              ? 'Pas'
              : (diff < 0 ? 'Kurang ${formatRupiah(-diff)}' : 'Lebih ${formatRupiah(diff)}');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rekap Hari Ini (${_fmtTgl(_todayKey())})',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 12),
                      _row('Penjualan tunai', formatRupiah(recap.cash), scheme),
                      _row('Non-tunai', formatRupiah(recap.nonCash), scheme),
                      _row('Jumlah nota', '${recap.txCount}', scheme),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _physicalCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: const [ThousandsSeparatorFormatter()],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Uang Fisik di Laci',
                  prefixText: 'Rp ',
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: diffColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Selisih (fisik − sistem)'),
                    Text(diffLabel,
                        style: AppTheme.numStyle(context,
                            size: 18,
                            weight: FontWeight.w700,
                            color: diffColor)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    _save(recap.cash, recap.nonCash, recap.txCount),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Simpan Tutup Kasir'),
              ),
              const SizedBox(height: 24),
              Text('Riwayat', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              historyAsync.maybeWhen(
                data: (list) => list.isEmpty
                    ? Text('Belum ada riwayat tutup kasir.',
                        style: TextStyle(color: scheme.onSurfaceVariant))
                    : Column(
                        children: [
                          for (final c in list)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(_fmtTgl(c.date)),
                              subtitle: Text(
                                  'Sistem ${formatRupiah(c.systemCash)} · '
                                  'Fisik ${formatRupiah(c.physicalCash)}'),
                              trailing: Text(
                                c.difference == 0
                                    ? 'Pas'
                                    : (c.difference < 0
                                        ? '−${formatRupiah(-c.difference)}'
                                        : '+${formatRupiah(c.difference)}'),
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: c.difference == 0
                                        ? AppTheme.changeFg(isDark)
                                        : (c.difference < 0
                                            ? AppTheme.debtFg(isDark)
                                            : scheme.tertiary)),
                              ),
                            ),
                        ],
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
            Text(value,
                style: AppTheme.numStyle(context,
                    size: 14, weight: FontWeight.w600)),
          ],
        ),
      );
}
