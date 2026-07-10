import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    this.cartId = kMainCartId,
  });

  final Product product;
  final String cartId;

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
    this.altPrices = const [],
    this.barcode,
  });

  final ProductUnit unit;
  final String unitName;
  final int basePrice;
  final int costPrice;
  final double stock;
  final List<PriceTier> tiers; // minQty DESC
  /// Harga alternatif berlabel (bukan tier qty) — mis. "Harga Toko A".
  final List<AltPrice> altPrices;
  final String? barcode;
}

/// Varian (produk anak) yang bisa ditambahkan sebagai item add-on bersarang.
class _VariantOption {
  _VariantOption({
    required this.product,
    required this.unitId,
    required this.unitName,
    required this.price,
    required this.costPrice,
    this.barcode,
  });

  final Product product;
  final String unitId;
  final String unitName;
  final int price;
  final int costPrice;
  final String? barcode;
}

class _ItemEntrySheetState extends ConsumerState<ItemEntrySheet> {
  bool _loading = true;
  bool _canOverride = false;
  /// Tombol edit produk hanya untuk owner/asisten (bukan kasir). Item 20.
  bool _canEditProduct = false;
  List<_UnitOption> _options = [];
  int _selectedIdx = 0;

  List<_VariantOption> _variants = [];
  final Map<String, double> _variantQty = {}; // variant productId → qty

  double _qty = 1;
  int _price = 0;
  bool _priceOverridden = false;

  /// True bila satuan terpilih sudah ada di keranjang saat modal dibuka →
  /// tampilkan tombol "Hapus dari keranjang".
  bool _existsInCart = false;

  final _priceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final priceService = PriceService(db);

    bool canOverride = device.deviceRole != 'kasir';
    final canEditProduct = device.deviceRole != 'kasir';
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
      );
      final stock = await db.currentStock(u.id);
      final tiers = await db.getPriceTiers(u.id);
      final altPriceList = await db.getAltPrices(u.id);
      final barcodes = await db.getProductBarcodes(u.id);
      opts.add(_UnitOption(
        unit: u,
        unitName: unitType?.name ?? 'Satuan',
        basePrice: resolved.price,
        costPrice: resolved.costPrice,
        stock: stock,
        tiers: tiers,
        altPrices: altPriceList,
        barcode: barcodes
            .where((b) => b.isPrimary)
            .map((b) => b.barcode)
            .firstOrNull,
      ));
    }

    // Varian (produk anak) — tiap varian punya satuan dasar sendiri.
    final variantProducts = await db.getVariants(widget.product.id);
    final variants = <_VariantOption>[];
    for (final vp in variantProducts) {
      final vUnits = await db.getProductUnits(vp.id);
      if (vUnits.isEmpty) continue;
      final base =
          vUnits.firstWhere((u) => u.isBaseUnit, orElse: () => vUnits.first);
      final vType = await (db.select(db.unitTypes)
            ..where((t) => t.id.equals(base.unitTypeId ?? 1)))
          .getSingleOrNull();
      final vResolved = await priceService.resolvePrice(
        productUnitId: base.id,
        qty: 1,
      );
      final vBarcodes = await db.getProductBarcodes(base.id);
      variants.add(_VariantOption(
        product: vp,
        unitId: base.id,
        unitName: vType?.name ?? 'Satuan',
        price: vResolved.price,
        costPrice: vResolved.costPrice,
        barcode: vBarcodes
            .where((b) => b.isPrimary)
            .map((b) => b.barcode)
            .firstOrNull,
      ));
    }

    if (!mounted) return;

    // Jika item ini sudah ada di keranjang, prefill qty & harga-nya.
    final cart = ref.read(cartProvider(widget.cartId));
    // Prefill qty varian yang sudah ada di keranjang.
    for (final v in variants) {
      final ex = cart.where((c) => c.productUnitId == v.unitId).firstOrNull;
      if (ex != null) _variantQty[v.product.id] = ex.qty;
    }
    var selIdx = 0;
    double qty = 1;
    int price = opts.isNotEmpty ? opts.first.basePrice : 0;
    bool overridden = false;
    bool exists = false;
    String note = '';
    final notifier = ref.read(cartProvider(widget.cartId).notifier);
    for (var i = 0; i < opts.length; i++) {
      final existing =
          cart.where((c) => c.productUnitId == opts[i].unit.id).firstOrNull;
      if (existing != null) {
        selIdx = i;
        // Prefill dengan effectiveQty agar konsisten dengan tampilan keranjang.
        qty = notifier.effectiveQtyFor(existing);
        price = existing.price;
        overridden = existing.priceOverridden;
        note = existing.itemNote ?? '';
        exists = true;
        break;
      }
    }
    if (opts.isNotEmpty && !overridden) price = opts[selIdx].basePrice;

    setState(() {
      _options = opts;
      _variants = variants;
      _canOverride = canOverride;
      _canEditProduct = canEditProduct;
      _selectedIdx = selIdx;
      _qty = qty;
      _price = price;
      _priceOverridden = overridden;
      _existsInCart = exists;
      _loading = false;
      _priceCtrl.text = ThousandsSeparatorFormatter.format(price);
      _qtyCtrl.text = _fmtQty(qty);
      _noteCtrl.text = note;
    });
  }

  void _setVariantQty(String variantId, double q) {
    setState(() => _variantQty[variantId] = q.clamp(0, 9999));
  }

  int get _variantTotal {
    var total = 0;
    for (final v in _variants) {
      total += (v.price * (_variantQty[v.product.id] ?? 0)).round();
    }
    return total;
  }

  double get _totalVariantQty =>
      _variants.fold(0.0, (s, v) => s + (_variantQty[v.product.id] ?? 0));

  bool get _canSubmit => _qty > 0 || _totalVariantQty > 0;

  String _fmtQty(double q) => q % 1 == 0 ? q.toInt().toString() : q.toString();

  _UnitOption? get _sel => _options.isEmpty ? null : _options[_selectedIdx];

  void _selectUnit(int idx) {
    // Bila satuan yang dipilih sudah ada di keranjang, ikuti catatan & status
    // override-nya agar edit konsisten per-satuan.
    final cart = ref.read(cartProvider(widget.cartId));
    final existing =
        cart.where((c) => c.productUnitId == _options[idx].unit.id).firstOrNull;
    setState(() {
      _selectedIdx = idx;
      _existsInCart = existing != null;
      _noteCtrl.text = existing?.itemNote ?? '';
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
    final notifier = ref.read(cartProvider(widget.cartId).notifier);

    // storedQty = effectiveQty + variantTotal agar offset math benar.
    // Kalau _qty == 0 tapi ada varian, simpan parent sebagai placeholder
    // (effectiveQty = 0 → tampil "via varian").
    final variantQtySum = _totalVariantQty;
    final storedQty = _qty + variantQtySum;

    final note = _noteCtrl.text.trim();
    if (storedQty > 0) {
      notifier.setItem(CartItem(
        productId: widget.product.id,
        productUnitId: sel.unit.id,
        productName: widget.product.name,
        unitName: sel.unitName,
        qty: storedQty,
        price: _price,
        originalPrice: sel.basePrice,
        costPrice: sel.costPrice,
        priceOverridden: _priceOverridden,
        itemNote: note.isEmpty ? null : note,
        barcode: sel.barcode,
      ));
    }

    // Varian terpilih → item add-on bersarang di bawah induk.
    for (final v in _variants) {
      final vq = _variantQty[v.product.id] ?? 0;
      notifier.setItem(CartItem(
        productId: v.product.id,
        productUnitId: v.unitId,
        productName: v.product.name,
        unitName: v.unitName,
        qty: vq,
        price: v.price,
        originalPrice: v.price,
        costPrice: v.costPrice,
        barcode: v.barcode,
        parentProductId: widget.product.id,
        parentProductUnitId: sel.unit.id, // Item 16: menempel ke satuan aktif
        isVariant: true,
      ));
    }
    Navigator.of(context).pop();
  }

  /// Buka form edit produk (owner/asisten). Tutup sheet dulu lalu push route
  /// `/produk/:id` via GoRouter — ProdukFormScreen menutup diri dengan
  /// `context.pop()` GoRouter, jadi tidak boleh di-push lewat Navigator biasa,
  /// dan tidak boleh menumpuk di atas modal sheet (barrier sheet menutupinya).
  /// Katalog kasir auto-refresh via stream `watchProducts`, jadi perubahan
  /// harga/stok langsung tercermin saat produk di-tap lagi.
  void _editProduct() {
    final router = GoRouter.of(context);
    final id = widget.product.id;
    Navigator.of(context).pop(); // tutup sheet
    router.push('/produk/$id');
  }

  /// Hapus item (satuan terpilih) dari keranjang. Hanya muncul saat item
  /// memang sudah ada di keranjang (modal dibuka dari keranjang).
  void _delete() {
    final sel = _sel;
    if (sel == null) return;
    final notifier = ref.read(cartProvider(widget.cartId).notifier);
    // removeItem sudah cascade-hapus varian yang menempel ke baris satuan ini
    // (Item 16), jadi cukup panggil sekali.
    notifier.removeItem(sel.unit.id);
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(widget.product.name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ),
                            if (_canEditProduct)
                              IconButton(
                                icon: Icon(Icons.edit_outlined,
                                    color: scheme.onSurfaceVariant),
                                tooltip: 'Edit produk',
                                visualDensity: VisualDensity.compact,
                                onPressed: _editProduct,
                              ),
                            if (_existsInCart)
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: scheme.error),
                                tooltip: 'Hapus dari keranjang',
                                visualDensity: VisualDensity.compact,
                                onPressed: _delete,
                              ),
                          ],
                        ),
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

                  // ── Harga lain (satuan + tier + harga alternatif) ─────
                  if (_options.length > 1 ||
                      (_sel?.tiers.length ?? 0) > 1 ||
                      (_sel?.altPrices.isNotEmpty ?? false)) ...[
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
                          // Harga alternatif berlabel (mis. "Harga Toko A").
                          if (_sel != null)
                            for (final a in _sel!.altPrices)
                              _PriceChip(
                                label: a.label,
                                price: a.price,
                                selected: _priceOverridden && _price == a.price,
                                onTap: () => _applyTierPrice(a.price),
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
                                      onTap: () => _qtyCtrl.selection =
                                          TextSelection(
                                              baseOffset: 0,
                                              extentOffset:
                                                  _qtyCtrl.text.length),
                                      onChanged: (v) {
                                        final q = double.tryParse(v.trim());
                                        setState(() {
                                          _qty = (q != null && q >= 0)
                                              ? q.clamp(0, 9999)
                                              : 0;
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
                                onTap: _canOverride
                                    ? () => _priceCtrl.selection =
                                        TextSelection(
                                            baseOffset: 0,
                                            extentOffset:
                                                _priceCtrl.text.length)
                                    : null,
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

                  // ── Catatan item ──────────────────────────────────────
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.note_alt_outlined,
                                size: 14, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text('Catatan item',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _noteCtrl,
                          maxLines: 2,
                          minLines: 1,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Contoh: tanpa saus, bungkus terpisah',
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 8, horizontal: 10),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Varian (add-on bersarang) ─────────────────────────
                  if (_variants.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.account_tree_outlined,
                              size: 15, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text('Varian',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 196),
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final v in _variants)
                            _VariantRow(
                              name: v.product.name,
                              unitName: v.unitName,
                              price: v.price,
                              qty: _variantQty[v.product.id] ?? 0,
                              onMinus: () => _setVariantQty(v.product.id,
                                  (_variantQty[v.product.id] ?? 0) - 1),
                              onPlus: () => _setVariantQty(v.product.id,
                                  (_variantQty[v.product.id] ?? 0) + 1),
                            ),
                        ],
                      ),
                    ),
                  ],
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
                            Text(_variantTotal > 0 ? 'Total' : 'Subtotal',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant)),
                            Text(
                              formatRupiah(
                                  (_price * _qty).round() + _variantTotal),
                              style: AppTheme.numStyle(context,
                                  size: 18, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed: _canSubmit ? _submit : null,
                            child: Text(_canSubmit
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

class _VariantRow extends StatelessWidget {
  const _VariantRow({
    required this.name,
    required this.unitName,
    required this.price,
    required this.qty,
    required this.onMinus,
    required this.onPlus,
  });

  final String name;
  final String unitName;
  final int price;
  final double qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = qty > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? scheme.secondaryContainer.withOpacity(0.5)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? scheme.secondary : scheme.outlineVariant,
          width: active ? 1.2 : 0.75,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text('$unitName · ${formatRupiah(price)}',
                    style: TextStyle(
                        fontSize: 10.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 22),
            visualDensity: VisualDensity.compact,
            onPressed: qty <= 0 ? null : onMinus,
          ),
          SizedBox(
            width: 24,
            child: Text(
              qty % 1 == 0 ? qty.toInt().toString() : qty.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 22),
            visualDensity: VisualDensity.compact,
            onPressed: onPlus,
          ),
        ],
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
