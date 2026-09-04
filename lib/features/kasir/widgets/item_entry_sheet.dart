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
    required this.stock,
    required this.isNonStock,
    this.altPrices = const [],
    this.barcode,
  });

  final Product product;
  final String unitId;
  final String unitName;
  final int price;
  final int costPrice;
  // Susulan (permintaan user) — stok varian SUDAH DILACAK di DB (tiap
  // varian punya stock_ledger sendiri via unitId-nya), tapi sebelumnya
  // TIDAK PERNAH ditampilkan di mana pun (kasir bisa jual varian kosong
  // tanpa peringatan sama sekali). `isNonStock` = varian ini tidak
  // melacak stok sama sekali ("Lacak stok varian" dimatikan di Edit
  // Produk) — beda dari `stock <= 0` (dilacak, TAPI kosong).
  final double stock;
  final bool isNonStock;
  // Susulan (permintaan user) — Harga Lain varian tersimpan sejak putaran
  // sebelumnya tapi belum bisa DIPAKAI sama sekali saat jual (harga
  // varian di keranjang selalu harga dasar mentah). Dipilih lewat menu
  // kecil di `_VariantRow` (bukan chip horizontal spt produk utama — baris
  // varian sengaja ringkas, chip penuh per varian akan makan tempat
  // vertikal kalau varian banyak).
  final List<AltPrice> altPrices;
  final String? barcode;
}

class _ItemEntrySheetState extends ConsumerState<ItemEntrySheet> {
  bool _loading = true;
  bool _canOverride = false;

  /// Tombol edit produk hanya untuk owner/asisten (bukan kasir). Item 20.
  bool _canEditProduct = false;

  /// Item 25a — tanda cepat "stok habis" manual, terpisah dari sistem stok
  /// resmi. Semua role bisa toggle (akses cepat, bukan izin ter-audit).
  late bool _markedOutOfStock = widget.product.markedOutOfStock;
  List<_UnitOption> _options = [];
  int _selectedIdx = 0;

  List<_VariantOption> _variants = [];
  final Map<String, double> _variantQty = {}; // variant productId → qty
  // Susulan (permintaan user) — "Harga Lain" varian tersimpan tapi sebelumnya
  // tidak bisa dipakai sama sekali saat jual (selalu harga dasar mentah).
  // variant productId → harga terpilih (null/tidak ada entri = harga dasar).
  final Map<String, int> _variantPriceOverride = {};
  // Susulan (permintaan user): samakan format dgn stepper Titip/Ketinggalan
  // — bisa ketik langsung (utk qty desimal, mis. varian produk timbang),
  // bukan cuma stepper +/-1 polos spt sebelumnya.
  final Map<String, TextEditingController> _variantQtyCtrls = {};
  // Susulan (permintaan user): field harga varian bisa diketik manual
  // langsung (persis field harga produk utama), bukan cuma lewat popup —
  // dibuat sekali per varian spy caret/selection tidak reset tiap rebuild.
  final Map<String, TextEditingController> _variantPriceCtrls = {};

  double _qty = 1;
  int _price = 0;
  bool _priceOverridden = false;

  /// Item 52 redesain pre-order — kartu "Pre-order?" HANYA muncul ketika
  /// [_markedOutOfStock] true. Default Tidak (opt-in eksplisit, konsisten
  /// dgn pola "aman/tidak mengasumsikan" fitur Laci Meja lain).
  bool _isPreorder = false;

  /// "DP?" — Ya berarti harga penuh terisi & dibayar lunas sekarang; Tidak
  /// (default) berarti harga 0, dicatat dulu, bayar nanti saat barang
  /// datang.
  bool _dpPaid = false;
  double _depositQty = 0;
  final _depositQtyCtrl = TextEditingController();

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
    _depositQtyCtrl.dispose();
    for (final c in _variantQtyCtrls.values) {
      c.dispose();
    }
    for (final c in _variantPriceCtrls.values) {
      c.dispose();
    }
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
      // Satuan JUAL varian (bisa satuan non-dasar yang berisi N satuan
      // dasar, mis. Renteng isi 10) — harga/barcode/Harga Lain/stok yang
      // dilihat kasir semuanya menempel di satuan ini.
      final base = AppDatabase.variantSaleUnit(vUnits)!;
      final vType = await (db.select(db.unitTypes)
            ..where((t) => t.id.equals(base.unitTypeId ?? 1)))
          .getSingleOrNull();
      final vResolved = await priceService.resolvePrice(
        productUnitId: base.id,
        qty: 1,
      );
      final vBarcodes = await db.getProductBarcodes(base.id);
      final vStock = base.isNonStock ? 0.0 : await db.currentStock(base.id);
      final vAltPrices = await db.getAltPrices(base.id);
      variants.add(_VariantOption(
        product: vp,
        unitId: base.id,
        unitName: vType?.name ?? 'Satuan',
        price: vResolved.price,
        costPrice: vResolved.costPrice,
        stock: vStock,
        isNonStock: base.isNonStock,
        altPrices: vAltPrices,
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
    // Bug ditemukan saat review logika laci-meja (permintaan user): sebelum
    // ini, toggle "Pre-order?"/"DP?" SELALU mulai dari default (Tidak) tiap
    // sheet dibuka, walau item yang SAMA sudah tersimpan di cart sbg
    // pre-order — toggle-nya jadi menampilkan state yg SALAH (membingungkan
    // kasir), dan kalau kasir tetap tap Simpan tanpa sadar (mis. cuma mau
    // ubah qty), status pre-order aslinya BENERAN hilang krn `_submit()`
    // menulis ulang cart line dgn `_isPreorder` yg sudah salah. Sekarang
    // di-prefill sama seperti qty/harga/catatan di atas.
    var isPreorder = false;
    var dpPaid = false;
    double depositQty = 0;
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
        isPreorder = existing.isPreorder;
        dpPaid = existing.preorderPaid;
        depositQty = existing.depositQty ?? 0;
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
      _isPreorder = isPreorder;
      _dpPaid = dpPaid;
      _depositQty = depositQty;
      _depositQtyCtrl.text = _fmtQty(depositQty);
    });
  }

  void _setVariantQty(String variantId, double q) {
    final clamped = q.clamp(0, 9999);
    setState(() {
      _variantQty[variantId] = clamped.toDouble();
      _variantQtyCtrls[variantId]?.text = _fmtQty(clamped.toDouble());
    });
  }

  int _variantPrice(_VariantOption v) =>
      _variantPriceOverride[v.product.id] ?? v.price;

  void _setVariantPrice(String variantId, int price) {
    setState(() {
      _variantPriceOverride[variantId] = price;
      _variantPriceCtrls[variantId]?.text =
          ThousandsSeparatorFormatter.format(price);
    });
  }

  /// Diketik manual di field harga varian (bukan lewat chip) — cuma
  /// override sekali pakai utk transaksi ini (persis override harga produk
  /// utama), TIDAK ditulis balik ke data varian tersimpan.
  void _onVariantPriceTyped(String variantId, String text) {
    final parsed = ThousandsSeparatorFormatter.parseValue(text);
    setState(() => _variantPriceOverride[variantId] = parsed);
  }

  int get _variantTotal {
    var total = 0;
    for (final v in _variants) {
      total += (_variantPrice(v) * (_variantQty[v.product.id] ?? 0)).round();
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

  /// Daftar pilihan harga untuk satuan terpilih: harga dasar + tier grosir
  /// (minQty>1) + Harga Lain. Item 19 — dipakai dropdown di sebelah field
  /// Harga (menggantikan chip yang menumpuk).
  List<({String label, int price})> _priceOptions() {
    final sel = _sel;
    if (sel == null) return const [];
    return [
      (label: 'Harga dasar', price: sel.basePrice),
      for (final t in sel.tiers.reversed)
        if (t.minQty > 1)
          (
            label: 'Grosir ≥${_fmtQty(t.minQty.toDouble())} ${sel.unitName}',
            price: t.price
          ),
      for (final a in sel.altPrices) (label: a.label, price: a.price),
    ];
  }

  // Redesain 25 Juli (usulan user, dari screenshot): dulu satu ikon
  // "Harga lain (N)" yang buka popup menu — sekarang setiap opsi harga
  // (harga dasar + tier grosir + Harga Lain) langsung tampil sbg chip
  // sendiri-sendiri, persis pola "Pilih satuan" di atasnya (`_PriceChip`
  // yang sama, dipakai ulang). Tidak perlu buka apa pun dulu utk melihat
  // opsinya — semua harga & labelnya langsung kelihatan sekaligus.

  void _setQty(double q) {
    setState(() {
      _qty = q.clamp(0, 9999);
      _qtyCtrl.text = _fmtQty(_qty);
    });
  }

  /// Pembulatan hasil konversi Rp→qty ke 3 desimal (cukup presisi utk
  /// gram-an tanpa noise floating point, mis. 5000/17000 → 0.294, bukan
  /// 0.29411764705882354).
  double _roundQty3(double q) => (q * 1000).round() / 1000;

  String _fmtConvertedQty(double q) {
    final r = _roundQty3(q);
    return r % 1 == 0 ? r.toInt().toString() : r.toString();
  }

  /// Susulan (permintaan user) — konverter "beli dengan nominal Rp": kasir
  /// ketik nominal uang pelanggan (mis. Rp 5.000), qty otomatis dihitung
  /// dari harga satuan aktif (`_price`, sudah termasuk tier grosir/Harga
  /// Lain terpilih) lalu diterapkan ke field Jumlah. Menghindari
  /// meraba-raba qty manual utk produk timbang/satuan desimal.
  Future<void> _showRupiahConverter() async {
    final sel = _sel;
    if (sel == null || _price <= 0) return;
    final amountCtrl = TextEditingController();
    double computedQty = 0;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: const Text('Beli dengan nominal'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Harga: ${formatRupiah(_price)} / ${sel.unitName}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsSeparatorFormatter()],
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixText: 'Rp ',
                    labelText: 'Uang pelanggan',
                  ),
                  onChanged: (v) {
                    final amount = ThousandsSeparatorFormatter.parseValue(v);
                    setDialogState(() {
                      computedQty = amount > 0 ? amount / _price : 0;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  '≈ ${_fmtConvertedQty(computedQty)} ${sel.unitName}',
                  style:
                      AppTheme.numStyle(ctx, size: 18, weight: FontWeight.w700),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: computedQty > 0
                    ? () {
                        _setQty(_roundQty3(computedQty));
                        Navigator.of(ctx).pop();
                      }
                    : null,
                child: const Text('Pakai'),
              ),
            ],
          );
        },
      ),
    );
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
        price: _effectivePrice,
        originalPrice: sel.basePrice,
        costPrice: sel.costPrice,
        priceOverridden: _priceOverridden,
        itemNote: note.isEmpty ? null : note,
        barcode: sel.barcode,
        isPreorder: _isPreorder,
        preorderPaid: _dpPaid,
        depositQty:
            (_isPreorder && sel.unit.requiresDeposit) ? _depositQty : null,
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
        price: _variantPrice(v),
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
  ///
  /// Pop dengan `true` (bukan default/null) — penanda ke `_openCartSheet` di
  /// kasir_screen.dart bahwa sheet ini ditutup karena PINDAH LAYAR, bukan
  /// selesai edit biasa, supaya cart sheet TIDAK dibuka ulang otomatis di
  /// belakang layar baru (kalau dibuka ulang, `_onHardwareKey` salah kira
  /// cart sheet masih aktif dan menelan input keyboard di layar baru itu).
  void _editProduct() {
    final router = GoRouter.of(context);
    final id = widget.product.id;
    Navigator.of(context).pop(true); // tutup sheet, tandai "pindah layar"
    router.push('/produk/$id');
  }

  /// Item 25a — tandai/lepas "stok habis" cepat, tanpa buka form Produk.
  Future<void> _toggleOutOfStock() async {
    final next = !_markedOutOfStock;
    setState(() {
      _markedOutOfStock = next;
      // Kartu "Pre-order?" cuma muncul selama produk masih ditandai habis —
      // begitu ditandai tersedia lagi, reset supaya tidak ada state
      // pre-order basi yg diam-diam ikut ke keranjang.
      if (!next) {
        _isPreorder = false;
        _dpPaid = false;
      }
    });
    await ref
        .read(databaseProvider)
        .setMarkedOutOfStock(widget.product.id, next);
  }

  void _setPreorder(bool value) {
    setState(() {
      _isPreorder = value;
      _dpPaid = false;
      _priceCtrl.text = ThousandsSeparatorFormatter.format(_effectivePrice);
      if (value && _sel != null && _sel!.unit.requiresDeposit) {
        _depositQty = _qty;
        _depositQtyCtrl.text = _fmtQty(_depositQty);
      }
    });
  }

  void _setDpPaid(bool value) {
    setState(() {
      _dpPaid = value;
      _priceCtrl.text = ThousandsSeparatorFormatter.format(_effectivePrice);
    });
  }

  /// Harga yang SUNGGUHAN disimpan ke keranjang — pre-order TANPA DP
  /// (belum bayar) selalu 0, terlepas dari harga yang ter-resolve normal.
  int get _effectivePrice => (_isPreorder && !_dpPaid) ? 0 : _price;

  /// Field Harga dikunci (tak bisa diketik) selama pre-order TANPA DP —
  /// harganya WAJIB 0, bukan sesuatu yang bisa disunting manual.
  bool get _priceLocked => _isPreorder && !_dpPaid;

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
                            IconButton(
                              icon: Icon(
                                _markedOutOfStock
                                    ? Icons.remove_shopping_cart
                                    : Icons.remove_shopping_cart_outlined,
                                color: _markedOutOfStock
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                              ),
                              tooltip: _markedOutOfStock
                                  ? 'Tandai stok tersedia lagi'
                                  : 'Tandai stok habis',
                              visualDensity: VisualDensity.compact,
                              onPressed: _toggleOutOfStock,
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

                  // ── Pilih satuan (chip) — hanya bila >1 satuan. Item 19:
                  // tier grosir & Harga Lain TIDAK lagi dicampur di sini;
                  // pindah ke dropdown di sebelah field Harga (skalabel &
                  // menempel ke satuan terpilih).
                  if (_options.length > 1) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Pilih satuan',
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
                              // BUG dilaporkan user: dulu `&& !_priceOverridden`
                              // — begitu pilih chip "Harga Lain" (yg men-set
                              // `_priceOverridden=true`), highlight satuan
                              // yang sedang aktif ikut MATI, padahal
                              // satuannya sendiri tidak berubah sama sekali.
                              // Dua hal berbeda (satuan aktif vs harga yg
                              // dipakai) dipaksa jadi satu kondisi. Satuan
                              // aktif HANYA ditentukan `_selectedIdx` —
                              // harga yg dipakai punya highlight sendiri di
                              // baris "Pilih harga" di bawah.
                              selected: i == _selectedIdx,
                              onTap: () => _selectUnit(i),
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
                              Row(
                                children: [
                                  Text('Jumlah',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant)),
                                  // Susulan (permintaan user) — konverter kecil
                                  // "beli dengan nominal Rp", supaya pelanggan
                                  // yg mau beli produk timbang/satuan desimal
                                  // (mis. gula per kg) senilai uang tertentu
                                  // (mis. Rp 5.000) tidak perlu meraba-raba
                                  // qty-nya secara manual. Cuma tampil kalau
                                  // harga satuan aktif diketahui (>0) & tidak
                                  // terkunci (pre-order tanpa DP = harga 0).
                                  if (_price > 0 && !_priceLocked) ...[
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: _showRupiahConverter,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: Icon(Icons.calculate_outlined,
                                            size: 15, color: scheme.primary),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline,
                                        size: 26),
                                    onPressed: () => _setQty(_qty - 1),
                                  ),
                                  const SizedBox(width: 2),
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
                                  const SizedBox(width: 2),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline,
                                        size: 26),
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
                                readOnly: !_canOverride || _priceLocked,
                                keyboardType: TextInputType.number,
                                inputFormatters: const [
                                  ThousandsSeparatorFormatter()
                                ],
                                decoration: InputDecoration(
                                  isDense: true,
                                  prefixText: 'Rp ',
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 10),
                                  suffixIcon: (!_canOverride || _priceLocked)
                                      ? Icon(Icons.lock_outline,
                                          size: 14,
                                          color: scheme.onSurfaceVariant)
                                      : null,
                                ),
                                onTap: (_canOverride && !_priceLocked)
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

                  // ── Kartu "Pre-order?" — Item 52 redesain, HANYA muncul
                  // selama produk ditandai habis (menggantikan total jalur
                  // lama "+ Antri"/"Catat Pre-order" yg terpisah dari
                  // keranjang; sekarang nyambung langsung supaya administrasi
                  // & tracking-nya jadi satu jalur dgn nota).
                  if (_markedOutOfStock && _sel != null) ...[
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.laciBg(
                              Theme.of(context).brightness == Brightness.dark),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('Pre-order?',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.laciFg(
                                              Theme.of(context).brightness ==
                                                  Brightness.dark))),
                                ),
                                _YesNoToggle(
                                  value: _isPreorder,
                                  onChanged: _setPreorder,
                                ),
                              ],
                            ),
                            if (_isPreorder) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('DP? (bayar lunas sekarang)',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.laciFg(
                                                Theme.of(context).brightness ==
                                                    Brightness.dark))),
                                  ),
                                  _YesNoToggle(
                                    value: _dpPaid,
                                    onChanged: _setDpPaid,
                                  ),
                                ],
                              ),
                              if (_sel!.unit.requiresDeposit) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text('Jumlah jaminan dititip',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.laciFg(
                                                  Theme.of(context)
                                                          .brightness ==
                                                      Brightness.dark))),
                                    ),
                                    SizedBox(
                                      width: 90,
                                      child: TextField(
                                        controller: _depositQtyCtrl,
                                        textAlign: TextAlign.center,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding:
                                              EdgeInsets.symmetric(vertical: 8),
                                        ),
                                        onChanged: (v) {
                                          final q = double.tryParse(v.trim());
                                          if (q != null) {
                                            setState(() =>
                                                _depositQty = q.clamp(0, 9999));
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],

                  // ── Pilih harga (chip) — tier grosir & Harga Lain milik
                  // satuan terpilih, SATU CHIP PER OPSI (termasuk "Harga
                  // dasar" utk kembali cepat), bukan lagi satu ikon yang
                  // buka popup menu. Pola & widget SAMA dgn "Pilih satuan"
                  // di atas (`_PriceChip`) — usulan user: opsi harga
                  // sebanyak apa pun langsung kelihatan semua sekaligus.
                  if (_priceOptions().length > 1 && !_priceLocked) ...[
                    const SizedBox(height: 14),
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
                          for (final o in _priceOptions())
                            _PriceChip(
                              label: o.label,
                              price: o.price,
                              selected: _price == o.price,
                              onTap: () => _applyTierPrice(o.price),
                            ),
                        ],
                      ),
                    ),
                  ],

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
                              price: _variantPrice(v),
                              basePrice: v.price,
                              altPrices: v.altPrices,
                              onSelectPrice: (p) =>
                                  _setVariantPrice(v.product.id, p),
                              priceController: _variantPriceCtrls.putIfAbsent(
                                  v.product.id,
                                  () => TextEditingController(
                                      text: ThousandsSeparatorFormatter.format(
                                          _variantPrice(v)))),
                              onPriceTyped: (text) =>
                                  _onVariantPriceTyped(v.product.id, text),
                              stock: v.stock,
                              isNonStock: v.isNonStock,
                              qty: _variantQty[v.product.id] ?? 0,
                              qtyController: _variantQtyCtrls.putIfAbsent(
                                  v.product.id,
                                  () => TextEditingController(
                                      text: _fmtQty(
                                          _variantQty[v.product.id] ?? 0))),
                              onMinus: () => _setVariantQty(v.product.id,
                                  (_variantQty[v.product.id] ?? 0) - 1),
                              onPlus: () => _setVariantQty(v.product.id,
                                  (_variantQty[v.product.id] ?? 0) + 1),
                              onChanged: (v2) {
                                final parsed = double.tryParse(v2);
                                if (parsed != null && parsed >= 0) {
                                  setState(
                                      () => _variantQty[v.product.id] = parsed);
                                }
                              },
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
                              formatRupiah((_effectivePrice * _qty).round() +
                                  _variantTotal),
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
    required this.basePrice,
    required this.altPrices,
    required this.onSelectPrice,
    required this.priceController,
    required this.onPriceTyped,
    required this.stock,
    required this.isNonStock,
    required this.qty,
    required this.qtyController,
    required this.onMinus,
    required this.onPlus,
    required this.onChanged,
  });

  final String name;
  final String unitName;
  final int price;
  // Susulan (permintaan user) — field harga & chip Harga Lain HANYA muncul
  // saat varian ini sedang qty>0 (sedang dibeli), supaya varian yg banyak
  // (mis. 8 rasa) tidak bikin layar penuh sesak/scroll panjang kalau
  // semuanya menampilkan kontrol harga sekaligus — cuma yg benar-benar
  // dibeli yang perlu diatur.
  final int basePrice;
  final List<AltPrice> altPrices;
  final ValueChanged<int> onSelectPrice;
  // Field harga bisa diketik manual langsung (persis field harga produk
  // utama) — override SEKALI PAKAI utk transaksi ini, tidak mengubah data
  // varian tersimpan (konsisten dgn override harga produk utama).
  final TextEditingController priceController;
  final ValueChanged<String> onPriceTyped;
  // Susulan (permintaan user) — stok varian sudah dilacak di DB (stok
  // terpisah per varian via unitId-nya), tapi sebelumnya tidak pernah
  // ditampilkan sama sekali di sini — kasir bisa jual varian kosong tanpa
  // peringatan. Ditampilkan APA ADANYA (bukan blokir tambah ke keranjang,
  // konsisten dgn produk utama yg jg tidak hard-block saat stok habis).
  final double stock;
  final bool isNonStock;
  final double qty;
  final TextEditingController qtyController;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = qty > 0;
    final isOutOfStock = !isNonStock && stock <= 0;
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
                Row(
                  children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                    if (isOutOfStock) ...[
                      const SizedBox(width: 6),
                      Text('Habis',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.error)),
                    ],
                  ],
                ),
                Text(
                  isNonStock
                      ? '$unitName · Non-stok'
                      : '$unitName · Stok '
                          '${stock % 1 == 0 ? stock.toInt() : stock}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
                // Susulan (permintaan user) — field harga bisa diketik
                // manual + chip Harga Lain langsung (bukan popup lagi),
                // persis pengalaman produk utama, TAPI cuma muncul kalau
                // varian ini qty>0 (sedang dibeli) — supaya varian yg
                // banyak tidak bikin baris jadi panjang semua sekaligus.
                if (active) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 100,
                    height: 32,
                    child: TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [ThousandsSeparatorFormatter()],
                      style: AppTheme.numStyle(context,
                          size: 12, weight: FontWeight.w700),
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixText: 'Rp ',
                        prefixStyle: TextStyle(fontSize: 11),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: onPriceTyped,
                    ),
                  ),
                  if (altPrices.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _MiniPriceChip(
                          label: 'Harga dasar',
                          price: basePrice,
                          selected: price == basePrice,
                          onTap: () => onSelectPrice(basePrice),
                        ),
                        for (final a in altPrices)
                          _MiniPriceChip(
                            label: a.label,
                            price: a.price,
                            selected: price == a.price,
                            onTap: () => onSelectPrice(a.price),
                          ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 24),
            onPressed: qty <= 0 ? null : onMinus,
          ),
          const SizedBox(width: 2),
          SizedBox(
            width: 44,
            child: TextField(
              controller: qtyController,
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4)),
              // Ketik bebas (utk qty desimal, mis. varian produk timbang) —
              // stepper +/-1 SENDIRIAN tidak bisa mencapai nilai desimal
              // sembarang. Pola identik dialog Titip/Ketinggalan.
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 24),
            onPressed: onPlus,
          ),
        ],
      ),
    );
  }
}

/// Versi mini `_PriceChip` khusus baris varian — dipakai `Wrap` (bukan
/// `ListView` horizontal) krn ruang per baris varian sengaja sempit; padding
/// lebih kecil supaya beberapa chip muat sebaris tanpa scroll tambahan.
class _MiniPriceChip extends StatelessWidget {
  const _MiniPriceChip({
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withOpacity(0.12)
              : scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.2 : 0.75,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? scheme.primary : scheme.onSurface)),
            Text(
              formatRupiah(price),
              style: AppTheme.numStyle(context,
                  size: 11,
                  weight: FontWeight.w700,
                  color: selected ? scheme.primary : scheme.onSurface),
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

/// Toggle "dua tombol centang Ya/Tidak" — dipakai kartu "Pre-order?"/"DP?"
/// di [ItemEntrySheet]. Warna aksen Laci Meja (dusty rose) supaya konsisten
/// dgn kartu pembungkusnya.
class _YesNoToggle extends StatelessWidget {
  const _YesNoToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = AppTheme.laciFg(isDark);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _YesNoButton(
            label: 'Ya',
            selected: value,
            color: fg,
            onTap: () => onChanged(true)),
        const SizedBox(width: 6),
        _YesNoButton(
            label: 'Tidak',
            selected: !value,
            color: fg,
            onTap: () => onChanged(false)),
      ],
    );
  }
}

class _YesNoButton extends StatelessWidget {
  const _YesNoButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withOpacity(0.18) : Colors.transparent,
      shape: StadiumBorder(
          side: BorderSide(color: selected ? color : color.withOpacity(0.4))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 14, color: color),
                const SizedBox(width: 3),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
