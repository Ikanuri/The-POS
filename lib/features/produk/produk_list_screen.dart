import '../../core/widgets/app_filter_chip.dart';
import '../../core/services/kasir_sticker_service.dart';
import '../../core/widgets/app_empty_state.dart';
import '../kasir/kasir_screen.dart' show kasirStickerProvider;
import '../../core/theme/app_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/labeled_tool_button.dart';
import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/inline_banner.dart';
import '../shell/sync_status_banner.dart';
import '../../core/theme/app_overlays.dart';

final _searchQueryProvider = StateProvider<String>((ref) => '');
final _selectedGroupProvider = StateProvider<int?>((ref) => null);

final _productsStreamProvider =
    StreamProvider.family<List<Product>, (String, int?)>(
  (ref, args) {
    final db = ref.watch(databaseProvider);
    return db.watchProducts(query: args.$1, groupId: args.$2);
  },
);

final _groupsProvider = FutureProvider<List<ProductGroup>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.getAllProductGroups();
});

/// Harga dasar tiap produk (satuan dasar, tier minQty=1) — ditampilkan di
/// bawah nama produk di daftar. Item 17 — StreamProvider reaktif (bukan
/// snapshot sekali) supaya langsung ikut berubah begitu harga diedit di
/// form Produk, walau layar daftar ini tidak pernah benar-benar ditutup
/// (Navigator.push tidak dispose widget di baliknya).
final _basePricesProvider = StreamProvider.autoDispose<Map<String, int>>((ref) {
  return ref.watch(databaseProvider).watchBaseUnitPrices();
});

/// Item 11 — filter "Stok Menipis" aktif/tidak, jumlah untuk badge, & set id.
final _lowStockFilterProvider = StateProvider<bool>((ref) => false);
final _lowStockCountProvider = StreamProvider<int>((ref) {
  return ref.watch(databaseProvider).watchLowStockCount();
});
final _lowStockIdsProvider = FutureProvider.autoDispose<Set<String>>((ref) {
  // Re-hitung saat daftar produk berubah (mis. stok disesuaikan).
  ref.watch(_lowStockCountProvider);
  return ref.watch(databaseProvider).getLowStockProductIds();
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
    final productsAsync = ref.watch(_productsStreamProvider((query, groupId)));
    final groupsAsync = ref.watch(_groupsProvider);
    final lowStockFilter = ref.watch(_lowStockFilterProvider);
    final lowStockCount = ref.watch(_lowStockCountProvider).valueOrNull ?? 0;
    final lowStockIds =
        ref.watch(_lowStockIdsProvider).valueOrNull ?? const <String>{};
    final basePrices =
        ref.watch(_basePricesProvider).valueOrNull ?? const <String, int>{};
    final baseCanEdit = device.isOwner || device.deviceRole == 'asisten';
    final canEdit =
        ref.watch(_canEditProdukProvider).valueOrNull ?? baseCanEdit;
    final scheme = Theme.of(context).colorScheme;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shown = productsAsync.valueOrNull;
    final shownCount = shown == null
        ? null
        : (lowStockFilter
            ? shown.where((p) => lowStockIds.contains(p.id)).length
            : shown.length);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 18,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(shownCount == null ? ' ' : '$shownCount produk',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant)),
            Text('Produk',
                style: AppTheme.numStyle(context,
                    size: 21, weight: FontWeight.w600)),
          ],
        ),
        actions: [
          if (canEdit)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Material(
                color: scheme.primary,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  tooltip: 'Tambah Produk',
                  onPressed: () => _openForm('/produk/baru'),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          const SyncStatusBanner(),
          inlineBanner(),
          // Item 92 — tombol pintas berlabel (pola toolbar Kasir), kini satu
          // kartu dgn ikon bulat berwarna fungsi (gaya landing).
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    LabeledToolButton(
                      round: true,
                      labelWidth: 62,
                      icon: Icons.inventory_2_outlined,
                      label: 'Cek Stok',
                      tooltip: 'Cek Stok',
                      fg: AppTheme.scanFg,
                      bg: AppTheme.scanBg,
                      onTap: () => context.push('/produk/cek-stok'),
                    ),
                    LabeledToolButton(
                      round: true,
                      labelWidth: 62,
                      icon: Icons.sync_alt_outlined,
                      label: 'Sinkron Harga',
                      tooltip: 'Sinkron Harga',
                      fg: AppTheme.riwayatFg,
                      bg: AppTheme.riwayatBg,
                      onTap: () => context.push('/produk/sinkron-harga'),
                    ),
                    LabeledToolButton(
                      round: true,
                      labelWidth: 62,
                      icon: Icons.label_outline,
                      label: 'Kelola Kategori',
                      tooltip: 'Kelola Kategori',
                      fg: AppTheme.antrianFg,
                      bg: AppTheme.antrianBg,
                      onTap: () => context.push('/produk/kategori'),
                    ),
                    // Revisi 3 (permintaan user): pindah dari Pengaturan ke
                    // sini. Route TETAP `/pengaturan/kategori-harga`.
                    LabeledToolButton(
                      round: true,
                      labelWidth: 62,
                      icon: Icons.sell_outlined,
                      label: 'Kategori Harga',
                      tooltip: 'Kategori Harga',
                      fg: AppTheme.changeFg,
                      bg: AppTheme.changeBg,
                      onTap: () => context.push('/pengaturan/kategori-harga'),
                    ),
                    LabeledToolButton(
                      round: true,
                      labelWidth: 62,
                      icon: Icons.collections_bookmark_outlined,
                      label: 'Katalog',
                      tooltip: 'Katalog',
                      fg: AppTheme.laciFg,
                      bg: AppTheme.laciBg,
                      onTap: () => context.push('/produk/katalog'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: AppStyle.pillSearch(
              context,
              TextField(
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
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  isDense: true,
                ),
                onChanged: (v) =>
                    ref.read(_searchQueryProvider.notifier).state = v,
              ),
            ),
          ),
          groupsAsync.when(
            data: (groups) {
              final named = groups.where((g) => g.name != null).toList();
              if (named.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  children: [
                    if (lowStockCount > 0)
                      _GroupChip(
                        label: 'Stok Menipis ($lowStockCount)',
                        selected: lowStockFilter,
                        onTap: () => ref
                            .read(_lowStockFilterProvider.notifier)
                            .state = !lowStockFilter,
                      ),
                    _GroupChip(
                      label: 'Semua',
                      selected: groupId == null && !lowStockFilter,
                      onTap: () {
                        ref.read(_lowStockFilterProvider.notifier).state =
                            false;
                        ref.read(_selectedGroupProvider.notifier).state = null;
                      },
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
              data: (allProds) {
                final prods = lowStockFilter
                    ? allProds.where((p) => lowStockIds.contains(p.id)).toList()
                    : allProds;
                if (prods.isEmpty) {
                  return AppEmptyState(
                    query.isEmpty
                        ? 'Belum ada produk'
                        : 'Produk tidak ditemukan',
                    icon: Icons.inventory_2_outlined,
                    sticker: ref
                        .watch(kasirStickerProvider(query.isEmpty
                            ? KasirStickerSlot.empty
                            : KasirStickerSlot.notFound))
                        .valueOrNull,
                    action: (canEdit && query.isEmpty)
                        ? FilledButton.icon(
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 48)),
                            onPressed: () => _openForm('/produk/baru'),
                            icon: const Icon(Icons.add),
                            label: const Text('Tambah Produk'),
                          )
                        : null,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                  itemCount: prods.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _ProductTile(
                    product: prods[i],
                    canEdit: canEdit,
                    onOpen: _openForm,
                    basePrice: basePrices[prods[i].id],
                    lowStock: lowStockIds.contains(prods[i].id),
                    isDark: isDark,
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: AppFilterChip(label: label, selected: selected, onTap: onTap),
      );
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({
    required this.product,
    required this.canEdit,
    required this.onOpen,
    this.basePrice,
    this.lowStock = false,
    this.isDark = false,
  });
  final Product product;
  final bool canEdit;
  final Future<void> Function(String route) onOpen;

  /// Harga dasar (satuan dasar, tier minQty=1) — null bila produk belum
  /// punya satuan/harga sama sekali.
  final int? basePrice;

  /// Stok di bawah minimum -> lencana "Menipis".
  final bool lowStock;
  final bool isDark;

  Future<void> _confirmDeactivate(BuildContext context, WidgetRef ref) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nonaktifkan Produk?'),
        content: const Text(
            'Produk tidak akan muncul di katalog kasir. Data tetap tersimpan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Nonaktifkan')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(databaseProvider).deactivateProduct(product.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tile = ListTile(
      contentPadding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      leading: CircleAvatar(
        radius: 21,
        backgroundColor: scheme.primary.withOpacity(0.13),
        child: Text(
          product.name.isNotEmpty ? product.name[0].toUpperCase() : '?',
          style: TextStyle(
              color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      title: Text(product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
      subtitle: (product.kodeProduk != null || lowStock)
          ? Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (product.kodeProduk != null)
                    Text(product.kodeProduk!,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12)),
                  if (lowStock)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppTheme.stockWarnBg(isDark),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('Menipis',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.stockWarnFg(isDark))),
                    ),
                ],
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (basePrice != null)
            Text(formatRupiah(basePrice!),
                style: AppTheme.numStyle(context,
                    size: 14.5, weight: FontWeight.w600, color: scheme.primary)),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 19),
              onPressed: () => onOpen('/produk/${product.id}'),
            ),
        ],
      ),
      // Tetap bisa di-tap walau !canEdit: form membuka mode read-only
      // ("Detail Produk") untuk kasir tanpa izin input_stok.
      onTap: () => onOpen('/produk/${product.id}'),
    );

    if (!canEdit) return Card(margin: EdgeInsets.zero, child: tile);

    // Geser ke kiri untuk nonaktifkan — pola sama seperti hapus pelanggan.
    // Bukan hard-delete (tidak ada fungsi itu di DB): "Nonaktifkan" = sama
    // persis logika tombol Nonaktifkan di produk_form_screen.dart, cuma
    // dipanggil lebih cepat lewat swipe.
    return Card(
      margin: EdgeInsets.zero,
      child: Dismissible(
      key: ValueKey(product.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _confirmDeactivate(context, ref);
        return false; // stream akan memperbarui daftar sendiri
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: scheme.errorContainer,
        child:
            Icon(Icons.visibility_off_outlined, color: scheme.onErrorContainer),
      ),
      child: tile,
    ),
    );
  }
}
