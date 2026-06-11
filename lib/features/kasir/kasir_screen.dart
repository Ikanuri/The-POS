import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final resolved = await priceService.resolvePrice(
        productUnitId: unit.id, qty: 1);
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
    final resolved = await priceService.resolvePrice(
        productUnitId: unit.id, qty: 1);
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
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final query = ref.watch(_kasirSearchProvider);
    final isGrid = ref.watch(_kasirGridProvider);
    final productsAsync = ref.watch(_kasirProductsProvider(query));
    final scheme = Theme.of(context).colorScheme;

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

    final heldCount = ref.watch(_heldCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kasir'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan Barcode',
            onPressed: _openScanner,
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: heldCount > 0,
              label: Text('$heldCount'),
              child: const Icon(Icons.pause_circle_outline),
            ),
            tooltip: 'Pesanan Ditahan',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const HeldOrdersSheet(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Riwayat Transaksi',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const TxHistorySheet(),
            ),
          ),
          IconButton(
            icon: Icon(isGrid ? Icons.view_list : Icons.grid_view),
            tooltip: isGrid ? 'Tampilan List' : 'Tampilan Grid',
            onPressed: () =>
                ref.read(_kasirGridProvider.notifier).state = !isGrid,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Cari produk atau scan barcode…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(_kasirSearchProvider.notifier).state = '';
                        },
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              onChanged: (v) =>
                  ref.read(_kasirSearchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: productsAsync.when(
              data: (prods) {
                if (prods.isEmpty) {
                  return Center(
                    child: Text(
                      query.isEmpty
                          ? 'Belum ada produk'
                          : 'Produk tidak ditemukan',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  );
                }
                if (isGrid) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 160,
                      mainAxisExtent: 110,
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
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: prods.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 56),
                  itemBuilder: (_, i) => _ProductListTile(
                    product: prods[i],
                    onTap: () => _addSingleUnit(prods[i]),
                    onLongPress: () => _showVariantSheet(prods[i]),
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
      bottomNavigationBar: cart.isEmpty
          ? null
          : _CartBar(
              total: cartNotifier.totalAmount,
              count: cart.length,
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const CartSheet(),
              ),
            ),
    );
  }
}

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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  product.name.isNotEmpty
                      ? product.name[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
              style:
                  TextStyle(color: scheme.onSurfaceVariant, fontSize: 11))
          : null,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.total,
    required this.count,
    required this.onTap,
  });

  final int total;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Badge(
                label: Text('$count'),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              const Text(
                'Lihat Keranjang',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                formatRupiah(total),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
