import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';

/// PLAN Item 90 tahap 6 (keputusan user: "riwayat saja") — daftar pembelian
/// yang pernah dicatat lewat Penerimaan Barang, detail per baris (HPP lama ->
/// baru, PPN masukan), tombol Batalkan, dan (owner) Setujui/Tolak usulan HPP
/// dari HP pegawai.

const _bulan = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', //
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// Tanggal pendek Indonesia — dibentuk manual (DateFormat ber-locale meledak,
/// lihat gotcha CLAUDE.md).
String purchaseDateLabel(DateTime d) =>
    '${d.day} ${_bulan[d.month - 1]} ${d.year}';

/// Label status pembelian utk pengguna.
String purchaseStatusLabel(String status) => switch (status) {
      'received' => 'Diterapkan',
      'pending' => 'Menunggu persetujuan HPP',
      'cost_rejected' => 'HPP ditolak',
      'void' => 'Dibatalkan',
      _ => status,
    };

Color _statusColor(String status, ColorScheme scheme) => switch (status) {
      'received' => scheme.tertiary,
      'pending' => Colors.amber.shade800,
      'void' => scheme.error,
      _ => scheme.onSurfaceVariant,
    };

final _purchasesProvider = StreamProvider<List<Purchase>>(
    (ref) => ref.watch(databaseProvider).watchPurchases());

class PurchaseHistoryScreen extends ConsumerWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(_purchasesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Pembelian')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Belum ada pembelian tercatat'))
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final p = list[i];
                  final at = p.invoiceDate ?? p.createdAt;
                  return ListTile(
                    key: ValueKey('purchase-${p.id}'),
                    title: Text(
                      [
                        if ((p.invoiceNo ?? '').isNotEmpty) p.invoiceNo!,
                        if ((p.supplierName ?? '').isNotEmpty) p.supplierName!,
                        if ((p.invoiceNo ?? '').isEmpty &&
                            (p.supplierName ?? '').isEmpty)
                          'Penerimaan barang',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${purchaseDateLabel(at)} · '
                      '${purchaseStatusLabel(p.status)}',
                      style: TextStyle(
                          fontSize: 12, color: _statusColor(p.status, scheme)),
                    ),
                    trailing: Text(formatRupiah(p.total),
                        style: AppTheme.numStyle(context, size: 14)),
                    onTap: () => showPurchaseDetailSheet(context, ref, p),
                  );
                },
              ),
      ),
    );
  }
}

/// Lembar detail satu pembelian — dipakai riwayat & bagian "Menunggu
/// persetujuan" di Penerimaan Barang.
Future<void> showPurchaseDetailSheet(
    BuildContext context, WidgetRef ref, Purchase p) async {
  final db = ref.read(databaseProvider);
  final device = ref.read(deviceProvider);
  final items = await db.getPurchaseItemsWithLabels(p.id);
  if (!context.mounted) return;
  final scheme = Theme.of(context).colorScheme;
  final isOwner = device.isOwner;
  final ownPending = p.status == 'pending' && p.kasirId == device.deviceCode;
  final canVoid = p.status != 'void' && (isOwner || ownPending);

  String n(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          children: [
            Text(
              (p.invoiceNo ?? '').isEmpty ? 'Pembelian' : 'Faktur ${p.invoiceNo}',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              [
                if ((p.supplierName ?? '').isNotEmpty) p.supplierName!,
                purchaseDateLabel(p.invoiceDate ?? p.createdAt),
                purchaseStatusLabel(p.status),
              ].join(' · '),
              style: TextStyle(
                  fontSize: 12, color: _statusColor(p.status, scheme)),
            ),
            const Divider(height: 20),
            for (final x in items) ...[
              Text(x.productName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${n(x.item.qty)} ${x.unitName} × '
                '${formatRupiah(x.item.pricePerUnit)}'
                '${x.item.discount > 0 ? ' − ${formatRupiah(x.item.discount)}' : ''}'
                ' = ${formatRupiah(x.item.subtotal)}',
                style: const TextStyle(fontSize: 12),
              ),
              if (x.item.costAfter != null)
                Text(
                  'HPP ${p.status == 'received' ? '' : 'usulan '}per satuan '
                  'dasar: ${formatRupiah(x.item.costBefore ?? 0)} → '
                  '${formatRupiah(x.item.costAfter!)}',
                  key: ValueKey('purchase-item-cost-${x.item.id}'),
                  style: TextStyle(fontSize: 12, color: scheme.primary),
                ),
              if (x.item.inputTax > 0)
                Text('PPN masukan ${formatRupiah(x.item.inputTax)}',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
            ],
            const Divider(height: 12),
            _row('Total', formatRupiah(p.total)),
            if (p.discountTotal > 0)
              _row('Potongan', formatRupiah(p.discountTotal)),
            if (p.inputTaxTotal > 0)
              _row('PPN masukan', formatRupiah(p.inputTaxTotal)),
            const SizedBox(height: 12),
            if (isOwner && p.status == 'pending') ...[
              FilledButton(
                key: const ValueKey('purchase-approve'),
                onPressed: () => Navigator.pop(ctx, 'approve'),
                child: const Text('Setujui HPP'),
              ),
              const SizedBox(height: 6),
              OutlinedButton(
                key: const ValueKey('purchase-reject'),
                onPressed: () => Navigator.pop(ctx, 'reject'),
                child: const Text('Tolak HPP (stok tetap)'),
              ),
              const SizedBox(height: 6),
            ],
            if (canVoid)
              TextButton(
                key: const ValueKey('purchase-void'),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                onPressed: () => Navigator.pop(ctx, 'void'),
                child: const Text('Batalkan pembelian'),
              ),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  switch (action) {
    case 'approve':
      await db.approvePurchase(p.id);
      messenger.showSnackBar(
          const SnackBar(content: Text('HPP disetujui & diterapkan')));
    case 'reject':
      await db.rejectPurchaseCost(p.id);
      messenger.showSnackBar(const SnackBar(
          content: Text('Usulan HPP ditolak — stok tetap tercatat')));
    case 'void':
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Batalkan pembelian?'),
          content: const Text('Stok yang masuk dari pembelian ini akan '
              'dikurangi lagi. HPP dikembalikan ke nilai sebelumnya bila '
              'belum berubah oleh pembelian lain.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Tidak')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Batalkan')),
          ],
        ),
      );
      if (ok != true) return;
      final notRestored =
          await db.voidPurchase(p.id, kasirId: device.deviceCode);
      messenger.showSnackBar(SnackBar(
        content: Text(notRestored.isEmpty
            ? 'Pembelian dibatalkan'
            : 'Pembelian dibatalkan. HPP ${notRestored.length} barang TIDAK '
                'dikembalikan karena sudah berubah oleh pembelian lain.'),
      ));
  }
}

Widget _row(String a, String b) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(a), Text(b)],
      ),
    );
