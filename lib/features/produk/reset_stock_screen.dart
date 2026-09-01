import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/inline_banner.dart';

/// Susulan (permintaan user): "beri opsi untuk reset seluruh atau grup
/// produk tertentu stoknya jadi 0". Proposal UI/UX direview & disetujui
/// user sebelum implementasi (instruksi eksplisit "tawarkan UI UX nya
/// dulu").
///
/// SENGAJA dibangun sbg pemakaian LAIN dari mekanisme Stock Opname yang
/// sudah ada (`AppDatabase.commitOpname`), bukan jalur tulis stok baru —
/// "reset ke 0" secara konsep adalah kasus KHUSUS opname (hitung fisik =
/// 0 utk semua produk terpilih), jadi otomatis dapat: atomic write per
/// sesi, jejak audit `stock_ledger`, DAN muncul di layar "Riwayat Opname"
/// yang sudah ada TANPA perlu layar riwayat baru (lihat
/// `AppDatabase.buildOpnameNote` param `isReset`).
///
/// Beda dari opname biasa: TIDAK ada tahap "hitung buta" (target akhir
/// SELALU 0, tidak ada yang perlu diketik) — langsung dari pilih scope ke
/// review daftar apa yang akan berubah, sebelum benar-benar disimpan.
class ResetStockScreen extends ConsumerStatefulWidget {
  const ResetStockScreen({super.key});

  @override
  ConsumerState<ResetStockScreen> createState() => _ResetStockScreenState();
}

final _resetStockGroupsProvider = FutureProvider<List<ProductGroup>>((ref) {
  return ref.watch(databaseProvider).getAllProductGroups();
});

class _ResetStockScreenState extends ConsumerState<ResetStockScreen> {
  int? _selectedGroupId;
  String? _selectedGroupLabel;
  bool _loading = false;

  Future<void> _proceed() async {
    setState(() => _loading = true);
    final db = ref.read(databaseProvider);
    final allRows = await db.watchStockOverview(groupId: _selectedGroupId).first;
    // Produk yang stoknya SUDAH 0 tidak ada gunanya diproses (tidak ada
    // selisih, cuma menambah baris ledger kosong) — disaring di sini,
    // BUKAN cuma di layar review, supaya "0 produk berstok" bisa ditolak
    // lebih awal dgn pesan yang jelas.
    final rows = allRows.where((r) => r.stock != 0).toList();
    if (!mounted) return;
    setState(() => _loading = false);
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tidak ada produk berstok di cakupan ini')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ResetStockReviewScreen(
        rows: rows,
        categoryLabel: _selectedGroupLabel,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(_resetStockGroupsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Reset Stok')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Peringatan eksplisit di titik paling awal — tindakan ini
            // MENGHAPUS data stok, beda dari opname biasa (koreksi ke
            // hasil hitung fisik yang bisa benar/wajar).
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.error.withOpacity(0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: scheme.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Stok produk yang dipilih akan DITIMPA jadi 0. '
                      'Berbeda dari Stock Opname biasa — tidak ada hitung '
                      'fisik, langsung ditulis 0. Akan ada layar review '
                      'sebelum benar-benar disimpan.',
                      style: TextStyle(fontSize: 12.5, color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Pilih cakupan:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            groupsAsync.when(
              data: (groups) {
                final named = groups.where((g) => g.name != null).toList();
                return Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _ScopeChip(
                      label: 'Semua',
                      selected: _selectedGroupId == null,
                      onTap: () => setState(() {
                        _selectedGroupId = null;
                        _selectedGroupLabel = null;
                      }),
                    ),
                    ...named.map((g) => _ScopeChip(
                          label: g.name!,
                          selected: _selectedGroupId == g.id,
                          onTap: () => setState(() {
                            _selectedGroupId = g.id;
                            _selectedGroupLabel = g.name;
                          }),
                        )),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _proceed,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.restore),
                label: const Text('Lihat & Reset'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Review sebelum commit — daftar SEMUA produk yang akan terdampak (stok
/// != 0 di cakupan terpilih), Sistem vs Baru (selalu 0), diklik "Reset ke
/// 0" baru muncul dialog konfirmasi berketik.
class _ResetStockReviewScreen extends ConsumerStatefulWidget {
  const _ResetStockReviewScreen(
      {required this.rows, required this.categoryLabel});
  final List<StockOverviewRow> rows;
  final String? categoryLabel;

  @override
  ConsumerState<_ResetStockReviewScreen> createState() =>
      _ResetStockReviewScreenState();
}

class _ResetStockReviewScreenState
    extends ConsumerState<_ResetStockReviewScreen>
    with InlineBannerStateMixin<_ResetStockReviewScreen> {
  bool _saving = false;

  String _fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  Future<void> _confirmAndCommit() async {
    final scopeLabel = widget.categoryLabel == null
        ? 'SEMUA produk (${widget.rows.length} item)'
        : 'kategori "${widget.categoryLabel}" (${widget.rows.length} item)';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => _TypeToConfirmDialog(scopeLabel: scopeLabel),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final note = AppDatabase.buildOpnameNote(DateTime.now(),
        categoryLabel: widget.categoryLabel, isReset: true);
    try {
      await db.commitOpname(
        entries: widget.rows
            .map((r) => (productUnitId: r.unitId, newQty: 0.0))
            .toList(),
        note: note,
        kasirId: device.deviceCode,
      );
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == '/');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Stok direset (${widget.rows.length} produk ke 0)')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError('Gagal mereset stok: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Review Reset Stok')),
      body: Column(
        children: [
          inlineBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${widget.rows.length} produk akan direset ke 0'
                '${widget.categoryLabel != null ? ' (kategori: ${widget.categoryLabel})' : ' (seluruh kategori)'}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              itemCount: widget.rows.length,
              itemBuilder: (context, i) {
                final r = widget.rows[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(r.name,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('Sistem: ${_fmt(r.stock)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant)),
                        ),
                        const Expanded(
                          flex: 2,
                          child: Text('Baru: 0', style: TextStyle(fontSize: 11)),
                        ),
                        SizedBox(
                          width: 64,
                          child: Text(
                            '-${_fmt(r.stock)}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.debtFg(
                                    Theme.of(context).brightness ==
                                        Brightness.dark)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _confirmAndCommit,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.restore),
                  label: const Text('Reset ke 0'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gerbang konfirmasi berketik ("ketik RESET") — tindakan ini menimpa
/// stok store-wide/kategori sekaligus, gesekan lebih tinggi drpd dialog
/// Ya/Batal biasa (pola sama kelas tindakan dgn hapus kategori), supaya
/// tidak ke-tap tanpa sengaja saat terburu-buru.
class _TypeToConfirmDialog extends StatefulWidget {
  const _TypeToConfirmDialog({required this.scopeLabel});
  final String scopeLabel;

  @override
  State<_TypeToConfirmDialog> createState() => _TypeToConfirmDialogState();
}

class _TypeToConfirmDialogState extends State<_TypeToConfirmDialog> {
  final _ctrl = TextEditingController();
  bool _match = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Reset Stok?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reset ${widget.scopeLabel} ke 0. Tindakan ini menulis '
              'penyesuaian stok baru — tidak bisa dibatalkan otomatis, '
              'hanya bisa dikoreksi manual lewat opname/penyesuaian '
              'berikutnya.'),
          const SizedBox(height: 12),
          Text('Ketik RESET untuk melanjutkan:',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: 'RESET',
            ),
            onChanged: (v) => setState(() => _match = v.trim() == 'RESET'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _match ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          child: const Text('Reset ke 0'),
        ),
      ],
    );
  }
}
