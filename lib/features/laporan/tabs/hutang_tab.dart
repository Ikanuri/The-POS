import '../../../core/theme/app_style.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/app_empty_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/data_refresh_provider.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../kasir/widgets/debt_payment_sheet.dart';
import '../../../core/theme/app_overlays.dart';

final _debtBookProvider =
    FutureProvider.autoDispose<List<DebtBookEntry>>((ref) {
  // Lihat dok `dataSyncedTickProvider` — provider ini tidak reaktif thd DB.
  ref.watch(dataSyncedTickProvider);
  final db = ref.watch(databaseProvider);
  return db.getDebtBook();
});

/// Item 12 — Buku Hutang terpusat: daftar pelanggan berhutang, diurut dari
/// yang paling lama menunggak, dengan aksi Lunasi langsung.
class HutangTab extends ConsumerStatefulWidget {
  const HutangTab({super.key});

  @override
  ConsumerState<HutangTab> createState() => _HutangTabState();
}

class _HutangTabState extends ConsumerState<HutangTab> {
  String _query = '';

  /// Hijau (<7 hari) → kuning (7–29) → merah (≥30) berdasar umur menunggak.
  Color _overdueColor(int days, bool isDark) {
    if (days >= 30) return AppTheme.debtFg(isDark);
    if (days >= 7) return isDark ? const Color(0xFFF0B54A) : const Color(0xFFB8791A);
    return AppTheme.changeFg(isDark);
  }

  @override
  Widget build(BuildContext context) {
    final asyncDebt = ref.watch(_debtBookProvider);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return asyncDebt.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (all) {
        final q = _query.trim().toLowerCase();
        final list = q.isEmpty
            ? all
            : all.where((e) => e.name.toLowerCase().contains(q)).toList();
        final totalDebt = all.fold<int>(0, (s, e) => s + e.debt);

        // Item 83 (permintaan user) — pisahkan pelanggan TERDAFTAR dari
        // pembeli AD-HOC (nama diketik manual/"Umum", tidak punya record
        // `Customers`) jadi 2 section, bukan satu daftar campur.
        final tetap = list.where((e) => !e.isAdhoc).toList();
        final adhoc = list.where((e) => e.isAdhoc).toList();
        final tetapDebt = tetap.fold<int>(0, (s, e) => s + e.debt);
        final adhocDebt = adhoc.fold<int>(0, (s, e) => s + e.debt);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AppStyle.pillSearch(
                context,
                TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Cari nama pelanggan',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ),
            if (all.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('${all.length} pelanggan berhutang',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ),
                    const SizedBox(width: 8),
                    Text('Total ${formatRupiah(totalDebt)}',
                        style: AppTheme.numStyle(context,
                            size: 14,
                            weight: FontWeight.w700,
                            color: AppTheme.debtFg(isDark))),
                  ],
                ),
              ),
            Expanded(
              child: list.isEmpty
                  ? AppEmptyState(
                      all.isEmpty
                          ? 'Tidak ada hutang. 🎉'
                          : 'Tidak ada pelanggan cocok.',
                      icon: Icons.verified_outlined,
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        if (tetap.isNotEmpty)
                          _groupSection(
                            title: 'Pelanggan Tetap',
                            entries: tetap,
                            groupDebt: tetapDebt,
                            isDark: isDark,
                            scheme: scheme,
                          ),
                        if (adhoc.isNotEmpty)
                          _groupSection(
                            title: 'Pembeli Umum (Ad-hoc)',
                            entries: adhoc,
                            groupDebt: adhocDebt,
                            isDark: isDark,
                            scheme: scheme,
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  /// Item 83 — satu section (header + subtotal + daftar), dipakai baik utk
  /// "Pelanggan Tetap" maupun "Pembeli Umum (Ad-hoc)".
  Widget _groupSection({
    required String title,
    required List<DebtBookEntry> entries,
    required int groupDebt,
    required bool isDark,
    required ColorScheme scheme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              Text(formatRupiah(groupDebt),
                  style: AppTheme.numStyle(context,
                      size: 13.5,
                      weight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 68),
                ListTile(
                  leading: CircleAvatar(
                    radius: 19,
                    backgroundColor: AppTheme.debtBg(isDark),
                    child: Text(
                      entries[i].name.isNotEmpty
                          ? entries[i].name.characters.first.toUpperCase()
                          : '?',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.debtFg(isDark)),
                    ),
                  ),
                  title: Text(entries[i].name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'menunggak ${entries[i].daysOverdue} hari · ${entries[i].count} nota',
                    style: TextStyle(
                        fontSize: 12,
                        color: _overdueColor(entries[i].daysOverdue, isDark),
                        fontWeight: FontWeight.w600),
                  ),
                  trailing: Text(formatRupiah(entries[i].debt),
                      style: AppTheme.numStyle(context,
                          size: 15,
                          weight: FontWeight.w700,
                          color: AppTheme.debtFg(isDark))),
                  onTap: () => _showDetail(entries[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showDetail(DebtBookEntry e) async {
    final scheme = Theme.of(context).colorScheme;
    final db = ref.read(databaseProvider);
    final unpaidTx = e.isAdhoc
        ? await db.getUnpaidTxDetailsByCustomerName(e.adhocCustomerName)
        : await db.getUnpaidTxDetails(e.customerId!);
    if (!mounted) return;
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => SafeArea(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Text(e.name,
                  style: Theme.of(context).textTheme.titleMedium),
              if (e.phone != null && e.phone!.isNotEmpty)
                Text(e.phone!,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('Total hutang (${e.count} nota)',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Text(formatRupiah(e.debt),
                      style: AppTheme.numStyle(context,
                          size: 18,
                          weight: FontWeight.w700,
                          color: AppTheme.debtFg(
                              Theme.of(context).brightness == Brightness.dark))),
                ],
              ),
              const SizedBox(height: 4),
              Text('Menunggak sejak ${e.daysOverdue} hari lalu',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Lunasi'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _lunasi(e);
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text('Nota belum lunas',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant)),
              const Divider(height: 12),
              for (final tx in unpaidTx)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(tx.localId,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_formatDate(tx.createdAt),
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant)),
                  trailing: Text(formatRupiah(tx.sisa),
                      style: AppTheme.numStyle(context,
                          size: 13.5,
                          weight: FontWeight.w700,
                          color: AppTheme.debtFg(
                              Theme.of(context).brightness ==
                                  Brightness.dark))),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.push('/kasir/struk/${tx.id}');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _lunasi(DebtBookEntry e) async {
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDebtPaymentSheet(context, db,
        remaining: e.debt, title: 'Lunasi Hutang ${e.name}');
    if (result == null || result.amount <= 0) return;

    final txIds = e.isAdhoc
        ? await db.getUnpaidTxIdsByCustomerName(e.adhocCustomerName)
        : await db.getUnpaidTxIds(e.customerId!);
    final (applied, change) = await db.settleMergedDebt(
      txIds: txIds,
      amount: result.amount,
      method: result.method,
      methodName: result.methodName,
      kasirId: device.deviceCode,
    );
    ref.invalidate(_debtBookProvider);
    if (!mounted) return;
    messenger.showAppSnackBar(SnackBar(
      content: Text(change > 0
          ? 'Terbayar ${formatRupiah(applied)}, kembalian ${formatRupiah(change)}'
          : 'Terbayar ${formatRupiah(applied)}'),
    ));
  }
}
