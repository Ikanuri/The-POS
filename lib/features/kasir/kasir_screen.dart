import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/app_database.dart';
import '../../core/models/cart_item.dart';
import '../../core/providers/device_provider.dart';
import '../../core/providers/product_providers.dart';
import '../../core/services/price_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/inline_banner.dart';
import 'cart_provider.dart';
import 'widgets/cart_sheet.dart';
import 'widgets/held_orders_sheet.dart';
import 'widgets/item_entry_sheet.dart';
import 'widgets/tx_history_sheet.dart';

final _kasirSearchProvider = StateProvider<String>((ref) => '');

/// State toast melayang saat scan mode berulang.
class _ScanToast {
  _ScanToast({
    required this.productUnitId,
    required this.productName,
    required this.unitName,
    required this.qty,
    required this.price,
  });

  final String productUnitId;
  final String productName;
  final String unitName;
  int qty;
  final int price;
  Timer? timer;
}

/// Kartu toast melayang di atas kamera scanner. Tombol ± identik gaya keranjang.
class _ScanToastCard extends StatelessWidget {
  const _ScanToastCard({
    required this.toast,
    required this.onInc,
    required this.onDec,
  });

  final _ScanToast toast;
  final VoidCallback onInc;
  final VoidCallback onDec;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(toast.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${toast.unitName} · ${formatRupiah(toast.price)}',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              visualDensity: VisualDensity.compact,
              onPressed: onDec,
            ),
            SizedBox(
              width: 28,
              child: Text('${toast.qty}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              visualDensity: VisualDensity.compact,
              onPressed: onInc,
            ),
          ],
        ),
      ),
    );
  }
}

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

/// Detail katalog per produk: harga satuan dasar + jumlah satuan.
class CatalogDetail {
  const CatalogDetail({
    required this.baseUnitId,
    required this.baseUnitName,
    required this.basePrice,
    required this.costPrice,
    required this.unitCount,
    this.barcode,
    this.hasVariants = false,
  });

  final String baseUnitId;
  final String baseUnitName;
  final int basePrice;
  final int costPrice;
  final int unitCount;
  final String? barcode;
  final bool hasVariants;
}

final _catalogDetailProvider =
    FutureProvider.family<CatalogDetail, String>((ref, productId) async {
  final db = ref.watch(databaseProvider);
  // Watch product list (name/group changes) AND explicit update counter
  // (price/barcode changes don't touch the products table).
  ref.watch(_kasirProductsProvider(''));
  ref.watch(productUpdateCountProvider);
  final units = await db.getProductUnits(productId);
  if (units.isEmpty) {
    return const CatalogDetail(
      baseUnitId: '',
      baseUnitName: 'Satuan',
      basePrice: 0,
      costPrice: 0,
      unitCount: 0,
    );
  }
  final base =
      units.firstWhere((u) => u.isBaseUnit, orElse: () => units.first);
  final resolved =
      await PriceService(db).resolvePrice(productUnitId: base.id, qty: 1);
  final unitType = await (db.select(db.unitTypes)
        ..where((t) => t.id.equals(base.unitTypeId ?? 1)))
      .getSingleOrNull();
  final barcodes = await db.getProductBarcodes(base.id);
  final variants = await db.getVariants(productId);
  return CatalogDetail(
    baseUnitId: base.id,
    baseUnitName: unitType?.name ?? 'Satuan',
    basePrice: resolved.price,
    costPrice: resolved.costPrice,
    unitCount: units.length,
    barcode:
        barcodes.where((b) => b.isPrimary).map((b) => b.barcode).firstOrNull,
    hasVariants: variants.isNotEmpty,
  );
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

List<Color> _gradFor(String name) =>
    _kAvatarGradients[(name.isEmpty ? 0 : name.codeUnitAt(0)) %
        _kAvatarGradients.length];

class KasirScreen extends ConsumerStatefulWidget {
  const KasirScreen({super.key});

  @override
  ConsumerState<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends ConsumerState<KasirScreen> {
  static const _prefContinuous = 'scanner_continuous';
  static const _prefToastDuration = 'scanner_toast_duration';

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  bool _scannerOpen = false;
  MobileScannerController? _scannerCtrl;

  // ── Scanner barcode eksternal (HID: USB OTG / Bluetooth HID) ──────────────
  // Scanner HID mengirim barcode seperti ketikan keyboard sangat cepat yang
  // diakhiri Enter. Kita kumpulkan karakter di buffer dan proses saat Enter.
  // Tidak ada konflik dengan printer Bluetooth (printer pakai profil SPP).
  final StringBuffer _hwScanBuffer = StringBuffer();
  DateTime _lastKeyTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _kHumanGapMs = 200; // jeda antar-tombol manusia > 200ms
  static const _kMinBarcodeLen = 3;

  // Mode scanner
  bool _continuousScan = false;
  int _toastDurationSeconds = 5;

  // Toast melayang (mode continuous)
  _ScanToast? _activeToast;

  // Debounce deteksi berulang barcode yang sama
  String? _lastScan;
  int _lastScanMs = 0;

  // Banner notifikasi inline (bukan SnackBar overlay)
  String? _bannerMsg;
  InlineBannerType _bannerType = InlineBannerType.error;

  void _showBanner(String msg, [InlineBannerType type = InlineBannerType.error]) {
    setState(() { _bannerMsg = msg; _bannerType = type; });
  }

  @override
  void initState() {
    super.initState();
    _loadScannerPrefs();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  /// Handler global untuk scanner barcode eksternal (HID keyboard mode).
  /// Mengembalikan true (consume) saat karakter/Enter berasal dari scan,
  /// sehingga tidak memicu aksi lain. Dilewati saat: scanner kamera terbuka,
  /// layar kasir bukan rute teratas (mis. di dialog/sheet/halaman bayar),
  /// atau field pencarian sedang fokus (pengguna mengetik manual).
  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_scannerOpen) return false;
    if (_searchFocus.hasFocus) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;

    final now = DateTime.now();
    final gapMs = now.difference(_lastKeyTime).inMilliseconds;
    _lastKeyTime = now;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final code = _hwScanBuffer.toString().trim();
      _hwScanBuffer.clear();
      if (code.length >= _kMinBarcodeLen) {
        _handleBarcode(code);
        return true;
      }
      return false;
    }

    // Jeda antar-karakter terlalu lama → bukan scanner, mulai buffer baru.
    if (gapMs > _kHumanGapMs && _hwScanBuffer.isNotEmpty) {
      _hwScanBuffer.clear();
    }

    final ch = event.character;
    if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 0x20) {
      _hwScanBuffer.write(ch);
      return true;
    }
    return false;
  }

  Future<void> _loadScannerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _continuousScan = prefs.getBool(_prefContinuous) ?? false;
      _toastDurationSeconds = prefs.getInt(_prefToastDuration) ?? 5;
    });
  }

  Future<void> _setContinuous(bool v) async {
    setState(() => _continuousScan = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefContinuous, v);
  }

  Future<void> _setToastDuration(int s) async {
    setState(() => _toastDurationSeconds = s);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefToastDuration, s);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _activeToast?.timer?.cancel();
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
    _activeToast?.timer?.cancel();
    _scannerCtrl?.dispose();
    setState(() {
      _scannerOpen = false;
      _scannerCtrl = null;
      _activeToast = null;
    });
  }

  /// Resolusi barcode → data produk siap-tambah, atau null bila tidak ada.
  Future<({CartItem item})?> _resolveBarcode(String barcode) async {
    final db = ref.read(databaseProvider);
    final bc = await db.lookupBarcode(barcode);
    if (bc == null) return null;
    final unit = await (db.select(db.productUnits)
          ..where((t) => t.id.equals(bc.productUnitId)))
        .getSingleOrNull();
    if (unit == null) return null;
    final product = await (db.select(db.products)
          ..where((t) => t.id.equals(unit.productId)))
        .getSingleOrNull();
    if (product == null) return null;
    final resolved =
        await PriceService(db).resolvePrice(productUnitId: unit.id, qty: 1);
    final unitType = await (db.select(db.unitTypes)
          ..where((t) => t.id.equals(unit.unitTypeId ?? 1)))
        .getSingleOrNull();
    return (
      item: CartItem(
        productId: product.id,
        productUnitId: unit.id,
        productName: product.name,
        unitName: unitType?.name ?? 'Satuan',
        qty: 1,
        price: resolved.price,
        originalPrice: resolved.price,
        costPrice: resolved.costPrice,
        barcode: barcode,
        // Bila barcode milik varian (produk anak), tandai agar tampil
        // bersarang di bawah induknya di keranjang & struk.
        parentProductId: product.parentProductId,
        isVariant: product.parentProductId != null,
      ),
    );
  }

  /// Jika [item] adalah varian dan parentnya belum ada di keranjang,
  /// tambahkan item induk sebagai placeholder dengan storedQty = 0.
  /// Setelah ini, [addItem] varian akan menaikkan storedQty induk sebesar
  /// qty varian → effective base = 0 ("via varian"). Bila induk sudah ada
  /// dengan qty dasar, biarkan apa adanya agar qty dasar tidak hilang.
  Future<void> _ensureParentInCart(CartItem variantItem) async {
    if (!variantItem.isVariant || variantItem.parentProductId == null) return;
    final cart = ref.read(cartProvider);
    final hasParent = cart.any(
        (c) => c.productId == variantItem.parentProductId && !c.isVariant);
    if (hasParent) return;

    final db = ref.read(databaseProvider);
    final parent = await (db.select(db.products)
          ..where((t) => t.id.equals(variantItem.parentProductId!)))
        .getSingleOrNull();
    if (parent == null || !mounted) return;

    final units = await db.getProductUnits(parent.id);
    if (units.isEmpty || !mounted) return;
    final base =
        units.firstWhere((u) => u.isBaseUnit, orElse: () => units.first);
    final resolved =
        await PriceService(db).resolvePrice(productUnitId: base.id, qty: 1);
    final unitType = await (db.select(db.unitTypes)
          ..where((t) => t.id.equals(base.unitTypeId ?? 1)))
        .getSingleOrNull();
    if (!mounted) return;

    ref.read(cartProvider.notifier).addItem(CartItem(
          productId: parent.id,
          productUnitId: base.id,
          productName: parent.name,
          unitName: unitType?.name ?? 'Satuan',
          // Placeholder qty 0; addItem(varian) berikutnya menaikkan storedQty
          // induk sebesar qty varian sehingga effective base = 0.
          qty: 0,
          price: resolved.price,
          originalPrice: resolved.price,
          costPrice: resolved.costPrice,
        ));
  }

  Future<void> _handleBarcode(String barcode) async {
    // Debounce: abaikan deteksi berulang barcode sama dalam 1.5 detik.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (barcode == _lastScan && nowMs - _lastScanMs < 1500) return;
    _lastScan = barcode;
    _lastScanMs = nowMs;

    if (!_continuousScan) {
      _closeScanner();
      final resolved = await _resolveBarcode(barcode);
      if (resolved == null) {
        if (mounted) _showBanner('Barcode tidak ditemukan: $barcode');
        return;
      }
      await _ensureParentInCart(resolved.item);
      ref.read(cartProvider.notifier).addItem(resolved.item);
      return;
    }

    // Mode continuous — scanner tetap terbuka, tampilkan/perbarui toast.
    final resolved = await _resolveBarcode(barcode);
    if (!mounted) return;
    if (resolved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Barcode tidak ditemukan: $barcode'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    final item = resolved.item;
    final notifier = ref.read(cartProvider.notifier);
    await _ensureParentInCart(item);
    notifier.addItem(item);
    final newQty = notifier.qtyForUnit(item.productUnitId).round();
    _showOrUpdateToast(item, newQty);
  }

  void _showOrUpdateToast(CartItem item, int qty) {
    _activeToast?.timer?.cancel();
    final toast = _ScanToast(
      productUnitId: item.productUnitId,
      productName: item.productName,
      unitName: item.unitName,
      qty: qty,
      price: item.price,
    );
    toast.timer = Timer(Duration(seconds: _toastDurationSeconds), () {
      if (mounted) setState(() => _activeToast = null);
    });
    setState(() => _activeToast = toast);
  }

  void _toastInc() {
    final t = _activeToast;
    if (t == null) return;
    final notifier = ref.read(cartProvider.notifier);
    final q = t.qty + 1;
    // setEffectiveQty agar varian menaikkan qty sambil menjaga qty dasar induk.
    notifier.setEffectiveQty(t.productUnitId, q.toDouble());
    setState(() => t.qty = q);
    t.timer?.cancel();
    t.timer = Timer(Duration(seconds: _toastDurationSeconds), () {
      if (mounted) setState(() => _activeToast = null);
    });
  }

  void _toastDec() {
    final t = _activeToast;
    if (t == null) return;
    final notifier = ref.read(cartProvider.notifier);
    final q = t.qty - 1;
    if (q <= 0) {
      notifier.removeItem(t.productUnitId);
      t.timer?.cancel();
      setState(() => _activeToast = null);
      return;
    }
    notifier.setEffectiveQty(t.productUnitId, q.toDouble());
    setState(() => t.qty = q);
    t.timer?.cancel();
    t.timer = Timer(Duration(seconds: _toastDurationSeconds), () {
      if (mounted) setState(() => _activeToast = null);
    });
  }

  void _openEntry(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ItemEntrySheet(product: product),
    );
  }

  /// Tambah cepat 1 satuan dasar (produk satuan tunggal).
  void _quickAdd(Product product, CatalogDetail detail) {
    ref.read(cartProvider.notifier).addItem(CartItem(
          productId: product.id,
          productUnitId: detail.baseUnitId,
          productName: product.name,
          unitName: detail.baseUnitName,
          qty: 1,
          price: detail.basePrice,
          originalPrice: detail.basePrice,
          costPrice: detail.costPrice,
          barcode: detail.barcode,
        ));
  }

  @override
  Widget build(BuildContext context) {
    if (_scannerOpen && _scannerCtrl != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_continuousScan ? 'Scan Berulang' : 'Scan Sekali'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _closeScanner,
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Pengaturan Scanner',
              onSelected: (v) {
                if (v == 'mode') {
                  _setContinuous(!_continuousScan);
                } else if (v.startsWith('dur:')) {
                  _setToastDuration(int.parse(v.substring(4)));
                }
              },
              itemBuilder: (ctx) => [
                CheckedPopupMenuItem(
                  value: 'mode',
                  checked: _continuousScan,
                  child: const Text('Scan Berulang'),
                ),
                const PopupMenuDivider(),
                for (final s in [3, 5, 10])
                  CheckedPopupMenuItem(
                    value: 'dur:$s',
                    checked: _toastDurationSeconds == s,
                    child: Text('Durasi Pesan: ${s}s'),
                  ),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            MobileScanner(
              controller: _scannerCtrl!,
              onDetect: (capture) {
                final barcode = capture.barcodes.firstOrNull?.rawValue;
                if (barcode != null) _handleBarcode(barcode);
              },
            ),
            if (_activeToast != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _ScanToastCard(
                  toast: _activeToast!,
                  onInc: _toastInc,
                  onDec: _toastDec,
                ),
              ),
          ],
        ),
      );
    }

    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final query = ref.watch(_kasirSearchProvider);
    final isGrid = ref.watch(kasirGridProvider);
    final heldCount = ref.watch(_heldCountProvider).valueOrNull ?? 0;
    final productsAsync = ref.watch(_kasirProductsProvider(query));
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          _KasirTopbar(
            searchCtrl: _searchCtrl,
            searchFocus: _searchFocus,
            onSearch: (v) => ref.read(_kasirSearchProvider.notifier).state = v,
            onScan: _openScanner,
            onHeld: () async {
              final msg = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const HeldOrdersSheet(),
              );
              if (msg != null && msg.isNotEmpty && mounted) {
                _showBanner(msg, InlineBannerType.success);
              }
            },
            onHistory: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const TxHistorySheet(),
            ),
            heldCount: heldCount,
            isGrid: isGrid,
            onToggleGrid: () => ref.read(kasirGridProvider.notifier).toggle(),
          ),
          InlineBanner(
            message: _bannerMsg,
            type: _bannerType,
            onDismiss: () => setState(() => _bannerMsg = null),
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
                          query.isEmpty
                              ? 'Belum ada produk'
                              : 'Produk tidak ditemukan',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                if (isGrid) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      mainAxisExtent: 138,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: prods.length,
                    itemBuilder: (_, i) => _ProductCard(
                      product: prods[i],
                      onTapBody: () => _openEntry(prods[i]),
                      onQuickAdd: _quickAdd,
                      onOpenEntry: () => _openEntry(prods[i]),
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
                    onTapBody: () => _openEntry(prods[i]),
                    onQuickAdd: _quickAdd,
                    onOpenEntry: () => _openEntry(prods[i]),
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
    required this.searchFocus,
    required this.onSearch,
    required this.onScan,
    required this.onHeld,
    required this.onHistory,
    required this.heldCount,
    required this.isGrid,
    required this.onToggleGrid,
  });

  final TextEditingController searchCtrl;
  final FocusNode searchFocus;
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
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: searchCtrl,
                    builder: (context, value, _) {
                      return TextField(
                        controller: searchCtrl,
                        focusNode: searchFocus,
                        decoration: InputDecoration(
                          hintText: 'Cari produk…',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: value.text.isNotEmpty
                              ? IconButton(
                                  icon:
                                      const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () {
                                    searchCtrl.clear();
                                    onSearch('');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
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
                  icon:
                      isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
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

// ─── Add / counter control ────────────────────────────────────────────────────

/// Tombol "+" yang berubah jadi lingkaran berisi jumlah saat produk ada di
/// keranjang. Tap menambah 1 (produk satuan tunggal) atau membuka modal
/// (produk multi-satuan).
class _AddControl extends StatelessWidget {
  const _AddControl({
    required this.qty,
    required this.onTap,
    this.onMinus,
    this.size = 34,
  });

  final double qty;
  final VoidCallback onTap;
  final VoidCallback? onMinus;
  final double size;

  @override
  Widget build(BuildContext context) {
    final inCart = qty > 0;
    final label = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = inCart ? AppTheme.changeFg(isDark) : AppTheme.accent;
    final shadowColor = inCart
        ? AppTheme.changeFg(isDark).withOpacity(0.30)
        : const Color(0x33C96442);

    // Lingkaran utama (jumlah / "+") berukuran sama baik saat kosong maupun
    // saat sudah ada di keranjang, agar tidak "melompat" ukuran.
    final circleSize = size + 4;
    final mainCircle = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: circleSize,
        height: circleSize,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: shadowColor, blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Center(
          child: inCart
              ? Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: circleSize * 0.40,
                  ),
                )
              : Icon(Icons.add_rounded,
                  color: Colors.white, size: circleSize * 0.6),
        ),
      ),
    );

    if (!inCart) return mainCircle;

    // Tombol minus: merah, sedikit lebih kecil dari lingkaran jumlah. Pakai
    // HitTestBehavior.opaque agar tap tidak "tembus" ke InkWell kartu produk.
    final minusSize = size - 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onMinus,
          child: Container(
            width: minusSize,
            height: minusSize,
            decoration: const BoxDecoration(
              color: Color(0xFFD64545),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(Icons.remove_rounded,
                  color: Colors.white, size: minusSize * 0.6),
            ),
          ),
        ),
        const SizedBox(width: 6),
        mainCircle,
      ],
    );
  }
}

// ─── Product grid card ────────────────────────────────────────────────────────

class _ProductCard extends ConsumerWidget {
  const _ProductCard({
    required this.product,
    required this.onTapBody,
    required this.onQuickAdd,
    required this.onOpenEntry,
  });

  final Product product;
  final VoidCallback onTapBody;
  final void Function(Product, CatalogDetail) onQuickAdd;
  final VoidCallback onOpenEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final grad = _gradFor(product.name);
    final detailAsync = ref.watch(_catalogDetailProvider(product.id));
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final qty = cart
        .where((c) => c.productId == product.id)
        .fold<double>(0, (s, c) => s + notifier.effectiveQtyFor(c));

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTapBody,
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
              Container(
                width: 34,
                height: 34,
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
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: detailAsync.when(
                      data: (d) => Text(
                        formatRupiah(d.basePrice),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.numStyle(context,
                            size: 14, weight: FontWeight.w700),
                      ),
                      loading: () => const SizedBox(
                        height: 14,
                        width: 40,
                        child: _PriceShimmer(),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ),
                  detailAsync.maybeWhen(
                    data: (d) => _AddControl(
                      qty: qty,
                      size: 32,
                      onTap: () {
                        if (d.baseUnitId.isEmpty || d.hasVariants) {
                          onOpenEntry();
                        } else {
                          onQuickAdd(product, d);
                        }
                      },
                      onMinus: qty > 0
                          ? () {
                              final items = cart.where(
                                  (c) => c.productId == product.id);
                              if (items.isEmpty) return;
                              final item = items.first;
                              final eff =
                                  notifier.effectiveQtyFor(item);
                              if (eff <= 1) {
                                notifier.removeItem(
                                    item.productUnitId);
                              } else {
                                notifier.setEffectiveQty(
                                    item.productUnitId, eff - 1);
                              }
                            }
                          : null,
                    ),
                    orElse: () => const SizedBox(width: 32, height: 32),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceShimmer extends StatelessWidget {
  const _PriceShimmer();
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ─── Product list tile ────────────────────────────────────────────────────────

class _ProductListTile extends ConsumerWidget {
  const _ProductListTile({
    required this.product,
    required this.onTapBody,
    required this.onQuickAdd,
    required this.onOpenEntry,
  });

  final Product product;
  final VoidCallback onTapBody;
  final void Function(Product, CatalogDetail) onQuickAdd;
  final VoidCallback onOpenEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final grad = _gradFor(product.name);
    final detailAsync = ref.watch(_catalogDetailProvider(product.id));
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final qty = cart
        .where((c) => c.productId == product.id)
        .fold<double>(0, (s, c) => s + notifier.effectiveQtyFor(c));

    return InkWell(
      onTap: onTapBody,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  detailAsync.when(
                    data: (d) => Row(
                      children: [
                        Text(
                          formatRupiah(d.basePrice),
                          style: AppTheme.numStyle(context,
                              size: 13.5,
                              weight: FontWeight.w700,
                              color: cs.primary),
                        ),
                        Text(
                          ' /${d.baseUnitName}',
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                        if (d.unitCount > 1)
                          Text(
                            '  +${d.unitCount - 1} satuan',
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                    loading: () => Text('…',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            detailAsync.maybeWhen(
              data: (d) => _AddControl(
                qty: qty,
                onTap: () {
                  if (d.baseUnitId.isEmpty || d.hasVariants) {
                    onOpenEntry();
                  } else {
                    onQuickAdd(product, d);
                  }
                },
              ),
              orElse: () => const SizedBox(width: 34, height: 34),
            ),
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
