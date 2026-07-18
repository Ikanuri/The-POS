import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/lan_sync_service.dart';
import '../../core/widgets/inline_banner.dart';

/// Item 40 — review usulan harga/produk dari device non-owner (asisten/
/// kasir), sebelum ditulis ke DB owner. Gaya visual sengaja disamakan
/// dgn `PricePreviewScreen` (sinkron harga dari file), tapi struktur data
/// beda: di sini baris MENTAH (produk+satuan+harga+alt harga+barcode)
/// dikirim apa adanya (bukan flat 1-baris-1-satuan spt `PriceCatalogItem`)
/// supaya produk baru dgn banyak satuan/varian/harga tidak "kepotong".
class ProductProposalReviewScreen extends ConsumerStatefulWidget {
  const ProductProposalReviewScreen({super.key, required this.proposal});
  final PendingProductProposal proposal;

  @override
  ConsumerState<ProductProposalReviewScreen> createState() =>
      _ProductProposalReviewScreenState();
}

class _ProductProposalReviewScreenState
    extends ConsumerState<ProductProposalReviewScreen>
    with InlineBannerStateMixin<ProductProposalReviewScreen> {
  bool _loading = true;
  bool _applying = false;
  List<_ProposalRow> _rows = [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final productRows = widget.proposal.rows['products'] ?? const [];
    final unitRows = widget.proposal.rows['product_units'] ?? const [];
    final tierRows = widget.proposal.rows['price_tiers'] ?? const [];

    final unitsByProduct = <String, List<Map<String, Object?>>>{};
    for (final u in unitRows) {
      unitsByProduct
          .putIfAbsent(u['product_id'] as String, () => [])
          .add(u);
    }
    final tiersByUnit = <String, List<Map<String, Object?>>>{};
    for (final t in tierRows) {
      tiersByUnit
          .putIfAbsent(t['product_unit_id'] as String, () => [])
          .add(t);
    }

    int? baseTierPrice(String productId) {
      final units = unitsByProduct[productId] ?? const [];
      final baseUnit = units
          .where((u) => u['is_base_unit'] == 1 || u['is_base_unit'] == true)
          .firstOrNull ??
          units.firstOrNull;
      if (baseUnit == null) return null;
      final tiers = tiersByUnit[baseUnit['id'] as String] ?? const [];
      final base = tiers
          .where((t) => t['min_qty'] == 1)
          .firstOrNull ??
          tiers.firstOrNull;
      return base == null ? null : (base['price'] as num).toInt();
    }

    final rows = <_ProposalRow>[];
    for (final p in productRows) {
      final id = p['id'] as String;
      final name = p['name'] as String? ?? '(tanpa nama)';
      final newPrice = baseTierPrice(id);

      final existing = await (db.select(db.products)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      int? oldPrice;
      if (existing != null) {
        final units = await db.getProductUnits(id);
        final baseUnit =
            units.where((u) => u.isBaseUnit).firstOrNull ?? units.firstOrNull;
        if (baseUnit != null) {
          final tiers = await db.getPriceTiers(baseUnit.id);
          final base = tiers.where((t) => t.minQty == 1).firstOrNull ??
              tiers.firstOrNull;
          oldPrice = base?.price;
        }
      }

      final unitCount = (unitsByProduct[id] ?? const []).length;
      rows.add(_ProposalRow(
        productId: id,
        name: name,
        isNew: existing == null,
        oldName: existing?.name,
        oldPrice: oldPrice,
        newPrice: newPrice,
        unitCount: unitCount,
      ));
      // Semua usulan default TERCENTANG — owner tinggal uncheck yang mau
      // ditolak (lebih cepat utk kasus umum "semuanya benar").
      _selected.add(id);
    }

    if (mounted) {
      setState(() {
        _rows = rows;
        _loading = false;
      });
    }
  }

  Future<void> _apply() async {
    if (_selected.isEmpty) {
      showBanner('Pilih minimal 1 produk', type: InlineBannerType.info);
      return;
    }
    setState(() => _applying = true);
    try {
      final applied =
          await LanSyncService.applyProposal(widget.proposal.id, _selected);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$applied baris diterapkan ke ${_selected.length} '
              'produk')));
    } catch (e) {
      if (mounted) {
        setState(() => _applying = false);
        showError('Gagal menerapkan usulan: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final changed = _rows.where((r) => !r.isNew).toList();
    final baru = _rows.where((r) => r.isNew).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Usulan dari ${widget.proposal.fromIp}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                inlineBanner(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (changed.isNotEmpty) ...[
                        Text('Harga/Produk Berubah (${changed.length})',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        ...changed.map((r) => _ProposalTile(
                              row: r,
                              selected: _selected.contains(r.productId),
                              onToggle: () => setState(() {
                                if (_selected.contains(r.productId)) {
                                  _selected.remove(r.productId);
                                } else {
                                  _selected.add(r.productId);
                                }
                              }),
                            )),
                      ],
                      if (baru.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('Produk Baru (${baru.length})',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        ...baru.map((r) => _ProposalTile(
                              row: r,
                              selected: _selected.contains(r.productId),
                              onToggle: () => setState(() {
                                if (_selected.contains(r.productId)) {
                                  _selected.remove(r.productId);
                                } else {
                                  _selected.add(r.productId);
                                }
                              }),
                            )),
                      ],
                      if (_rows.isEmpty)
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
                        top: BorderSide(
                            color: scheme.outlineVariant.withOpacity(0.3))),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _applying || _selected.isEmpty
                            ? null
                            : _apply,
                        child: _applying
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text('Terapkan (${_selected.length} produk)'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ProposalRow {
  _ProposalRow({
    required this.productId,
    required this.name,
    required this.isNew,
    this.oldName,
    this.oldPrice,
    this.newPrice,
    required this.unitCount,
  });

  final String productId;
  final String name;
  final bool isNew;
  final String? oldName;
  final int? oldPrice;
  final int? newPrice;
  final int unitCount;

  bool get priceChanged =>
      !isNew && oldPrice != null && newPrice != null && oldPrice != newPrice;
}

class _ProposalTile extends StatelessWidget {
  const _ProposalTile(
      {required this.row, required this.selected, required this.onToggle});
  final _ProposalRow row;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CheckboxListTile(
      value: selected,
      onChanged: (_) => onToggle(),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(row.name, style: const TextStyle(fontSize: 13)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.isNew)
            Text(
                '${row.unitCount} satuan'
                '${row.newPrice != null ? ' · Rp ${_fmt(row.newPrice!)}' : ''}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))
          else if (row.priceChanged)
            RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                children: [
                  const TextSpan(text: 'Harga: '),
                  TextSpan(
                    text: 'Rp ${_fmt(row.oldPrice!)}',
                    style: const TextStyle(
                        decoration: TextDecoration.lineThrough,
                        fontSize: 11),
                  ),
                  TextSpan(
                    text: ' → Rp ${_fmt(row.newPrice!)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: scheme.primary),
                  ),
                ],
              ),
            )
          else
            Text('Tidak ada perubahan harga',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

String _fmt(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}
