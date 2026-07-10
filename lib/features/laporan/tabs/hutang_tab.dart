import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../kasir/widgets/debt_payment_dialog.dart';

final _debtBookProvider =
    FutureProvider.autoDispose<List<DebtBookEntry>>((ref) {
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

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Cari nama pelanggan',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (all.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${all.length} pelanggan berhutang',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
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
                  ? Center(
                      child: Text(
                          all.isEmpty
                              ? 'Tidak ada hutang. 🎉'
                              : 'Tidak ada pelanggan cocok.',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    )
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = list[i];
                        final days = e.daysOverdue;
                        return ListTile(
                          title: Text(e.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            'menunggak $days hari · ${e.count} nota',
                            style: TextStyle(
                                fontSize: 12,
                                color: _overdueColor(days, isDark),
                                fontWeight: FontWeight.w600),
                          ),
                          trailing: Text(formatRupiah(e.debt),
                              style: AppTheme.numStyle(context,
                                  size: 15,
                                  weight: FontWeight.w700,
                                  color: AppTheme.debtFg(isDark))),
                          onTap: () => _showDetail(e),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDetail(DebtBookEntry e) async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  Text('Total hutang (${e.count} nota)'),
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _lunasi(DebtBookEntry e) async {
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDebtPaymentDialog(context, db,
        remaining: e.debt, title: 'Lunasi Hutang ${e.name}');
    if (result == null || result.amount <= 0) return;

    final txIds = await db.getUnpaidTxIds(e.customerId);
    final (applied, change) = await db.settleMergedDebt(
      txIds: txIds,
      amount: result.amount,
      method: result.method,
      kasirId: device.deviceCode,
    );
    ref.invalidate(_debtBookProvider);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(change > 0
          ? 'Terbayar ${formatRupiah(applied)}, kembalian ${formatRupiah(change)}'
          : 'Terbayar ${formatRupiah(applied)}'),
    ));
  }
}
