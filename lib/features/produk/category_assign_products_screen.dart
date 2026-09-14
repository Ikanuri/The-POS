import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/inline_banner.dart';

/// Item 54 — dari layar Kelola Kategori, tap sebuah kategori membuka layar
/// ini: centang produk LANGSUNG tersimpan hidup (live-toggle, tanpa tombol
/// "Terapkan" massal spt Item 52 lama) — centang = produk masuk kategori
/// ini (jadi kategori utama bila produk belum punya satu pun, atau tag
/// tambahan bila sudah), uncentang = keluar dari kategori ini SAJA (kategori
/// lain yang sudah melekat pada produk itu TETAP dipertahankan).
class CategoryAssignProductsScreen extends ConsumerStatefulWidget {
  const CategoryAssignProductsScreen(
      {super.key, required this.groupId, required this.groupName});
  final int groupId;
  final String groupName;

  @override
  ConsumerState<CategoryAssignProductsScreen> createState() =>
      _CategoryAssignProductsScreenState();
}

class _CategoryAssignProductsScreenState
    extends ConsumerState<CategoryAssignProductsScreen>
    with InlineBannerStateMixin<CategoryAssignProductsScreen> {
  final _searchCtrl = TextEditingController();
  List<Product> _results = [];
  // Varian (produk anak) yang cocok dari `db.searchProducts`, dikelompokkan
  // per parentProductId — TIDAK dirender sbg baris `_results` sendiri, tapi
  // nested dropdown di bawah baris induknya (lihat `_expandedParentIds` &
  // `build()`), konsisten dgn pola produk bervarian di halaman kasir.
  Map<String, List<Product>> _variantsByParent = {};
  final Set<String> _expandedParentIds = {};
  Map<int, String> _groupNames = {};
  Map<String, Set<int>> _tagsByProduct = {};
  Map<String, int> _basePrices = {};
  Map<String, double> _baseStock = {};
  bool _loading = true;
  final Set<String> _pending = {};

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    final db = ref.read(databaseProvider);
    final results = await db.searchProducts(query);
    final groups = await db.getAllProductGroups();

    final variantsByParent = <String, List<Product>>{};
    for (final p in results) {
      if (p.parentProductId != null) {
        variantsByParent.putIfAbsent(p.parentProductId!, () => []).add(p);
      }
    }

    var topLevel = results.where((p) => p.parentProductId == null).toList();
    // Pencarian bisa cocok ke NAMA VARIAN saja (mis. "Merah") tanpa cocok ke
    // nama produk induknya — induk tetap WAJIB dimasukkan (diambil terpisah,
    // krn tidak ikut lolos filter nama `db.searchProducts`), supaya varian
    // yang dicari tidak hilang begitu saja (tidak ada baris induk utk
    // menaruh dropdown-nya).
    final missingParentIds = variantsByParent.keys
        .where((pid) => !topLevel.any((p) => p.id == pid))
        .toList();
    if (missingParentIds.isNotEmpty) {
      final extraParents = await (db.select(db.products)
            ..where((t) => t.id.isIn(missingParentIds)))
          .get();
      topLevel = [...topLevel, ...extraParents]
        ..sort((a, b) => a.name.compareTo(b.name));
    }

    final productIds = {
      ...topLevel.map((p) => p.id),
      for (final vs in variantsByParent.values) ...vs.map((v) => v.id),
    }.toList();
    final tags = await db.getProductGroupTagsFor(productIds);
    final basePrices = await db.getBaseUnitPrices();
    final baseStock = await db.getBaseUnitRealStock();
    if (!mounted) return;
    setState(() {
      _results = topLevel;
      _variantsByParent = variantsByParent;
      _groupNames = {for (final g in groups) g.id: g.name ?? ''};
      _tagsByProduct = tags;
      _basePrices = basePrices;
      _baseStock = baseStock;
      _loading = false;
    });
  }

  /// Set kategori lengkap (utama + tag) produk — dipakai render centang &
  /// keterangan "juga ada di kategori lain".
  Set<int> _membershipOf(Product p) => {
        if (p.productGroupId != null) p.productGroupId!,
        ...?_tagsByProduct[p.id],
      };

  Future<void> _toggle(Product p, bool value) async {
    setState(() => _pending.add(p.id));
    try {
      final db = ref.read(databaseProvider);
      await db.setProductGroupMembership(p.id, widget.groupId, value);
      // Cascade (permintaan user): centang produk INDUK -> semua variannya
      // ikut tercentang otomatis, supaya tidak perlu dicentang manual satu
      // per satu. Sengaja SATU ARAH saja — uncentang induk TIDAK ikut
      // mengeluarkan varian dari kategori ini (varian bisa saja sengaja
      // dipertahankan independen dari induknya).
      final cascadeVariants = value ? _variantsByParent[p.id] : null;
      if (cascadeVariants != null) {
        for (final v in cascadeVariants) {
          await db.setProductGroupMembership(v.id, widget.groupId, true);
        }
      }
      if (!mounted) return;
      setState(() {
        _patchMembership(p, value);
        if (cascadeVariants != null) {
          for (final v in cascadeVariants) {
            _patchMembership(v, true);
          }
        }
      });
    } finally {
      if (mounted) setState(() => _pending.remove(p.id));
    }
  }

  /// Produk BARU dapat kategori utama kalau sebelumnya kosong — refresh
  /// field `productGroupId` lokal supaya "juga di kategori lain" & status
  /// centang berikutnya konsisten tanpa reload penuh. Dipakai baik utk
  /// produk induk (di `_results`) maupun varian (di `_variantsByParent`).
  void _patchMembership(Product p, bool value) {
    if (value) {
      if (p.productGroupId == null) {
        _replaceProduct(p.copyWith(productGroupId: Value(widget.groupId)));
      } else if (p.productGroupId != widget.groupId) {
        _tagsByProduct.putIfAbsent(p.id, () => {}).add(widget.groupId);
      }
    } else {
      if (p.productGroupId == widget.groupId) {
        _replaceProduct(p.copyWith(productGroupId: const Value(null)));
      } else {
        _tagsByProduct[p.id]?.remove(widget.groupId);
      }
    }
  }

  void _replaceProduct(Product updated) {
    final idx = _results.indexWhere((e) => e.id == updated.id);
    if (idx != -1) {
      _results[idx] = updated;
      return;
    }
    for (final variants in _variantsByParent.values) {
      final vIdx = variants.indexWhere((e) => e.id == updated.id);
      if (vIdx != -1) {
        variants[vIdx] = updated;
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Produk — ${widget.groupName}'),
      ),
      body: Column(
        children: [
          inlineBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Cari produk…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) {
                setState(() => _loading = true);
                _load(v.trim());
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Text('Tidak ada produk ditemukan',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final p = _results[i];
                          final variants =
                              _variantsByParent[p.id] ?? const <Product>[];
                          final hasVariants = variants.isNotEmpty;
                          final expanded = _expandedParentIds.contains(p.id);
                          return Column(
                            children: [
                              _buildProductRow(
                                p,
                                scheme: scheme,
                                secondary: hasVariants
                                    ? IconButton(
                                        icon: Icon(expanded
                                            ? Icons.expand_less
                                            : Icons.expand_more),
                                        tooltip: 'Varian',
                                        onPressed: () => setState(() {
                                          if (expanded) {
                                            _expandedParentIds.remove(p.id);
                                          } else {
                                            _expandedParentIds.add(p.id);
                                          }
                                        }),
                                      )
                                    : null,
                              ),
                              // Dropdown varian inline — mendorong item di
                              // bawahnya, bukan popup. Sama pola dgn produk
                              // bervarian di halaman kasir.
                              if (expanded && hasVariants)
                                Container(
                                  color: scheme.surfaceContainerHighest
                                      .withOpacity(0.4),
                                  padding: const EdgeInsets.only(left: 32),
                                  child: Column(
                                    children: [
                                      for (final v in variants)
                                        _buildProductRow(v,
                                            scheme: scheme, dense: true),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  /// Satu baris `CheckboxListTile` produk (induk ATAU varian — keduanya
  /// `Product` biasa, punya membership independen). [secondary] dipakai
  /// utk tombol expand/collapse varian di baris induk.
  Widget _buildProductRow(
    Product p, {
    required ColorScheme scheme,
    Widget? secondary,
    bool dense = false,
  }) {
    final membership = _membershipOf(p);
    final selected = membership.contains(widget.groupId);
    final otherNames = membership
        .where((g) => g != widget.groupId)
        .map((g) => _groupNames[g])
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .toList();
    final price = _basePrices[p.id];
    final stock = _baseStock[p.id];
    final infoParts = <String>[
      if (price != null) formatRupiah(price),
      if (stock != null)
        'Stok ${stock.toStringAsFixed(stock.truncateToDouble() == stock ? 0 : 1)}',
    ];
    return CheckboxListTile(
      dense: dense,
      value: selected,
      onChanged: _pending.contains(p.id) ? null : (v) => _toggle(p, v ?? false),
      title: Text(p.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (infoParts.isNotEmpty)
            Text(infoParts.join(' · '), style: const TextStyle(fontSize: 12)),
          if (otherNames.isNotEmpty)
            Text('Juga ada di: ${otherNames.join(', ')}',
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic)),
        ],
      ),
      controlAffinity: ListTileControlAffinity.leading,
      secondary: secondary,
    );
  }
}
