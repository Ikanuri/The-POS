import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
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
    final altRows = widget.proposal.rows['alt_prices'] ?? const [];
    final barcodeRows = widget.proposal.rows['product_barcodes'] ?? const [];

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
    final altsByUnit = <String, List<Map<String, Object?>>>{};
    for (final a in altRows) {
      altsByUnit.putIfAbsent(a['product_unit_id'] as String, () => []).add(a);
    }
    final barcodesByUnit = <String, List<Map<String, Object?>>>{};
    for (final b in barcodeRows) {
      barcodesByUnit
          .putIfAbsent(b['product_unit_id'] as String, () => [])
          .add(b);
    }

    final unitTypeNames = {
      for (final t in await db.getAllUnitTypes()) t.id: t.name,
    };

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
      List<String> changes = const [];
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
        changes = await _diffProduct(
          db: db,
          existingProduct: existing,
          proposedProduct: p,
          proposedUnits: unitsByProduct[id] ?? const [],
          tiersByUnit: tiersByUnit,
          altsByUnit: altsByUnit,
          barcodesByUnit: barcodesByUnit,
          unitTypeNames: unitTypeNames,
        );
      }

      final unitCount = (unitsByProduct[id] ?? const []).length;
      rows.add(_ProposalRow(
        productId: id,
        name: name,
        isNew: existing == null,
        changes: changes,
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

  /// Susulan (permintaan user): dulu subtitle usulan HANYA membandingkan
  /// harga tier dasar — kalau yang berubah bukan harga (mis. satuan diubah,
  /// isi/rasio, barcode, dst.), tampilannya bilang "Tidak ada perubahan
  /// harga" walau usulan itu MEMANG diajukan krn ada perubahan nyata (hampir
  /// bikin owner dismiss usulan asli krn dikira glitch/error). Bandingkan
  /// SEMUA aspek yang mungkin berubah (bukan cuma harga), kembalikan daftar
  /// deskripsi manusiawi. Cocokkan satuan by ID (stabil lintas edit — beda
  /// dari tier/alt-harga/barcode yang id-nya diregenerasi tiap simpan form,
  /// lihat dok `applyProductProposals`), jadi tier/alt/barcode dibandingkan
  /// dari ISI-nya (harga/qty/label/nilai barcode), bukan id.
  Future<List<String>> _diffProduct({
    required AppDatabase db,
    required Product existingProduct,
    required Map<String, Object?> proposedProduct,
    required List<Map<String, Object?>> proposedUnits,
    required Map<String, List<Map<String, Object?>>> tiersByUnit,
    required Map<String, List<Map<String, Object?>>> altsByUnit,
    required Map<String, List<Map<String, Object?>>> barcodesByUnit,
    required Map<int, String> unitTypeNames,
  }) async {
    final changes = <String>[];

    final newName = proposedProduct['name'] as String? ?? '';
    if (existingProduct.name != newName) {
      changes.add('Nama: "${existingProduct.name}" → "$newName"');
    }

    final existingUnits = await db.getProductUnits(existingProduct.id);
    final existingUnitById = {for (final u in existingUnits) u.id: u};
    final proposedUnitIds = <String>{};

    for (final u in proposedUnits) {
      final uid = u['id'] as String;
      proposedUnitIds.add(uid);
      final unitTypeId = (u['unit_type_id'] as num?)?.toInt();
      final ratio = (u['ratio_to_base'] as num?)?.toDouble() ?? 1.0;
      final isNonStock = u['is_non_stock'] == 1 || u['is_non_stock'] == true;
      final newUnitName = unitTypeNames[unitTypeId] ?? 'Satuan';

      final existingUnit = existingUnitById[uid];
      if (existingUnit == null) {
        changes.add('Satuan baru ditambahkan: $newUnitName');
      } else {
        final oldUnitName = unitTypeNames[existingUnit.unitTypeId] ?? 'Satuan';
        if (existingUnit.unitTypeId != unitTypeId) {
          changes.add('Satuan diubah: $oldUnitName → $newUnitName');
        }
        if (!existingUnit.isBaseUnit &&
            (existingUnit.ratioToBase - ratio).abs() > 0.0001) {
          changes.add('Isi per satuan ($newUnitName): '
              '${_fmtNum(existingUnit.ratioToBase)} → ${_fmtNum(ratio)}');
        }
        if (existingUnit.isNonStock != isNonStock) {
          changes.add(isNonStock
              ? 'Satuan $newUnitName diset TIDAK lacak stok'
              : 'Satuan $newUnitName kembali lacak stok');
        }
      }

      // Harga tier dasar per satuan ini (bukan cuma satuan dasar produk).
      final proposedTiers = tiersByUnit[uid] ?? const [];
      final proposedBase =
          proposedTiers.where((t) => (t['min_qty'] as num?)?.toInt() == 1).firstOrNull ??
              proposedTiers.firstOrNull;
      List<PriceTier> oldTiers = const [];
      if (existingUnit != null) {
        oldTiers = await db.getPriceTiers(uid);
      }
      // Harga satuan DASAR sengaja TIDAK dimasukkan ke `changes` di sini —
      // sudah dirender terpisah via `RichText` strikethrough (lihat
      // `_ProposalRow.oldPrice`/`newPrice` & `_ProposalTile`), supaya
      // tampilannya tetap sama persis dgn sebelumnya utk kasus paling
      // umum (harga berubah). Cuma satuan LAIN (non-dasar, mis. varian
      // isi/kemasan) yang harga-nya masuk daftar generik ini.
      final isBaseUnitRow = existingUnit?.isBaseUnit ??
          (u['is_base_unit'] == 1 || u['is_base_unit'] == true);
      if (proposedBase != null && !isBaseUnitRow) {
        final newPrice = (proposedBase['price'] as num).toInt();
        final oldBase =
            oldTiers.where((t) => t.minQty == 1).firstOrNull ?? oldTiers.firstOrNull;
        if (oldBase != null && oldBase.price != newPrice) {
          changes.add(
              'Harga $newUnitName: Rp ${_fmt(oldBase.price)} → Rp ${_fmt(newPrice)}');
        }
      }
      if (existingUnit != null && oldTiers.length != proposedTiers.length) {
        changes.add('Jumlah tier harga grosir ($newUnitName): '
            '${oldTiers.length} → ${proposedTiers.length}');
      }

      // Barcode — dibandingkan sbg SET nilai (id diregenerasi tiap simpan).
      final proposedBarcodes =
          (barcodesByUnit[uid] ?? const []).map((b) => b['barcode'] as String).toSet();
      if (existingUnit != null) {
        final oldBarcodes =
            (await db.getProductBarcodes(uid)).map((b) => b.barcode).toSet();
        final added = proposedBarcodes.difference(oldBarcodes);
        final removed = oldBarcodes.difference(proposedBarcodes);
        if (added.isNotEmpty) {
          changes.add('Barcode $newUnitName ditambah: ${added.join(', ')}');
        }
        if (removed.isNotEmpty) {
          changes.add('Barcode $newUnitName dihapus: ${removed.join(', ')}');
        }
      } else if (proposedBarcodes.isNotEmpty) {
        changes.add('Barcode $newUnitName: ${proposedBarcodes.join(', ')}');
      }

      // Harga alternatif — dibandingkan sbg SET label+harga.
      if (existingUnit != null) {
        final proposedAlts = altsByUnit[uid] ?? const [];
        final oldAlts = await db.getAltPrices(uid);
        final oldSig = oldAlts.map((a) => '${a.label}|${a.price}').toSet();
        final newSig =
            proposedAlts.map((a) => '${a['label']}|${a['price']}').toSet();
        if (oldSig.length != newSig.length || !oldSig.containsAll(newSig)) {
          changes.add('Harga alternatif ($newUnitName) berubah');
        }
      }
    }

    // Satuan yang dihapus (ada di DB owner, tidak ada lagi di usulan).
    for (final existingUnit in existingUnits) {
      if (!proposedUnitIds.contains(existingUnit.id)) {
        final oldUnitName = unitTypeNames[existingUnit.unitTypeId] ?? 'Satuan';
        changes.add('Satuan dihapus: $oldUnitName');
      }
    }

    return changes;
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
    required this.changes,
    this.oldPrice,
    this.newPrice,
    required this.unitCount,
  });

  final String productId;
  final String name;
  final bool isNew;

  /// Susulan (permintaan user) — daftar SEMUA perubahan LAIN terdeteksi
  /// (di luar harga satuan dasar, yang punya tampilan `RichText` sendiri di
  /// bawah — lihat [oldPrice]/[newPrice]): nama, satuan (ditambah/dihapus/
  /// tipe berubah/isi berubah), harga satuan NON-dasar, jumlah tier grosir,
  /// barcode, harga alternatif. Lihat
  /// `_ProductProposalReviewScreenState._diffProduct`.
  final List<String> changes;
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
          else ...[
            if (row.priceChanged)
              RichText(
                text: TextSpan(
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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
              ),
            // Susulan (permintaan user): tampilkan SEMUA perubahan LAIN
            // yang terdeteksi (satuan, isi/rasio, barcode, harga
            // alternatif, dst.), bukan cuma harga — dulu produk yang
            // diubah satuannya (harga tetap sama) tampil "Tidak ada
            // perubahan harga" walau usulannya memang sah, nyaris bikin
            // owner dismiss usulan asli krn dikira glitch.
            ...row.changes.map((c) => Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(c,
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant)),
                )),
            if (!row.priceChanged && row.changes.isEmpty)
              // Seharusnya jarang kejadian (filterUnchangedProposals di
              // host sudah membuang usulan yang isinya identik SEBELUM
              // masuk antrian) — kalau tetap muncul, katakan apa adanya
              // alih-alih menyiratkan ada perubahan harga yang sebenarnya
              // tidak ada.
              Text('Tidak ada perubahan terdeteksi',
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
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

String _fmtNum(double value) =>
    value % 1 == 0 ? value.toInt().toString() : value.toString();
