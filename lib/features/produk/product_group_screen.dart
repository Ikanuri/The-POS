import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      appBar: AppBar(
        title: const Text('Kelola Kategori'),
        actions: [
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
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scheme.secondaryContainer,
                        child: Text(
                          g.name![0].toUpperCase(),
                          style:
                              TextStyle(color: scheme.onSecondaryContainer),
                        ),
                      ),
                      title: Text(g.name!),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
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
