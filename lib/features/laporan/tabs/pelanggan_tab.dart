import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';

final _pelangganTabProvider =
    FutureProvider.family<List<_CustStat>, DateTimeRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final txList = await (db.select(db.transactions)
        ..where((t) =>
            t.status.isNotValue('void') &
            t.customerId.isNotNull() &
            t.createdAt.isBiggerOrEqualValue(range.start) &
            t.createdAt.isSmallerOrEqualValue(range.end)))
      .get();

  final stats = <String, _CustStat>{};
  for (final tx in txList) {
    if (tx.customerId == null) continue;
    final s = stats.putIfAbsent(tx.customerId!, () => _CustStat(tx.customerId!));
    s.txCount++;
    s.totalSpent += tx.total;
  }

  final sorted = stats.values.toList()
    ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));

  for (final s in sorted) {
    final c = await (db.select(db.customers)
          ..where((t) => t.id.equals(s.customerId)))
        .getSingleOrNull();
    if (c != null) {
      s.name = c.name;
      s.loyaltyPoints = c.loyaltyPoints;
    }
  }

  return sorted;
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
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: stats.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
          itemBuilder: (_, i) {
            final s = stats[i];
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
                style: TextStyle(
                    color: scheme.primary, fontWeight: FontWeight.w600),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _CustStat {
  _CustStat(this.customerId);
  final String customerId;
  String name = '';
  int txCount = 0;
  int totalSpent = 0;
  int loyaltyPoints = 0;
}
