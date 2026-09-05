import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';

final _transaksiTabProvider =
    StreamProvider.family<List<Transaction>, DateTimeRange>((ref, range) {
  final db = ref.watch(databaseProvider);
  // includeVoid: true — transaksi void HARUS tetap terlihat di laporan
  // (dulu difilter di sini, bikin badge VOID yang sudah ada di _TxTile
  // tidak pernah terpicu). Beda dari pemanggil lain watchTransactions
  // (ekspor, dll) yang TETAP default false.
  return db.watchTransactions(
      from: range.start, to: range.end, includeVoid: true);
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

  /// Dulu sheet ringkasan tipis (Total/Dibayar/Metode/Waktu/Kasir) dgn
  /// tombol Void/Tambah Bayar sendiri (`_confirmVoid`/`_tambahBayar`,
  /// dialog bespoke TERPISAH dari `showVoidTransactionDialog` bersama).
  /// Diganti navigasi ke `ReceiptScreen` (struk asli lengkap: item, harga,
  /// pelanggan) — screen itu SUDAH py tombol Batalkan/Tambah Bayar
  /// terintegrasi (pola sama `tx_history_sheet.dart`), jadi tombol
  /// bespoke di sheet lama ini jadi dead code & dihapus.
  void _showTxDetail(BuildContext context, WidgetRef ref, Transaction tx) {
    context.push('/kasir/struk/${tx.id}');
  }
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
