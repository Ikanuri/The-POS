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
    final productIds = results.map((p) => p.id).toList();
    final tags = await db.getProductGroupTagsFor(productIds);
    final basePrices = await db.getBaseUnitPrices();
    final baseStock = await db.getBaseUnitRealStock();
    if (!mounted) return;
    setState(() {
      _results = results;
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
      await ref
          .read(databaseProvider)
          .setProductGroupMembership(p.id, widget.groupId, value);
      if (!mounted) return;
      setState(() {
        // Produk BARU dapat kategori utama kalau sebelumnya kosong —
        // refresh field productGroupId lokal supaya "juga di kategori
        // lain" & status centang berikutnya konsisten tanpa reload penuh.
        if (value) {
          if (p.productGroupId == null) {
            final idx = _results.indexWhere((e) => e.id == p.id);
            if (idx != -1) {
              _results[idx] =
                  p.copyWith(productGroupId: Value(widget.groupId));
            }
          } else if (p.productGroupId != widget.groupId) {
            _tagsByProduct.putIfAbsent(p.id, () => {}).add(widget.groupId);
          }
        } else {
          if (p.productGroupId == widget.groupId) {
            final idx = _results.indexWhere((e) => e.id == p.id);
            if (idx != -1) {
              _results[idx] = p.copyWith(productGroupId: const Value(null));
            }
          } else {
            _tagsByProduct[p.id]?.remove(widget.groupId);
          }
        }
      });
    } finally {
      if (mounted) setState(() => _pending.remove(p.id));
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
                            style:
                                TextStyle(color: scheme.onSurfaceVariant)),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final p = _results[i];
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
                            if (stock != null) 'Stok ${stock.toStringAsFixed(
                                stock.truncateToDouble() == stock ? 0 : 1)}',
                          ];
                          return CheckboxListTile(
                            value: selected,
                            onChanged: _pending.contains(p.id)
                                ? null
                                : (v) => _toggle(p, v ?? false),
                            title: Text(p.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (infoParts.isNotEmpty)
                                  Text(infoParts.join(' · '),
                                      style: const TextStyle(fontSize: 12)),
                                if (otherNames.isNotEmpty)
                                  Text('Juga ada di: ${otherNames.join(', ')}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant,
                                          fontStyle: FontStyle.italic)),
                              ],
                            ),
                            controlAffinity:
                                ListTileControlAffinity.leading,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
