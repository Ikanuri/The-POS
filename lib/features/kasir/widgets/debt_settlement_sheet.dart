import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../cart_debt_settlement_provider.dart';

/// Fitur "Lunasi Hutang" — REDESAIN KEDUA (permintaan user, gantikan toggle
/// boolean tunggal `_DebtSettlementCartRow` dari `a254152`, DIHAPUS total).
/// Entry point sekarang chip pengingat hutang yang SUDAH ADA (cart bar
/// `kasir_screen.dart` & versi di `cart_sheet.dart`) — tap membuka sheet ini,
/// checklist SEMUA nota tempo/kurang_bayar pelanggan (`getUnpaidTxDetails`,
/// SUDAH ADA, REUSE — bukan query baru), kasir centang/uncentang per-nota
/// lalu "Terapkan". Tiap nota tercentang jadi SATU [DebtSettlementEntry]
/// terpisah di `cartDebtSettlementProvider(cartId)` (lihat dok di sana) —
/// uncentang nota yang SUDAH jadi entri = entri itu dihapus, centang nota
/// baru = entri baru ditambah. Nota yang tidak disentuh (sudah/belum
/// tercentang, tidak diubah) TIDAK disentuh entrinya sama sekali.
Future<void> showDebtSettlementSheet(
  BuildContext context,
  WidgetRef ref, {
  required String cartId,
  required String customerId,
  required String customerName,
}) async {
  final db = ref.read(databaseProvider);
  final invoices = await db.getUnpaidTxDetails(customerId);
  if (!context.mounted) return;
  if (invoices.isEmpty) {
    // Race jarang: hutang sudah lunas di antara baca total (chip) & tap
    // (mis. dilunasi dari device lain lalu sync). Beri tahu, jangan buka
    // sheet kosong yang membingungkan.
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tidak ada nota belum lunas utk pelanggan ini')));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DebtSettlementSheetBody(
      cartId: cartId,
      customerId: customerId,
      customerName: customerName,
      invoices: invoices,
    ),
  );
}

class _DebtSettlementSheetBody extends ConsumerStatefulWidget {
  const _DebtSettlementSheetBody({
    required this.cartId,
    required this.customerId,
    required this.customerName,
    required this.invoices,
  });

  final String cartId;
  final String customerId;
  final String customerName;
  final List<UnpaidTxEntry> invoices;

  @override
  ConsumerState<_DebtSettlementSheetBody> createState() =>
      _DebtSettlementSheetBodyState();
}

class _DebtSettlementSheetBodyState
    extends ConsumerState<_DebtSettlementSheetBody> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    // Pra-centang nota yang SUDAH jadi entri di keranjang ini (mis. kasir
    // buka sheet lagi utk uncentang sebagian nota yang tadi dipilih).
    final current = ref.read(cartDebtSettlementProvider(widget.cartId));
    _selected = current
        .where((e) => e.customerId == widget.customerId)
        .map((e) => e.invoiceId)
        .toSet();
  }

  bool get _allSelected => _selected.length == widget.invoices.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(widget.invoices.map((e) => e.id));
      }
    });
  }

  void _apply() {
    final notifier =
        ref.read(cartDebtSettlementProvider(widget.cartId).notifier);
    for (final inv in widget.invoices) {
      final isSelected = _selected.contains(inv.id);
      if (isSelected) {
        // Sudah ada entri utk nota ini -> biarkan (tidak menimpa amount,
        // walau sisa berubah tipis — konsisten dgn dok `DebtSettlementEntry`:
        // nominal dibekukan saat dicentang, bukan dihitung ulang tiap
        // buka sheet). Belum ada -> tambah baru.
        final already = ref
            .read(cartDebtSettlementProvider(widget.cartId))
            .any((e) => e.invoiceId == inv.id);
        if (!already) {
          notifier.add(DebtSettlementEntry(
            id: const Uuid().v4(),
            invoiceId: inv.id,
            invoiceLocalId: inv.localId,
            invoiceDate: inv.createdAt,
            customerId: widget.customerId,
            customerName: widget.customerName,
            amount: inv.sisa,
            createdAt: DateTime.now(),
            // Placeholder — DITIMPA metode FINAL kasir di layar Bayar (lihat
            // dok `DebtSettlementEntry.method`).
            method: 'tunai',
          ));
        }
      } else {
        notifier.removeByInvoice(inv.id);
      }
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedTotal = widget.invoices
        .where((e) => _selected.contains(e.id))
        .fold<int>(0, (s, e) => s + e.sisa);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Pilih Nota untuk Dilunasi',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(widget.customerName,
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _allSelected,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Centang Semua',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onChanged: (_) => _toggleAll(),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.invoices.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final inv = widget.invoices[i];
                  final checked = _selected.contains(inv.id);
                  return CheckboxListTile(
                    value: checked,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => setState(() {
                      if (v ?? false) {
                        _selected.add(inv.id);
                      } else {
                        _selected.remove(inv.id);
                      }
                    }),
                    title: Text('Nota ${inv.localId}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(formatTanggalPendek(inv.createdAt),
                        style: const TextStyle(fontSize: 12)),
                    secondary: Text(
                      formatRupiah(inv.sisa),
                      style: AppTheme.numStyle(context,
                          size: 13,
                          weight: FontWeight.w700,
                          color: scheme.primary),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total dipilih',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text(formatRupiah(selectedTotal),
                    style: AppTheme.numStyle(context,
                        size: 14,
                        weight: FontWeight.w700,
                        color: scheme.primary)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('Terapkan'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
