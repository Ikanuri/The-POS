import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../cart_preorder_settlement_provider.dart';

/// Fitur "Pelunasi Pre-order" DI KERANJANG — arsitektur IDENTIK dgn
/// `showDebtSettlementSheet` (`debt_settlement_sheet.dart`, baca dok di sana
/// dulu), cuma sumber datanya `getPreorderSettlementCandidates` (pre-order
/// pelanggan yang MASIH ada DP/jaminan terhutang, bukan nota tempo/kurang_
/// bayar). Entry point: chip pengingat pre-order di `cart_sheet.dart` — tap
/// membuka sheet ini, checklist SEMUA pre-order pelanggan yg masih terhutang,
/// kasir centang/uncentang per-baris lalu "Terapkan". Tiap baris tercentang
/// jadi SATU [PreorderSettlementEntry] terpisah di
/// `cartPreorderSettlementProvider(cartId)` — uncentang pre-order yang SUDAH
/// jadi entri = entri itu dihapus, centang baru = entri baru ditambah.
Future<void> showPreorderSettlementSheet(
  BuildContext context,
  WidgetRef ref, {
  required String cartId,
  required String customerId,
  required String customerName,
}) async {
  final db = ref.read(databaseProvider);
  final candidates = await db.getPreorderSettlementCandidates(customerId);
  if (!context.mounted) return;
  if (candidates.isEmpty) {
    // Race jarang: DP sudah terkumpul di antara baca total (chip) & tap
    // (mis. dilunasi dari device lain lalu sync). Beri tahu, jangan buka
    // sheet kosong yang membingungkan.
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Tidak ada pre-order dgn DP tertunggak utk pelanggan ini')));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PreorderSettlementSheetBody(
      cartId: cartId,
      customerId: customerId,
      customerName: customerName,
      candidates: candidates,
    ),
  );
}

class _PreorderSettlementSheetBody extends ConsumerStatefulWidget {
  const _PreorderSettlementSheetBody({
    required this.cartId,
    required this.customerId,
    required this.customerName,
    required this.candidates,
  });

  final String cartId;
  final String customerId;
  final String customerName;
  final List<PreorderSettlementCandidate> candidates;

  @override
  ConsumerState<_PreorderSettlementSheetBody> createState() =>
      _PreorderSettlementSheetBodyState();
}

class _PreorderSettlementSheetBodyState
    extends ConsumerState<_PreorderSettlementSheetBody> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    // Pra-centang pre-order yang SUDAH jadi entri di keranjang ini (mis.
    // kasir buka sheet lagi utk uncentang sebagian yang tadi dipilih).
    final current = ref.read(cartPreorderSettlementProvider(widget.cartId));
    _selected = current
        .where((e) => e.customerId == widget.customerId)
        .map((e) => e.preorderEntryId)
        .toSet();
  }

  bool get _allSelected => _selected.length == widget.candidates.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(widget.candidates.map((e) => e.preorderEntryId));
      }
    });
  }

  void _apply() {
    final notifier =
        ref.read(cartPreorderSettlementProvider(widget.cartId).notifier);
    for (final c in widget.candidates) {
      final isSelected = _selected.contains(c.preorderEntryId);
      if (isSelected) {
        // Sudah ada entri utk pre-order ini -> biarkan (tidak menimpa
        // amount, konsisten dgn dok `PreorderSettlementEntry`: nominal
        // dibekukan saat dicentang). Belum ada -> tambah baru.
        final already = ref
            .read(cartPreorderSettlementProvider(widget.cartId))
            .any((e) => e.preorderEntryId == c.preorderEntryId);
        if (!already) {
          notifier.add(PreorderSettlementEntry(
            id: const Uuid().v4(),
            preorderEntryId: c.preorderEntryId,
            invoiceId: c.invoiceId,
            invoiceLocalId: c.invoiceLocalId,
            invoiceDate: c.invoiceDate,
            customerId: widget.customerId,
            customerName: widget.customerName,
            productName: c.productName,
            amount: c.amount,
            createdAt: DateTime.now(),
            // Placeholder — DITIMPA metode FINAL kasir di layar Bayar (lihat
            // dok `PreorderSettlementEntry.method`).
            method: 'tunai',
          ));
        }
      } else {
        notifier.removeByPreorderEntry(c.preorderEntryId);
      }
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedTotal = widget.candidates
        .where((e) => _selected.contains(e.preorderEntryId))
        .fold<int>(0, (s, e) => s + e.amount);
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
            Text('Pilih Pre-order untuk Dilunasi',
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
                itemCount: widget.candidates.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = widget.candidates[i];
                  final checked = _selected.contains(c.preorderEntryId);
                  return CheckboxListTile(
                    value: checked,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => setState(() {
                      if (v ?? false) {
                        _selected.add(c.preorderEntryId);
                      } else {
                        _selected.remove(c.preorderEntryId);
                      }
                    }),
                    title: Text(c.productName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        'Nota ${c.invoiceLocalId} · '
                        '${formatTanggalPendek(c.invoiceDate)}',
                        style: const TextStyle(fontSize: 12)),
                    secondary: Text(
                      formatRupiah(c.amount),
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
