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
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$applied pelanggan diterapkan')));
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
                    child: Center(child: Text('Tidak ada usulan')),
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: rows.map((r) {
                      final id = r['id'] as String;
                      final name = (r['name'] as String?) ?? '(tanpa nama)';
                      final phone = r['phone'] as String?;
                      final selected = _selected.contains(id);
                      return CheckboxListTile(
                        value: selected,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(name, style: const TextStyle(fontSize: 13)),
                        subtitle: phone != null
                            ? Text(phone,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant))
                            : null,
                        onChanged: (_) => setState(() {
                          if (!_selected.add(id)) _selected.remove(id);
                        }),
                      );
                    }).toList(),
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
