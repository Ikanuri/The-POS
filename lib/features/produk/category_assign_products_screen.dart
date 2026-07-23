import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/widgets/inline_banner.dart';

/// Item 52 — dari layar Kelola Kategori, tap sebuah kategori membuka layar
/// ini: pilih banyak produk (multi-select) sekaligus, lalu ditugaskan ke
/// kategori itu. Produk yang SUDAH punya kategori lain tetap muncul & boleh
/// dipilih (kategorinya akan DITIMPA) — keputusan eksplisit user, bukan
/// dibatasi ke produk "Tanpa Kategori" saja.
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
  final Set<String> _selectedIds = {};
  bool _loading = true;
  bool _saving = false;

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
    if (!mounted) return;
    setState(() {
      _results = results;
      _groupNames = {for (final g in groups) g.id: g.name ?? ''};
      _loading = false;
    });
  }

  Future<void> _apply() async {
    if (_selectedIds.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(databaseProvider)
          .assignProductsToGroup(_selectedIds.toList(), widget.groupId);
      if (mounted) Navigator.of(context).pop(_selectedIds.length);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Pilih Produk — ${widget.groupName}'),
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
          if (_selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${_selectedIds.length} produk dipilih',
                    style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
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
                          final selected = _selectedIds.contains(p.id);
                          final currentGroupName =
                              p.productGroupId != null
                                  ? _groupNames[p.productGroupId]
                                  : null;
                          final isSameGroup =
                              p.productGroupId == widget.groupId;
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (_) {
                              setState(() {
                                if (selected) {
                                  _selectedIds.remove(p.id);
                                } else {
                                  _selectedIds.add(p.id);
                                }
                              });
                            },
                            title: Text(p.name),
                            subtitle: isSameGroup
                                ? const Text('Sudah di kategori ini',
                                    style: TextStyle(fontSize: 12))
                                : (currentGroupName != null &&
                                        currentGroupName.isNotEmpty
                                    ? Text('Saat ini: $currentGroupName',
                                        style:
                                            const TextStyle(fontSize: 12))
                                    : null),
                            controlAffinity:
                                ListTileControlAffinity.leading,
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _selectedIds.isEmpty || _saving ? null : _apply,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Terapkan ke ${_selectedIds.length} Produk'),
          ),
        ),
      ),
    );
  }
}
