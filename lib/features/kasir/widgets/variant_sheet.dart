import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/cart_item.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/services/price_service.dart';
import '../../../core/theme/app_theme.dart';
import '../cart_provider.dart';

class VariantSheet extends ConsumerStatefulWidget {
  const VariantSheet({
    super.key,
    required this.product,
    this.customerGroupId,
  });

  final Product product;
  final String? customerGroupId;

  @override
  ConsumerState<VariantSheet> createState() => _VariantSheetState();
}

class _VariantSheetState extends ConsumerState<VariantSheet> {
  List<_VariantRow> _variants = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final priceService = PriceService(db);
    final units = await db.getProductUnits(widget.product.id);
    final rows = <_VariantRow>[];
    for (final u in units) {
      final unitType = await (db.select(db.unitTypes)
            ..where((t) => t.id.equals(u.unitTypeId ?? 1)))
          .getSingleOrNull();
      final resolved = await priceService.resolvePrice(
        productUnitId: u.id,
        qty: 1,
        customerGroupId: widget.customerGroupId,
      );
      final stock = await db.currentStock(u.id);
      final barcodes = await db.getProductBarcodes(u.id);
      rows.add(_VariantRow(
        unit: u,
        unitName: unitType?.name ?? 'Satuan',
        price: resolved.price,
        costPrice: resolved.costPrice,
        stock: stock,
        barcode: barcodes.where((b) => b.isPrimary).map((b) => b.barcode).firstOrNull,
      ));
    }
    if (mounted) {
      setState(() {
        _variants = rows;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.product.name,
                    style: Theme.of(context).textTheme.titleMedium),
                if (widget.product.kodeProduk != null)
                  Text(widget.product.kodeProduk!,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ..._variants.map((v) => _VariantTile(
                  productId: widget.product.id,
                  productName: widget.product.name,
                  variant: v,
                )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _VariantRow {
  _VariantRow({
    required this.unit,
    required this.unitName,
    required this.price,
    required this.costPrice,
    required this.stock,
    this.barcode,
  });

  final ProductUnit unit;
  final String unitName;
  final int price;
  final int costPrice;
  final double stock;
  final String? barcode;
}

class _VariantTile extends ConsumerWidget {
  const _VariantTile({
    required this.productId,
    required this.productName,
    required this.variant,
  });

  final String productId;
  final String productName;
  final _VariantRow variant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final outOfStock = variant.unit.isNonStock
        ? false
        : variant.stock <= 0;

    return ListTile(
      title: Text(variant.unitName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatRupiah(variant.price),
              style: TextStyle(
                  color: scheme.primary, fontWeight: FontWeight.w600)),
          Text(
            outOfStock
                ? 'Stok habis'
                : 'Stok: ${variant.stock % 1 == 0 ? variant.stock.toInt() : variant.stock}',
            style: TextStyle(
                fontSize: 11,
                color: outOfStock ? scheme.error : scheme.onSurfaceVariant),
          ),
        ],
      ),
      trailing: FilledButton.tonal(
        onPressed: outOfStock
            ? null
            : () {
                ref.read(cartProvider.notifier).addItem(CartItem(
                      productId: productId,
                      productUnitId: variant.unit.id,
                      productName: productName,
                      unitName: variant.unitName,
                      qty: 1,
                      price: variant.price,
                      originalPrice: variant.price,
                      costPrice: variant.costPrice,
                      barcode: variant.barcode,
                    ));
                Navigator.of(context).pop();
              },
        child: const Text('Tambah'),
      ),
    );
  }
}
