import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../cart_provider.dart';

const _txUuid = Uuid();

final _recentTxProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.transactions)
        ..where((t) => t.status.isNotValue('void'))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(100))
      .watch();
});

/// Sheet riwayat transaksi di kasir: cari, filter Lunas/Belum Lunas,
/// aksi Lunasi · Tambah Item · Struk.
class TxHistorySheet extends ConsumerStatefulWidget {
  const TxHistorySheet({super.key});

  @override
  ConsumerState<TxHistorySheet> createState() => _TxHistorySheetState();
}

class _TxHistorySheetState extends ConsumerState<TxHistorySheet> {
  String _query = '';
  String _filter = 'semua'; // semua | lunas | hutang
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(_recentTxProvider);
    final scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Riwayat Transaksi',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Cari pelanggan atau no. transaksi…',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final (id, label) in [
                  ('semua', 'Semua'),
                  ('lunas', 'Lunas'),
                  ('hutang', 'Belum Lunas'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: _filter == id,
                      onSelected: (_) => setState(() => _filter = id),
                      visualDensity: VisualDensity.compact,
                      selectedColor: scheme.primaryContainer,
                      side: BorderSide.none,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1),
          Expanded(
            child: txAsync.when(
              data: (txs) {
                final filtered = txs.where((tx) {
                  if (_filter == 'lunas' && tx.status != 'lunas') return false;
                  if (_filter == 'hutang' &&
                      tx.status != 'kurang_bayar' &&
                      tx.status != 'tempo') {
                    return false;
                  }
                  if (_query.isEmpty) return true;
                  final q = _query.toLowerCase();
                  return tx.localId.toLowerCase().contains(q) ||
                      (tx.customerName?.toLowerCase().contains(q) ?? false);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text('Tidak ada transaksi.',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 13)),
                  );
                }
                return ListView.separated(
                  controller: scrollCtrl,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _TxRow(
                    tx: filtered[i],
                    expanded: _expandedId == filtered[i].id,
                    onToggle: () => setState(() => _expandedId =
                        _expandedId == filtered[i].id ? null : filtered[i].id),
                  ),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _TxRow extends ConsumerWidget {
  const _TxRow({
    required this.tx,
    required this.expanded,
    required this.onToggle,
  });

  final Transaction tx;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isHutang = tx.status == 'kurang_bayar' || tx.status == 'tempo';
    final time =
        '${tx.createdAt.hour.toString().padLeft(2, '0')}:${tx.createdAt.minute.toString().padLeft(2, '0')}';

    return Column(
      children: [
        ListTile(
          dense: true,
          title: Row(
            children: [
              Text(tx.localId,
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _customerLabel(tx),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          subtitle: Text(time, style: const TextStyle(fontSize: 11)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatRupiah(tx.total),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isHutang
                      ? scheme.errorContainer
                      : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isHutang ? 'Belum Lunas' : 'Lunas',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isHutang
                        ? scheme.onErrorContainer
                        : scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          onTap: onToggle,
        ),
        if (expanded) _TxDetail(tx: tx),
      ],
    );
  }

  String _customerLabel(Transaction tx) {
    if (tx.customerName != null) return tx.customerName!;
    if (tx.customerId != null) return 'Pelanggan';
    return 'Umum';
  }
}

class _TxDetail extends ConsumerWidget {
  const _TxDetail({required this.tx});
  final Transaction tx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isHutang = tx.status == 'kurang_bayar' || tx.status == 'tempo';

    return Container(
      color: scheme.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isHutang)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Dibayar: ${formatRupiah(tx.paid)}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                  Text('Sisa ${formatRupiah(tx.total - tx.paid)}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.error)),
                ],
              ),
            ),
          Row(
            children: [
              if (isHutang) ...[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _lunasi(context, ref),
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: const Text('Lunasi',
                        style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _tambahItem(context, ref),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Tambah Item',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/kasir/struk/${tx.id}');
                  },
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label:
                      const Text('Struk', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _lunasi(BuildContext context, WidgetRef ref) async {
    final remaining = tx.total - tx.paid;
    final ctrl = TextEditingController(text: remaining.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lunasi Transaksi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sisa tagihan: ${formatRupiah(remaining)}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  prefixText: 'Rp ', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(ctrl.text)),
            child: const Text('Bayar'),
          ),
        ],
      ),
    );

    if (result == null || result <= 0 || !context.mounted) return;
    final payment = result.clamp(1, remaining);

    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
            id: _txUuid.v4(),
            transactionId: tx.id,
            amount: payment,
            method: 'tunai',
            paidAt: Value(DateTime.now()),
            kasirId: Value(device.deviceCode),
          ),
        );
    final newPaid = tx.paid + payment;
    await (db.update(db.transactions)..where((t) => t.id.equals(tx.id)))
        .write(TransactionsCompanion(
      paid: Value(newPaid),
      status: Value(newPaid >= tx.total ? 'lunas' : 'kurang_bayar'),
    ));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newPaid >= tx.total
              ? '${tx.localId} lunas'
              : 'Pembayaran dicatat, sisa ${formatRupiah(tx.total - newPaid)}')));
    }
  }

  void _tambahItem(BuildContext context, WidgetRef ref) {
    final name = tx.customerName ?? (tx.customerId != null ? null : 'Umum');
    ref.read(prefillCustomerProvider.notifier).state =
        name == 'Umum' ? null : name;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Tambahkan item untuk ${name ?? 'pelanggan'} — pelanggan terisi otomatis saat bayar')));
  }
}
