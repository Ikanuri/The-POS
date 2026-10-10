import '../../core/widgets/app_empty_state.dart';
import '../../core/theme/app_overlays.dart';
import 'package:flutter/material.dart';

import '../../core/services/lan_sync_service.dart';

/// Susulan (permintaan user) — review usulan client->host utk tabel
/// `customers`, PARALEL dari `ProductProposalReviewScreen` (Item 40) &
/// `LaciMejaProposalReviewScreen` (Item 52) — antrian & data terpisah,
/// sengaja tidak menyentuh layar/alur usulan lain sama sekali.
class CustomerProposalReviewScreen extends StatefulWidget {
  const CustomerProposalReviewScreen({super.key, required this.proposal});
  final PendingCustomerProposal proposal;

  @override
  State<CustomerProposalReviewScreen> createState() =>
      _CustomerProposalReviewScreenState();
}

class _CustomerProposalReviewScreenState
    extends State<CustomerProposalReviewScreen> {
  bool _applying = false;

  // Semua default TERCENTANG (owner tinggal uncheck yang mau ditolak, sama
  // pola dgn usulan produk/Laci Meja).
  late final Set<String> _selected = widget.proposal.rows
      .map((r) => r['id'] as String?)
      .whereType<String>()
      .toSet();

  Future<void> _apply() async {
    if (_selected.isEmpty) return;
    setState(() => _applying = true);
    try {
      final applied = await LanSyncService.applyCustomerProposal(
          widget.proposal.id, _selected);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showAppSnackBar(
          SnackBar(content: Text('$applied pelanggan diterapkan')));
    } catch (e) {
      if (mounted) {
        setState(() => _applying = false);
        ScaffoldMessenger.of(context).showAppSnackBar(
            SnackBar(content: Text('Gagal menerapkan usulan: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = widget.proposal.rows;

    return Scaffold(
      appBar: AppBar(
        title: Text('Usulan Pelanggan dari ${widget.proposal.fromIp}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: AppEmptyState('Tidak ada usulan'),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                        child: Text(
                          '${rows.length} pelanggan diusulkan — hilangkan '
                          'centang pada yang tidak ingin diterapkan.',
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurfaceVariant),
                        ),
                      ),
                      ...rows.map((r) {
                        final id = r['id'] as String;
                        final name = (r['name'] as String?) ?? '(tanpa nama)';
                        final phone = r['phone'] as String?;
                        final selected = _selected.contains(id);
                        return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            clipBehavior: Clip.antiAlias,
                            child: CheckboxListTile(
                              value: selected,
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(name,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: phone != null
                                  ? Text(phone,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant))
                                  : null,
                              onChanged: (_) => setState(() {
                                if (!_selected.add(id)) _selected.remove(id);
                              }),
                            ));
                      }),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _applying || _selected.isEmpty ? null : _apply,
                  child: _applying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Terapkan (${_selected.length} pelanggan)'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
