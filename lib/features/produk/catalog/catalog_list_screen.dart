import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../kasir/cart_provider.dart';
import 'catalog_models.dart';
import 'catalog_share.dart';
import 'catalog_store.dart';

/// Daftar katalog tersimpan. Dibuka dari tombol "Katalog" di tab Produk.
/// Tombol "Buat Katalog" meminjam layar kasir dalam mode katalog.
class CatalogListScreen extends ConsumerWidget {
  const CatalogListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogs = ref.watch(catalogStoreProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Katalog')),
      body: catalogs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.collections_bookmark_outlined,
                        size: 56, color: cs.outlineVariant),
                    const SizedBox(height: 14),
                    Text('Belum ada katalog',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text(
                      'Buat katalog harga untuk diumumkan ke pelanggan via '
                      'WhatsApp. Tekan "Buat Katalog" lalu pilih produk seperti '
                      'di kasir.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: catalogs.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, indent: 16, color: cs.outlineVariant),
              itemBuilder: (_, i) => _CatalogTile(catalog: catalogs[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Mulai katalog baru: kosongkan keranjang katalog & konteks edit.
          ref.read(cartProvider(kCatalogCartId).notifier).clear();
          ref.read(catalogEditProvider.notifier).state = null;
          context.push('/produk/katalog/buat');
        },
        icon: const Icon(Icons.add),
        label: const Text('Buat Katalog'),
      ),
    );
  }
}

class _CatalogTile extends ConsumerWidget {
  const _CatalogTile({required this.catalog});
  final SavedCatalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.primary.withOpacity(0.12),
        child: Icon(Icons.sell_outlined, color: cs.primary, size: 20),
      ),
      title: Text(catalog.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${catalogDateText(catalog.createdAt)} · ${catalog.lines.length} produk',
        style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
      ),
      onTap: () => showCatalogPreviewSheet(
        context,
        ref,
        title: catalog.title,
        lines: catalog.lines,
        date: catalog.createdAt,
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (v) {
          if (v == 'edit') {
            _edit(context, ref);
          } else if (v == 'hapus') {
            _confirmDelete(context, ref);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'hapus', child: Text('Hapus')),
        ],
      ),
    );
  }

  /// Muat ulang katalog ke keranjang katalog & buka layar kasir mode katalog
  /// untuk diedit. Menyimpan akan memperbarui katalog yang sama.
  void _edit(BuildContext context, WidgetRef ref) {
    final items = catalogLinesToCartItems(catalog.lines);
    ref.read(cartProvider(kCatalogCartId).notifier).replaceAll(items);
    ref.read(catalogEditProvider.notifier).state = catalog;
    context.push('/produk/katalog/buat');
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Katalog?'),
        content: Text('"${catalog.title}" akan dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(catalogStoreProvider.notifier).remove(catalog.id);
    }
  }
}
