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
      final result = await LanSyncService.applyLaciMejaProposal(
          widget.proposal.id, _selected);
      if (!mounted) return;
      Navigator.of(context).pop();
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(
        content: Text('${result.applied} baris diterapkan ke Laci Meja'),
      ));
      // Susulan (bug ditemukan user) — baris yang transaksi terkaitnya
      // belum tersinkron ke host DILEWATI (bukan menggagalkan seluruh
      // batch), tapi owner WAJIB tahu supaya tidak mengira usulannya
      // sudah tuntas padahal masih ada sisa yang menunggu. Baris itu
      // akan otomatis diusulkan ulang begitu transaksinya sendiri sudah
      // tersinkron — tidak hilang, cukup ditunggu/diulang.
      if (result.skippedReasons.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sebagian Baris Ditunda'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${result.skippedReasons.length} baris belum bisa diterapkan '
                    '— transaksi terkaitnya belum tersinkron ke perangkat ini. '
                    'Baris ini akan otomatis diusulkan lagi begitu transaksinya '
                    'sudah masuk (mis. setelah usulan sync "Transaksi" dari '
                    'device yang sama diterima):',
                  ),
                  const SizedBox(height: 10),
                  for (final reason in result.skippedReasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $reason', style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Mengerti'),
              ),
            ],
          ),
        );
      }
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
    final events = widget.proposal.rows['laci_meja_events'] ?? const [];

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
                  ...leftBehind.map((r) {
                    // Susulan (permintaan user) — baris yang SUDAH diambil
                    // (`collected_at` terisi) tetap masuk usulan (dumpnya
                    // ikut nyala `locally_modified` saat status berubah),
                    // tapi TANPA penanda ini terlihat seperti barang
                    // titip/ketinggalan yang MASIH menunggu diambil —
                    // padahal usulan ini cuma riwayat "sudah diambil" yang
                    // perlu disinkron ke host, bukan hal baru yang perlu
                    // ditinjau.
                    final collected = r['collected_at'] != null;
                    return _row(
                      table: 'left_behind_items',
                      id: r['id'] as String,
                      title: (r['item_name'] as String?) ?? '(tanpa nama)',
                      subtitle:
                          '${(r['jenis'] as String?) == 'titip' ? 'Dititip' : 'Ketinggalan'}'
                          '${r['customer_name_text'] != null ? ' — ${r['customer_name_text']}' : ''}'
                          '${collected ? ' · Sudah diambil' : ''}',
                    );
                  }),
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
                    final fullyReturned = r['fully_returned_at'] != null;
                    return _row(
                      table: 'borrowed_items',
                      id: r['id'] as String,
                      title: (r['item_name'] as String?) ?? '(tanpa nama)',
                      subtitle: 'Qty $qty (sisa ${qty - returned})'
                          '${r['customer_name_text'] != null ? ' — ${r['customer_name_text']}' : ''}'
                          '${fullyReturned ? ' · Sudah kembali semua' : (returned > 0 ? ' · Dikembalikan sebagian ($returned)' : '')}',
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
                    // Susulan (permintaan user) — pre-order yang SUDAH
                    // dipenuhi/dibatalkan tetap bisa masuk usulan (baris
                    // itu berubah statusnya, jadi `locally_modified` nyala
                    // lagi), tapi tanpa penanda status di sini owner
                    // mengira ini pre-order BARU yang masih terbuka —
                    // padahal cuma riwayat penyelesaian yang perlu
                    // disinkron. Ini yang bikin laporan user "kenapa
                    // pre-order yang sudah dipenuhi muncul lagi utk
                    // ditinjau" — jawabannya: ya, itu memang riwayat sync
                    // (bukan bug), sekarang ditandai jelas biar tidak
                    // membingungkan.
                    final fulfilled = r['fulfilled_at'] != null;
                    final cancelled = r['cancelled_at'] != null;
                    return _row(
                      table: 'preorder_entries',
                      id: r['id'] as String,
                      title: (r['customer_name'] as String?) ?? '(tanpa nama)',
                      subtitle: 'Qty $qty'
                          '${deposit > 0 ? ' · titip wadah $deposit' : ''}'
                          '${paid ? ' · sudah bayar' : ''}'
                          '${fulfilled ? ' · Dipenuhi' : (cancelled ? ' · Dibatalkan' : '')}',
                    );
                  }),
                ],
                if (events.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Riwayat Kejadian (${events.length})',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  // Susulan (permintaan user) — kejadian "diambil sejumlah
                  // sekian" dkk (`laci_meja_events`) SEBELUMNYA ikut
                  // dikirim & diterapkan sbg usulan, tapi TIDAK PERNAH
                  // ditampilkan di layar ini sama sekali — owner menyetujui
                  // baris yang tak terlihat. Sekarang ditampilkan eksplisit
                  // supaya jelas usulan ini murni riwayat kejadian, bukan
                  // permintaan baru.
                  Text(
                      'Kejadian ambil/kembali/penuhi/batal yang tercatat di '
                      'perangkat kasir — ikut disinkron sbg riwayat, BUKAN '
                      'permintaan baru.',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  ...events.map((r) {
                    final aksi = r['aksi'] as String? ?? '?';
                    final qty = (r['qty'] as num?)?.toDouble() ?? 0;
                    final label = switch (aksi) {
                      'ambil' => 'Diambil $qty',
                      'kembali' => 'Dikembalikan $qty',
                      'penuhi' => 'Dipenuhi $qty',
                      'batal' => 'Dibatalkan',
                      // Susulan (permintaan user) — pembayaran DP/jaminan
                      // pre-order yang tadinya dikunci Rp 0 saat checkout.
                      // qty SENGAJA 0 di event ini (nominalnya ada di
                      // `note`) supaya tidak ikut kehitung sbg qty barang
                      // diambil/dipenuhi.
                      'bayar' => 'DP Dibayar',
                      _ => aksi,
                    };
                    return _row(
                      table: 'laci_meja_events',
                      id: r['id'] as String,
                      title: label,
                      subtitle: (r['note'] as String?) ?? '',
                    );
                  }),
                ],
                if (leftBehind.isEmpty &&
                    borrowed.isEmpty &&
                    preorder.isEmpty &&
                    events.isEmpty)
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
