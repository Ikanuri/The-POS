import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/widgets/inline_banner.dart';

final _searchQueryProvider = StateProvider<String>((ref) => '');
final _selectedGroupProvider = StateProvider<int?>((ref) => null);

final _productsStreamProvider = StreamProvider.family<List<Product>, (String, int?)>(
  (ref, args) {
    final db = ref.watch(databaseProvider);
    return db.watchProducts(query: args.$1, groupId: args.$2);
  },
);

final _groupsProvider = FutureProvider<List<ProductGroup>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.getAllProductGroups();
});

final _canEditProdukProvider = FutureProvider.autoDispose<bool>((ref) async {
  final device = ref.watch(deviceProvider);
  if (device.isOwner || device.deviceRole == 'asisten') return true;
  if (device.deviceRole != 'kasir') return false;
  return ref.watch(databaseProvider).isPermissionEnabled('input_stok');
});

class ProdukListScreen extends ConsumerStatefulWidget {
  const ProdukListScreen({super.key});

  @override
  ConsumerState<ProdukListScreen> createState() => _ProdukListScreenState();
}

class _ProdukListScreenState extends ConsumerState<ProdukListScreen>
    with InlineBannerStateMixin<ProdukListScreen> {
  /// Buka form produk lalu tampilkan banner sukses bila form mengembalikan
  /// pesan saat ditutup (mis. "Produk disimpan").
  Future<void> _openForm(String route) async {
    final result = await context.push<Object?>(route);
    if (result is String && result.isNotEmpty) showSuccess(result);
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(deviceProvider);
    final query = ref.watch(_searchQueryProvider);
    final groupId = ref.watch(_selectedGroupProvider);
    final productsAsync =
        ref.watch(_productsStreamProvider((query, groupId)));
    final groupsAsync = ref.watch(_groupsProvider);
    final baseCanEdit = device.isOwner || device.deviceRole == 'asisten';
    final canEdit =
        ref.watch(_canEditProdukProvider).valueOrNull ?? baseCanEdit;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produk'),
        actions: [
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: 'Kelola Kategori',
            onPressed: () => context.push('/produk/kategori'),
          ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Tambah Produk',
              onPressed: () => _openForm('/produk/baru'),
            ),
        ],
      ),
      body: Column(
        children: [
          inlineBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Cari nama atau kode produk…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => ref
                            .read(_searchQueryProvider.notifier)
                            .state = '',
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              onChanged: (v) =>
                  ref.read(_searchQueryProvider.notifier).state = v,
            ),
          ),
          groupsAsync.when(
            data: (groups) {
              final named = groups.where((g) => g.name != null).toList();
              if (named.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    _GroupChip(
                      label: 'Semua',
                      selected: groupId == null,
                      onTap: () => ref
                          .read(_selectedGroupProvider.notifier)
                          .state = null,
                    ),
                    ...named.map((g) => _GroupChip(
                          label: g.name!,
                          selected: groupId == g.id,
                          onTap: () => ref
                              .read(_selectedGroupProvider.notifier)
                              .state = g.id,
                        )),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          Expanded(
            child: productsAsync.when(
              data: (prods) {
                if (prods.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 64, color: scheme.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          query.isEmpty
                              ? 'Belum ada produk'
                              : 'Produk tidak ditemukan',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        if (canEdit && query.isEmpty) ...[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _openForm('/produk/baru'),
                            icon: const Icon(Icons.add),
                            label: const Text('Tambah Produk'),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: prods.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                  itemBuilder: (context, i) => _ProductTile(
                    product: prods[i],
                    canEdit: canEdit,
                    onOpen: _openForm,
                  ),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        side: BorderSide.none,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({
    required this.product,
    required this.canEdit,
    required this.onOpen,
  });
  final Product product;
  final bool canEdit;
  final Future<void> Function(String route) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(
          product.name.isNotEmpty ? product.name[0].toUpperCase() : '?',
          style: TextStyle(
              color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(product.name),
      subtitle: product.kodeProduk != null
          ? Text(product.kodeProduk!,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12))
          : null,
      trailing: canEdit
          ? IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => onOpen('/produk/${product.id}'),
            )
          : null,
      // Tetap bisa di-tap walau !canEdit: form membuka mode read-only
      // ("Detail Produk") untuk kasir tanpa izin input_stok.
      onTap: () => onOpen('/produk/${product.id}'),
    );
  }
}
