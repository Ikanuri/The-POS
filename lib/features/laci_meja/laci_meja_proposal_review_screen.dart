import 'package:flutter/material.dart';

import '../../core/services/lan_sync_service.dart';

/// Item 52 ("Laci Meja") — review usulan client->host utk 3 tabel Laci
/// Meja (left_behind_items/borrowed_items/preorder_entries), PARALEL dari
/// `ProductProposalReviewScreen` (Item 40) — antrian & data terpisah,
/// sengaja tidak menyentuh layar/alur usulan produk sama sekali.
class LaciMejaProposalReviewScreen extends StatefulWidget {
  const LaciMejaProposalReviewScreen({super.key, required this.proposal});
  final PendingLaciMejaProposal proposal;

  @override
  State<LaciMejaProposalReviewScreen> createState() =>
      _LaciMejaProposalReviewScreenState();
}

class _LaciMejaProposalReviewScreenState
    extends State<LaciMejaProposalReviewScreen> {
  bool _applying = false;

  // table -> set of selected row ids. Semua default TERCENTANG (owner
  // tinggal uncheck yang mau ditolak, sama pola dgn usulan produk).
  late final Map<String, Set<String>> _selected = {
    for (final entry in widget.proposal.rows.entries)
      entry.key: entry.value
          .map((r) => r['id'] as String?)
          .whereType<String>()
          .toSet(),
  };

  int get _totalSelected =>
      _selected.values.fold(0, (a, b) => a + b.length);

  Future<void> _apply() async {
    if (_totalSelected == 0) return;
    setState(() => _applying = true);
    try {
      final applied = await LanSyncService.applyLaciMejaProposal(
          widget.proposal.id, _selected);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$applied baris diterapkan ke Laci Meja')));
    } catch (e) {
      if (mounted) {
        setState(() => _applying = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menerapkan usulan: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final leftBehind = widget.proposal.rows['left_behind_items'] ?? const [];
    final borrowed = widget.proposal.rows['borrowed_items'] ?? const [];
    final preorder = widget.proposal.rows['preorder_entries'] ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text('Usulan Laci Meja dari ${widget.proposal.fromIp}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (leftBehind.isNotEmpty) ...[
                  Text('Titip/Ketinggalan (${leftBehind.length})',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  ...leftBehind.map((r) => _row(
                        table: 'left_behind_items',
                        id: r['id'] as String,
                        title: (r['item_name'] as String?) ?? '(tanpa nama)',
                        subtitle:
                            '${(r['jenis'] as String?) == 'titip' ? 'Dititip' : 'Ketinggalan'}'
                            '${r['customer_name_text'] != null ? ' — ${r['customer_name_text']}' : ''}',
                      )),
                  const SizedBox(height: 12),
                ],
                if (borrowed.isNotEmpty) ...[
                  Text('Pinjaman Barang (${borrowed.length})',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  ...borrowed.map((r) {
                    final qty = (r['qty'] as num?)?.toDouble() ?? 0;
                    final returned =
                        (r['qty_returned'] as num?)?.toDouble() ?? 0;
                    return _row(
                      table: 'borrowed_items',
                      id: r['id'] as String,
                      title: (r['item_name'] as String?) ?? '(tanpa nama)',
                      subtitle: 'Qty $qty (sisa ${qty - returned})'
                          '${r['customer_name_text'] != null ? ' — ${r['customer_name_text']}' : ''}',
                    );
                  }),
                  const SizedBox(height: 12),
                ],
                if (preorder.isNotEmpty) ...[
                  Text('Pre-order (${preorder.length})',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  ...preorder.map((r) {
                    final qty = (r['qty_ordered'] as num?)?.toDouble() ?? 0;
                    final deposit = (r['deposit_qty'] as num?)?.toDouble() ?? 0;
                    final paid = r['paid'] == 1 || r['paid'] == true;
                    return _row(
                      table: 'preorder_entries',
                      id: r['id'] as String,
                      title: (r['customer_name'] as String?) ?? '(tanpa nama)',
                      subtitle: 'Qty $qty'
                          '${deposit > 0 ? ' · titip wadah $deposit' : ''}'
                          '${paid ? ' · sudah bayar' : ''}',
                    );
                  }),
                ],
                if (leftBehind.isEmpty && borrowed.isEmpty && preorder.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Tidak ada usulan')),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                  top:
                      BorderSide(color: scheme.outlineVariant.withOpacity(0.3))),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _applying || _totalSelected == 0 ? null : _apply,
                  child: _applying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Terapkan ($_totalSelected baris)'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required String table,
    required String id,
    required String title,
    required String subtitle,
  }) {
    final selected = _selected[table]?.contains(id) ?? false;
    return CheckboxListTile(
      value: selected,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      onChanged: (_) => setState(() {
        final set = _selected.putIfAbsent(table, () => {});
        if (!set.add(id)) set.remove(id);
      }),
    );
  }
}
