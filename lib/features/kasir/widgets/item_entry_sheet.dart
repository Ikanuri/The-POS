import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/cart_item.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/services/price_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_formatters.dart';
import '../cart_provider.dart';

/// Modal entri item: pilih satuan (harga lain), atur qty & harga, lalu
/// tambahkan / perbarui keranjang. Menggantikan VariantSheet lama dengan
/// kemampuan edit qty + harga langsung.
class ItemEntrySheet extends ConsumerStatefulWidget {
  const ItemEntrySheet({
    super.key,
    required this.product,
    this.customerGroupId,
  });

  final Product product;
  final String? customerGroupId;

  @override
  ConsumerState<ItemEntrySheet> createState() => _ItemEntrySheetState();
}

class _UnitOption {
  _UnitOption({
    required this.unit,
    required this.unitName,
    required this.basePrice,
    required this.costPrice,
    required this.stock,
    required this.tiers,
    this.barcode,
  });

  final ProductUnit unit;
  final String unitName;
  final int basePrice;
  final int costPrice;
  final double stock;
  final List<PriceTier> tiers; // minQty DESC
  final String? barcode;
}

class _ItemEntrySheetState extends ConsumerState<ItemEntrySheet> {
  bool _loading = true;
  bool _canOverride = false;
  List<_UnitOption> _options = [];
  int _selectedIdx = 0;

  double _qty = 1;
  int _price = 0;
  bool _priceOverridden = false;

  final _priceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final priceService = PriceService(db);

    bool canOverride = device.deviceRole != 'kasir';
    if (!canOverride) {
      canOverride = await db.isPermissionEnabled('override_harga');
    }

    final units = await db.getProductUnits(widget.product.id);
    final opts = <_UnitOption>[];
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
      final tiers = await db.getPriceTiers(u.id);
      final barcodes = await db.getProductBarcodes(u.id);
      opts.add(_UnitOption(
        unit: u,
        unitName: unitType?.name ?? 'Satuan',
        basePrice: resolved.price,
        costPrice: resolved.costPrice,
        stock: stock,
        tiers: tiers,
        barcode: barcodes
            .where((b) => b.isPrimary)
            .map((b) => b.barcode)
            .firstOrNull,
      ));
    }

    if (!mounted) return;

    // Jika item ini sudah ada di keranjang, prefill qty & harga-nya.
    final cart = ref.read(cartProvider);
    var selIdx = 0;
    double qty = 1;
    int price = opts.isNotEmpty ? opts.first.basePrice : 0;
    bool overridden = false;
    for (var i = 0; i < opts.length; i++) {
      final existing =
          cart.where((c) => c.productUnitId == opts[i].unit.id).firstOrNull;
      if (existing != null) {
        selIdx = i;
        qty = existing.qty;
        price = existing.price;
        overridden = existing.priceOverridden;
        break;
      }
    }
    if (opts.isNotEmpty && !overridden) price = opts[selIdx].basePrice;

    setState(() {
      _options = opts;
      _canOverride = canOverride;
      _selectedIdx = selIdx;
      _qty = qty;
      _price = price;
      _priceOverridden = overridden;
      _loading = false;
      _priceCtrl.text = ThousandsSeparatorFormatter.format(price);
      _qtyCtrl.text = _fmtQty(qty);
    });
  }

  String _fmtQty(double q) => q % 1 == 0 ? q.toInt().toString() : q.toString();

  _UnitOption? get _sel =>
      _options.isEmpty ? null : _options[_selectedIdx];

  void _selectUnit(int idx) {
    setState(() {
      _selectedIdx = idx;
      _priceOverridden = false;
      _price = _options[idx].basePrice;
      _priceCtrl.text = ThousandsSeparatorFormatter.format(_price);
    });
  }

  void _applyTierPrice(int price) {
    setState(() {
      _price = price;
      _priceOverridden = price != _sel!.basePrice;
      _priceCtrl.text = ThousandsSeparatorFormatter.format(price);
    });
  }

  void _setQty(double q) {
    setState(() {
      _qty = q.clamp(0, 9999);
      _qtyCtrl.text = _fmtQty(_qty);
    });
  }

  void _submit() {
    final sel = _sel;
    if (sel == null) return;
    final notifier = ref.read(cartProvider.notifier);
    notifier.setItem(CartItem(
      productId: widget.product.id,
      productUnitId: sel.unit.id,
      productName: widget.product.name,
      unitName: sel.unitName,
      qty: _qty,
      price: _price,
      originalPrice: sel.basePrice,
      costPrice: sel.costPrice,
      priceOverridden: _priceOverridden,
      barcode: sel.barcode,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: _loading
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.product.name,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (_sel != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: scheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Satuan: ${_sel!.unitName}',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSecondaryContainer),
                                ),
                              ),
                            if (widget.product.kodeProduk != null)
                              Text('Kode: ${widget.product.kodeProduk!}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Harga lain (satuan + tier) ────────────────────────
                  if (_options.length > 1 ||
                      (_sel?.tiers.length ?? 0) > 1) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Pilih harga',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant)),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 64,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (var i = 0; i < _options.length; i++)
                            _PriceChip(
                              label: _options[i].unitName,
                              price: _options[i].basePrice,
                              selected: i == _selectedIdx && !_priceOverridden,
                              onTap: () => _selectUnit(i),
                            ),
                          // Tier qty untuk satuan terpilih (mis. grosir).
                          if (_sel != null)
                            for (final t in _sel!.tiers.reversed)
                              if (t.minQty > 1)
                                _PriceChip(
                                  label:
                                      '≥${_fmtQty(t.minQty.toDouble())} ${_sel!.unitName}',
                                  price: t.price,
                                  selected:
                                      _priceOverridden && _price == t.price,
                                  onTap: () => _applyTierPrice(t.price),
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Stok satuan terpilih ──────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          _sel == null
                              ? ''
                              : _sel!.unit.isNonStock
                                  ? 'Non-stok'
                                  : 'Stok ${_fmtQty(_sel!.stock)} ${_sel!.unitName}',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Qty & Harga input ─────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Qty stepper
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Jumlah',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline,
                                        size: 24),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _setQty(_qty - 1),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: _qtyCtrl,
                                      textAlign: TextAlign.center,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding:
                                            EdgeInsets.symmetric(vertical: 8),
                                      ),
                                      onChanged: (v) {
                                        final q = double.tryParse(v.trim());
                                        setState(() {
                                          _qty = (q != null && q >= 0) ? q.clamp(0, 9999) : 0;
                                        });
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline,
                                        size: 24),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _setQty(_qty + 1),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Harga input
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('Harga',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant)),
                                  if (_priceOverridden) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.edit,
                                        size: 11, color: scheme.tertiary),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _priceCtrl,
                                readOnly: !_canOverride,
                                keyboardType: TextInputType.number,
                                inputFormatters: const [
                                  ThousandsSeparatorFormatter()
                                ],
                                decoration: InputDecoration(
                                  isDense: true,
                                  prefixText: 'Rp ',
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 10),
                                  suffixIcon: !_canOverride
                                      ? Icon(Icons.lock_outline,
                                          size: 14,
                                          color: scheme.onSurfaceVariant)
                                      : null,
                                ),
                                onChanged: (v) {
                                  final p =
                                      ThousandsSeparatorFormatter.parseValue(v);
                                  _price = p;
                                  _priceOverridden =
                                      _sel != null && p != _sel!.basePrice;
                                  setState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Subtotal + submit ─────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Subtotal',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant)),
                            Text(
                              formatRupiah((_price * _qty).round()),
                              style: AppTheme.numStyle(context,
                                  size: 18, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed: _qty > 0 ? _submit : null,
                            child: Text(_qty > 0
                                ? 'Tambah ke Keranjang'
                                : 'Atur jumlah'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  const _PriceChip({
    required this.label,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withOpacity(0.12)
                : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.4 : 0.75,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatRupiah(price),
                style: AppTheme.numStyle(context,
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: selected ? scheme.primary : scheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

