import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';

final _produkTabProvider =
    FutureProvider.family<List<_ProdukStat>, DateTimeRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final txList = await (db.select(db.transactions)
        ..where((t) =>
            t.status.isNotValue('void') &
            t.createdAt.isBiggerOrEqualValue(range.start) &
            t.createdAt.isSmallerOrEqualValue(range.end)))
      .get();

  final stats = <String, _ProdukStat>{};
  for (final tx in txList) {
    final items = await (db.select(db.transactionItems)
          ..where((t) => t.transactionId.equals(tx.id)))
        .get();
    for (final item in items) {
      final s = stats.putIfAbsent(item.productId, () => _ProdukStat(item.productId));
      s.sold += item.qty;
      s.revenue += item.subtotal;
      s.cogs += (item.costAtSale * item.qty).round();
    }
  }

  final sorted = stats.values.toList()
    ..sort((a, b) => b.revenue.compareTo(a.revenue));

  for (final s in sorted) {
    final p = await (db.select(db.products)
          ..where((t) => t.id.equals(s.productId)))
        .getSingleOrNull();
    if (p != null) s.name = p.name;
  }

  return sorted;
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
          return Center(
            child: Text('Tidak ada data untuk periode ini',
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
                backgroundColor: i == 0 ? scheme.primary : scheme.surfaceContainerHighest,
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
                '${s.sold % 1 == 0 ? s.sold.toInt() : s.sold} terjual · Laba: ${formatRupiah(s.revenue - s.cogs)}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              trailing: Text(
                formatRupiah(s.revenue),
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

class _ProdukStat {
  _ProdukStat(this.productId);
  final String productId;
  String name = '';
  double sold = 0;
  int revenue = 0;
  int cogs = 0;
}
