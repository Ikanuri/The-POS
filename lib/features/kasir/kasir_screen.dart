import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/database/app_database.dart';
import '../../core/models/cart_item.dart';
import '../../core/providers/device_provider.dart';
import '../../core/services/price_service.dart';
import '../../core/theme/app_theme.dart';
import 'cart_provider.dart';
import 'widgets/cart_sheet.dart';
import 'widgets/held_orders_sheet.dart';
import 'widgets/tx_history_sheet.dart';
import 'widgets/variant_sheet.dart';

final _kasirSearchProvider = StateProvider<String>((ref) => '');
final _kasirGridProvider = StateProvider<bool>((ref) => true);

final _heldCountProvider = StreamProvider<int>((ref) {
  return ref
      .watch(databaseProvider)
      .watchHeldOrders()
      .map((list) => list.length);
});

final _kasirProductsProvider =
    StreamProvider.family<List<Product>, String>((ref, query) {
  final db = ref.watch(databaseProvider);
  return db.watchProducts(query: query);
});

// Gradient palette for product avatars — cycles by first char code
const _kAvatarGradients = [
  [Color(0xFFD97757), Color(0xFFC96442)],
  [Color(0xFF4F7B5E), Color(0xFF3A6349)],
  [Color(0xFF4A6E94), Color(0xFF345880)],
  [Color(0xFF8E6B3E), Color(0xFF7A5A2F)],
  [Color(0xFF7B5EA7), Color(0xFF654E90)],
  [Color(0xFF4E8B8B), Color(0xFF3A7474)],
];

class KasirScreen extends ConsumerStatefulWidget {
  const KasirScreen({super.key});

  @override
  ConsumerState<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends ConsumerState<KasirScreen> {
  final _searchCtrl = TextEditingController();
  bool _scannerOpen = false;
  MobileScannerController? _scannerCtrl;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scannerCtrl?.dispose();
    super.dispose();
  }

  void _openScanner() {
    setState(() {
      _scannerOpen = true;
      _scannerCtrl = MobileScannerController();
    });
  }

  void _closeScanner() {
    _scannerCtrl?.dispose();
    setState(() {
      _scannerOpen = false;
      _scannerCtrl = null;
    });
  }

  Future<void> _handleBarcode(String barcode) async {
    _closeScanner();
    final db = ref.read(databaseProvider);
    final bc = await db.lookupBarcode(barcode);
    if (bc == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Barcode tidak ditemukan: $barcode')),
        );
      }
      return;
    }
    final unit = await (db.select(db.productUnits)
          ..where((t) => t.id.equals(bc.productUnitId)))
        .getSingleOrNull();
    if (unit == null || !mounted) return;
    final product = await (db.select(db.products)
          ..where((t) => t.id.equals(unit.productId)))
        .getSingleOrNull();
    if (product == null || !mounted) return;
    final priceService = PriceService(db);
    final resolved =
        await priceService.resolvePrice(productUnitId: unit.id, qty: 1);
    final unitType = await (db.select(db.unitTypes)
          ..where((t) => t.id.equals(unit.unitTypeId ?? 1)))
        .getSingleOrNull();
    ref.read(cartProvider.notifier).addItem(CartItem(
          productId: product.id,
          productUnitId: unit.id,
          productName: product.name,
          unitName: unitType?.name ?? 'Satuan',
          qty: 1,
          price: resolved.price,
          originalPrice: resolved.price,
          costPrice: resolved.costPrice,
          barcode: barcode,
        ));
  }

  void _showVariantSheet(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => VariantSheet(product: product),
    );
  }

  Future<void> _addSingleUnit(Product product) async {
    final db = ref.read(databaseProvider);
    final units = await db.getProductUnits(product.id);
    if (!mounted) return;
    if (units.length > 1) {
      _showVariantSheet(product);
      return;
    }
    final unit = units.isNotEmpty ? units.first : null;
    if (unit == null) return;
    final priceService = PriceService(db);
    final resolved =
        await priceService.resolvePrice(productUnitId: unit.id, qty: 1);
    final unitType = await (db.select(db.unitTypes)
          ..where((t) => t.id.equals(unit.unitTypeId ?? 1)))
        .getSingleOrNull();
    ref.read(cartProvider.notifier).addItem(CartItem(
          productId: product.id,
          productUnitId: unit.id,
          productName: product.name,
          unitName: unitType?.name ?? 'Satuan',
          qty: 1,
          price: resolved.price,
          originalPrice: resolved.price,
          costPrice: resolved.costPrice,
        ));
  }

  @override
  Widget build(BuildContext context) {
    if (_scannerOpen && _scannerCtrl != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Scan Barcode'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _closeScanner,
          ),
        ),
        body: MobileScanner(
          controller: _scannerCtrl!,
          onDetect: (capture) {
            final barcode = capture.barcodes.firstOrNull?.rawValue;
            if (barcode != null) _handleBarcode(barcode);
          },
        ),
      );
    }

    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final query = ref.watch(_kasirSearchProvider);
    final isGrid = ref.watch(_kasirGridProvider);
    final heldCount = ref.watch(_heldCountProvider).valueOrNull ?? 0;
    final productsAsync = ref.watch(_kasirProductsProvider(query));
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          _KasirTopbar(
            searchCtrl: _searchCtrl,
            onSearch: (v) => ref.read(_kasirSearchProvider.notifier).state = v,
            onScan: _openScanner,
            onHeld: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const HeldOrdersSheet(),
            ),
            onHistory: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const TxHistorySheet(),
            ),
            heldCount: heldCount,
            isGrid: isGrid,
            onToggleGrid: () =>
                ref.read(_kasirGridProvider.notifier).state = !isGrid,
          ),
          Expanded(
            child: productsAsync.when(
              data: (prods) {
                if (prods.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.inventory_2_outlined,
                              color: cs.onSurfaceVariant, size: 26),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          query.isEmpty ? 'Belum ada produk' : 'Produk tidak ditemukan',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (query.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('"$query"',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  );
                }
                if (isGrid) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 160,
                      mainAxisExtent: 118,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: prods.length,
                    itemBuilder: (_, i) => _ProductCard(
                      product: prods[i],
                      onTap: () => _addSingleUnit(prods[i]),
                      onLongPress: () => _showVariantSheet(prods[i]),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: prods.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, indent: 62, color: cs.outlineVariant),
                  itemBuilder: (_, i) => _ProductListTile(
                    product: prods[i],
                    onTap: () => _addSingleUnit(prods[i]),
                    onLongPress: () => _showVariantSheet(prods[i]),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _CartBar(
              total: cartNotifier.totalAmount,
              count: cart.length,
              onView: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const CartSheet(),
              ),
              onPay: () => context.go('/kasir/bayar'),
            ),
    );
  }
}

// ─── Topbar ──────────────────────────────────────────────────────────────────

class _KasirTopbar extends StatelessWidget {
  const _KasirTopbar({
    required this.searchCtrl,
    required this.onSearch,
    required this.onScan,
    required this.onHeld,
    required this.onHistory,
    required this.heldCount,
    required this.isGrid,
    required this.onToggleGrid,
  });

  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearch;
  final VoidCallback onScan;
  final VoidCallback onHeld;
  final VoidCallback onHistory;
  final int heldCount;
  final bool isGrid;
  final VoidCallback onToggleGrid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      color: cs.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, topPadding + 8, 12, 10),
            child: Row(
              children: [
                // Brand mark
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFD97757), Color(0xFFC96442)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A302416),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shopping_basket_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                // Inline search field
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: searchCtrl,
                    builder: (context, value, _) {
                      return TextField(
                        controller: searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Cari produk…',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: value.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () {
                                    searchCtrl.clear();
                                    onSearch('');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10,
                          ),
                          isDense: true,
                        ),
                        onChanged: onSearch,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 6),
                _TbBtn(icon: Icons.qr_code_scanner_rounded, onTap: onScan),
                const SizedBox(width: 4),
                _TbBtn(
                  icon: Icons.pause_circle_outline_rounded,
                  onTap: onHeld,
                  badgeCount: heldCount,
                ),
                const SizedBox(width: 4),
                _TbBtn(icon: Icons.history_rounded, onTap: onHistory),
                const SizedBox(width: 4),
                _TbBtn(
                  icon: isGrid
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded,
                  onTap: onToggleGrid,
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: cs.outlineVariant),
        ],
      ),
    );
  }
}

class _TbBtn extends StatelessWidget {
  const _TbBtn({required this.icon, required this.onTap, this.badgeCount = 0});

  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final child = Icon(icon, size: 18, color: cs.onSurfaceVariant);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant, width: 0.75),
        ),
        child: badgeCount > 0
            ? Badge(label: Text('$badgeCount'), child: child)
            : child,
      ),
    );
  }
}

// ─── Product grid card ────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onTap,
    required this.onLongPress,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gradIdx =
        (product.name.isEmpty ? 0 : product.name.codeUnitAt(0)) %
            _kAvatarGradients.length;
    final grad = _kAvatarGradients[gradIdx];

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant, width: 0.5),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gradient avatar
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: grad,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    product.name.isNotEmpty
                        ? product.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              if (product.kodeProduk != null) ...[
                const SizedBox(height: 2),
                Text(
                  product.kodeProduk!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Product list tile ────────────────────────────────────────────────────────

class _ProductListTile extends StatelessWidget {
  const _ProductListTile({
    required this.product,
    required this.onTap,
    required this.onLongPress,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gradIdx =
        (product.name.isEmpty ? 0 : product.name.codeUnitAt(0)) %
            _kAvatarGradients.length;
    final grad = _kAvatarGradients[gradIdx];

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: grad,
                ),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Center(
                child: Text(
                  product.name.isNotEmpty
                      ? product.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  if (product.kodeProduk != null)
                    Text(
                      product.kodeProduk!,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.add_circle_outline_rounded,
                size: 20, color: cs.primary.withOpacity(0.7)),
          ],
        ),
      ),
    );
  }
}

// ─── Cart bar ─────────────────────────────────────────────────────────────────

class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.total,
    required this.count,
    required this.onView,
    required this.onPay,
  });

  final int total;
  final int count;
  final VoidCallback onView;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + bottomPad),
      child: Row(
        children: [
          // Item count bubble
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppTheme.accent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Total
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  formatRupiah(total),
                  style: AppTheme.numStyle(context,
                      size: 16.5, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: onView,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                  side: BorderSide(color: cs.outlineVariant),
                  foregroundColor: cs.onSurface,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Lihat',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onPay,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Bayar',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
