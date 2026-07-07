import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_formatters.dart';

final _transaksiTabProvider =
    StreamProvider.family<List<Transaction>, DateTimeRange>((ref, range) {
  final db = ref.watch(databaseProvider);
  return db.watchTransactions(from: range.start, to: range.end);
});

class TransaksiTab extends ConsumerWidget {
  const TransaksiTab({super.key, required this.range});
  final DateTimeRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(_transaksiTabProvider(range));
    final scheme = Theme.of(context).colorScheme;

    return txAsync.when(
      data: (txList) {
        if (txList.isEmpty) {
          return Center(
            child: Text(
              'Tidak ada transaksi pada periode ini',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: txList.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => _TxTile(tx: txList[i]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _TxTile extends ConsumerWidget {
  const _TxTile({required this.tx});
  final Transaction tx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isVoid = tx.status == 'void';
    final isKurang = tx.status == 'kurang_bayar' || tx.status == 'tempo';

    Color statusColor;
    String statusLabel;
    if (isVoid) {
      statusColor = scheme.error;
      statusLabel = 'VOID';
    } else if (isKurang) {
      statusColor = scheme.tertiary;
      statusLabel = tx.status == 'tempo' ? 'TEMPO' : 'KURANG';
    } else {
      statusColor = scheme.primary;
      statusLabel = 'LUNAS';
    }

    return ListTile(
      title: Row(
        children: [
          Text(tx.localId, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                  fontSize: 9,
                  color: statusColor,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Text(
            _fmtTime(tx.createdAt),
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          if (tx.customerId != null || tx.customerName != null) ...[
            const SizedBox(width: 8),
            _CustomerLabel(tx: tx),
          ],
        ],
      ),
      trailing: Text(
        formatRupiah(tx.total),
        style: TextStyle(
          color: isVoid ? scheme.onSurfaceVariant : scheme.primary,
          fontWeight: FontWeight.w600,
          decoration: isVoid ? TextDecoration.lineThrough : null,
        ),
      ),
      onTap: () => _showTxDetail(context, ref, tx),
    );
  }

  String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  void _showTxDetail(BuildContext context, WidgetRef ref, Transaction tx) {
    final isVoid = tx.status == 'void';
    final isKurang =
        tx.status == 'kurang_bayar' || tx.status == 'tempo';
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => Column(
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
                  Text(tx.localId,
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (!isVoid)
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: scheme.error),
                      tooltip: 'Void',
                      onPressed: () => _confirmVoid(ctx, ref, tx),
                    ),
                  if (isKurang)
                    IconButton(
                      icon: const Icon(Icons.payments_outlined),
                      tooltip: 'Tambah Bayar',
                      onPressed: () => _tambahBayar(ctx, ref, tx),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                children: [
                  _InfoRow('Total', formatRupiah(tx.total)),
                  _InfoRow('Dibayar', formatRupiah(tx.paid)),
                  if (isKurang)
                    _InfoRow('Sisa Tagihan',
                        formatRupiah(tx.total - tx.paid),
                        color: scheme.error),
                  _InfoRow('Metode', _methodLabel(tx.paymentMethod)),
                  _InfoRow(
                    'Waktu',
                    '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year} ${tx.createdAt.hour.toString().padLeft(2, '0')}:${tx.createdAt.minute.toString().padLeft(2, '0')}',
                  ),
                  if (tx.kasirId != null) _InfoRow('Kasir', tx.kasirId!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmVoid(
      BuildContext ctx, WidgetRef ref, Transaction tx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Void Transaksi?'),
        content: Text(
            'Stok akan dikembalikan. Loyalitas akan dibalik.\nTransaksi: ${tx.localId}'),
        actions: [
          TextButton(onPressed: () => d.pop(false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(d).colorScheme.error),
            onPressed: () => d.pop(true),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final db = ref.read(databaseProvider);
      final device = ref.read(deviceProvider);
      await db.voidTransaction(tx.id, device.deviceCode);
      if (ctx.mounted) Navigator.of(ctx).pop();
    }
  }

  Future<void> _tambahBayar(
      BuildContext ctx, WidgetRef ref, Transaction tx) async {
    final remaining = tx.total - tx.paid;
    final ctrl = TextEditingController();
    final result = await showDialog<int>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Tambah Bayar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sisa tagihan: ${formatRupiah(remaining)}'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              // Konsisten dengan dialog bayar lain — tanpa formatter, input
              // "10.000" gagal di-parse diam-diam dan tidak terjadi apa-apa.
              inputFormatters: const [ThousandsSeparatorFormatter()],
              decoration: const InputDecoration(
                  prefixText: 'Rp ', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => d.pop(), child: const Text('Batal')),
          FilledButton(
            onPressed: () =>
                d.pop(ThousandsSeparatorFormatter.parseValue(ctrl.text)),
            child: const Text('Bayar'),
          ),
        ],
      ),
    );

    if (result != null && result > 0) {
      final db = ref.read(databaseProvider);
      final device = ref.read(deviceProvider);
      // Satu jalur DB yang sama dengan Tambah Bayar di struk & riwayat:
      // paid penuh + status + kembalian dihitung di addPaymentToTransaction.
      await db.addPaymentToTransaction(
        txId: tx.id,
        amount: result,
        method: 'tunai',
        kasirId: device.deviceCode,
      );
      if (ctx.mounted) Navigator.of(ctx).pop();
    }
  }

  String _methodLabel(String m) => switch (m) {
        'tunai' => 'Tunai',
        'transfer' => 'Transfer',
        'qris' => 'QRIS',
        'ewallet' => 'E-Wallet',
        'tempo' => 'Tempo',
        _ => m,
      };
}

class _CustomerLabel extends ConsumerWidget {
  const _CustomerLabel({required this.tx});
  final Transaction tx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (tx.customerId != null) {
      return FutureBuilder<Customer?>(
        future: (ref.read(databaseProvider).select(
                  ref.read(databaseProvider).customers)
                ..where((t) => t.id.equals(tx.customerId!)))
            .getSingleOrNull(),
        builder: (ctx, snap) {
          final name = snap.data?.name ?? '…';
          return Text(
            name,
            style: TextStyle(
                fontSize: 11,
                color: scheme.primary,
                fontWeight: FontWeight.w600),
          );
        },
      );
    }
    final name = tx.customerName ?? 'Umum';
    return Text(
      name,
      style: TextStyle(
          fontSize: 11,
          color: scheme.onSurfaceVariant,
          fontStyle: tx.customerName == null
              ? FontStyle.italic
              : FontStyle.normal),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: scheme.onSurfaceVariant, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontSize: 13)),
        ],
      ),
    );
  }
}
