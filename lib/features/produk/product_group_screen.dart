import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/widgets/inline_banner.dart';

final _groupsProvider = FutureProvider.autoDispose<List<ProductGroup>>((ref) {
  return ref.watch(databaseProvider).getAllProductGroups();
});

class ProductGroupScreen extends ConsumerStatefulWidget {
  const ProductGroupScreen({super.key});

  @override
  ConsumerState<ProductGroupScreen> createState() => _ProductGroupScreenState();
}

class _ProductGroupScreenState extends ConsumerState<ProductGroupScreen>
    with InlineBannerStateMixin<ProductGroupScreen> {
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};

  void _enterSelection(int id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  Future<void> _showBulkAddDialog() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Massal'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Satu kategori per baris',
            hintText: 'Minuman\nMakanan\nSnack',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final names = ctrl.text.split('\n');
    final added = await ref.read(databaseProvider).addProductGroups(names);
    if (added == 0) return;
    ref.invalidate(_groupsProvider);
    if (mounted) showSuccess('$added kategori ditambahkan');
  }

  Future<void> _confirmBulkDelete(List<ProductGroup> allGroups) async {
    final db = ref.read(databaseProvider);
    final selected =
        allGroups.where((g) => _selectedIds.contains(g.id)).toList();
    var totalProducts = 0;
    for (final g in selected) {
      totalProducts += await db.countProductsInGroup(g.id);
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus ${selected.length} kategori?'),
        content: Text(totalProducts > 0
            ? '$totalProducts produk menggunakan kategori-kategori ini dan '
                'akan menjadi tanpa kategori.'
            : 'Kategori terpilih akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await db.deleteProductGroups(selected.map((g) => g.id).toList());
    ref.invalidate(_groupsProvider);
    if (mounted) {
      showSuccess('${selected.length} kategori dihapus');
      _exitSelection();
    }
  }

  Future<void> _showAddDialog() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Kategori'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nama Kategori *',
            hintText: 'Contoh: Minuman',
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    await ref.read(databaseProvider).addProductGroup(ctrl.text.trim());
    ref.invalidate(_groupsProvider);
    if (mounted) showSuccess('Kategori "${ctrl.text.trim()}" ditambahkan');
  }

  Future<void> _showRenameDialog(ProductGroup group) async {
    final ctrl = TextEditingController(text: group.name);
    ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah Nama Kategori'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nama Kategori *'),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    if (ctrl.text.trim() == group.name) return;
    await ref.read(databaseProvider).renameProductGroup(group.id, ctrl.text.trim());
    ref.invalidate(_groupsProvider);
    if (mounted) showSuccess('Nama diperbarui');
  }

  /// Item 52 — tap kategori (di luar mode pilih-utk-hapus) buka layar
  /// pilih produk multi-select, produk terpilih ditugaskan ke kategori ini.
  Future<void> _openAssignProducts(ProductGroup group) async {
    final assigned = await context.push<int>(
      '/produk/kategori/${group.id}/pilih-produk',
      extra: group.name ?? '',
    );
    if (assigned != null && assigned > 0 && mounted) {
      showSuccess('$assigned produk dipindahkan ke "${group.name}"');
    }
  }

  Future<void> _confirmDelete(ProductGroup group) async {
    final db = ref.read(databaseProvider);
    final count = await db.countProductsInGroup(group.id);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus "${group.name}"?'),
        content: count > 0
            ? Text(
                '$count produk menggunakan kategori ini dan akan menjadi tanpa kategori.')
            : const Text('Kategori akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await db.deleteProductGroup(group.id);
    ref.invalidate(_groupsProvider);
    if (mounted) showSuccess('Kategori "${group.name}" dihapus');
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(_groupsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Batal pilih',
                onPressed: _exitSelection,
              ),
              title: Text('${_selectedIds.length} dipilih'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Hapus Terpilih',
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => _confirmBulkDelete(
                          groupsAsync.valueOrNull ?? const []),
                ),
              ],
            )
          : AppBar(
              title: const Text('Kelola Kategori'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.playlist_add),
                  tooltip: 'Tambah Massal',
                  onPressed: _showBulkAddDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Tambah Kategori',
                  onPressed: _showAddDialog,
                ),
              ],
            ),
      body: Column(
        children: [
          inlineBanner(),
          Expanded(
            child: groupsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (groups) {
                if (groups.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.label_off_outlined,
                            size: 56, color: scheme.outlineVariant),
                        const SizedBox(height: 12),
                        const Text('Belum ada kategori'),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _showAddDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Tambah Kategori'),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16),
                  itemBuilder: (_, i) {
                    final g = groups[i];
                    final selected = _selectedIds.contains(g.id);
                    return ListTile(
                      onLongPress: _selectionMode
                          ? null
                          : () => _enterSelection(g.id),
                      onTap: _selectionMode
                          ? () => _toggleSelected(g.id)
                          : () => _openAssignProducts(g),
                      leading: _selectionMode
                          ? Checkbox(
                              value: selected,
                              onChanged: (_) => _toggleSelected(g.id),
                            )
                          : CircleAvatar(
                              backgroundColor: scheme.secondaryContainer,
                              child: Text(
                                g.name![0].toUpperCase(),
                                style: TextStyle(
                                    color: scheme.onSecondaryContainer),
                              ),
                            ),
                      title: Text(g.name!),
                      trailing: _selectionMode
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 20),
                                  tooltip: 'Ubah nama',
                                  onPressed: () => _showRenameDialog(g),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline,
                                      size: 20, color: scheme.error),
                                  tooltip: 'Hapus',
                                  onPressed: () => _confirmDelete(g),
                                ),
                              ],
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
