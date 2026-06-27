import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/models/cart_item.dart';
import '../../core/providers/device_provider.dart';
import '../../core/providers/product_providers.dart';
import '../../core/services/price_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/inline_banner.dart';
import 'cart_meta_provider.dart';
import 'cart_provider.dart';
import 'widgets/cart_meta_pickers.dart';
import 'widgets/cart_sheet.dart';
import 'widgets/item_entry_sheet.dart';
import 'widgets/tx_history_sheet.dart';

const _kasirUuid = Uuid();

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

/// Panduan visual scanner: kotak transparan dengan empat sudut + garis tengah.
/// Murni dekoratif — tidak memengaruhi area deteksi (engine tetap fullframe).
class _ScanGuideOverlay extends StatelessWidget {
  const _ScanGuideOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ScanGuidePainter());
  }
}

class _ScanGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final boxW = size.width * 0.7;
    final boxH = boxW * 0.62;
    final left = (size.width - boxW) / 2;
    final top = (size.height - boxH) / 2;
    final rect = Rect.fromLTWH(left, top, boxW, boxH);

    // Kotak sudut.
    final corner = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const cLen = 26.0;
    // Kiri-atas
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(cLen, 0), corner);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, cLen), corner);
    // Kanan-atas
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-cLen, 0), corner);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, cLen), corner);
    // Kiri-bawah
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(cLen, 0), corner);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -cLen), corner);
    // Kanan-bawah
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-cLen, 0), corner);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -cLen), corner);

    // Garis tengah merah (penanda arah scan).
    final line = Paint()
      ..color = Colors.red.withOpacity(0.8)
      ..strokeWidth = 2;
    final midY = top + boxH / 2;
    canvas.drawLine(
        Offset(left + 12, midY), Offset(left + boxW - 12, midY), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

final _heldCountProvider = StreamProvider<int>((ref) {
  return ref
      .watch(databaseProvider)
      .watchHeldOrders()
      .map((list) => list.length);
});

final _heldOrdersListProvider = StreamProvider<List<HeldOrder>>((ref) {
  return ref.watch(databaseProvider).watchHeldOrders();
});

/// Bongkar payload pesanan ditahan. Format baru: objek `{items:[...], meta:{}}`.
/// Format lama (kompatibel mundur): list item langsung tanpa metadata.
({List<CartItem> items, CartMeta meta}) _parseHeldPayload(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is List) {
      // Format lama: hanya daftar item.
      return (
        items: decoded
            .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        meta: const CartMeta(),
      );
    }
    if (decoded is Map<String, dynamic>) {
      final itemsRaw = decoded['items'] as List? ?? const [];
      final metaRaw = decoded['meta'] as Map<String, dynamic>?;
      return (
        items: itemsRaw
            .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        meta: metaRaw != null ? CartMeta.fromJson(metaRaw) : const CartMeta(),
      );
    }
  } catch (_) {/* data rusak → kosong */}
  return (items: const <CartItem>[], meta: const CartMeta());
}

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

/// Info satu varian (produk anak) untuk dropdown inline di katalog kasir.
class _VariantInfo {
  const _VariantInfo({
    required this.productId,
    required this.productName,
    required this.unitId,
    required this.unitName,
    required this.price,
    required this.costPrice,
    this.barcode,
  });

  final String productId;
  final String productName;
  final String unitId;
  final String unitName;
  final int price;
  final int costPrice;
  final String? barcode;
}

final _variantsProvider =
    FutureProvider.family<List<_VariantInfo>, String>((ref, parentId) async {
  final db = ref.watch(databaseProvider);
  ref.watch(productUpdateCountProvider);
  final priceService = PriceService(db);
  final vps = await db.getVariants(parentId);
  final out = <_VariantInfo>[];
  for (final vp in vps) {
    final units = await db.getProductUnits(vp.id);
    if (units.isEmpty) continue;
    final base =
        units.firstWhere((u) => u.isBaseUnit, orElse: () => units.first);
    final resolved =
        await priceService.resolvePrice(productUnitId: base.id, qty: 1);
    final type = await (db.select(db.unitTypes)
          ..where((t) => t.id.equals(base.unitTypeId ?? 1)))
        .getSingleOrNull();
    final barcodes = await db.getProductBarcodes(base.id);
    out.add(_VariantInfo(
      productId: vp.id,
      productName: vp.name,
      unitId: base.id,
      unitName: type?.name ?? 'Satuan',
      price: resolved.price,
      costPrice: resolved.costPrice,
      barcode:
          barcodes.where((b) => b.isPrimary).map((b) => b.barcode).firstOrNull,
    ));
  }
  return out;
});

/// Tambah 1 varian ke keranjang. Memastikan induk hadir sebagai placeholder
/// agar invariant storedQty induk = base + Σ(varian) tetap terjaga.
void _incrementVariant({
  required CartNotifier notifier,
  required List<CartItem> cart,
  required Product parent,
  required CatalogDetail parentDetail,
  required _VariantInfo v,
}) {
  final existing = cart.where((c) => c.productUnitId == v.unitId).firstOrNull;
  if (existing != null) {
    notifier.setEffectiveQty(v.unitId, existing.qty + 1);
    return;
  }
  final parentInCart =
      cart.any((c) => !c.isVariant && c.productId == parent.id);
  if (!parentInCart && parentDetail.baseUnitId.isNotEmpty) {
    notifier.addItem(CartItem(
      productId: parent.id,
      productUnitId: parentDetail.baseUnitId,
      productName: parent.name,
      unitName: parentDetail.baseUnitName,
      qty: 0,
      price: parentDetail.basePrice,
      originalPrice: parentDetail.basePrice,
      costPrice: parentDetail.costPrice,
      barcode: parentDetail.barcode,
    ));
  }
  notifier.addItem(CartItem(
    productId: v.productId,
    productUnitId: v.unitId,
    productName: v.productName,
    unitName: v.unitName,
    qty: 1,
    price: v.price,
    originalPrice: v.price,
    costPrice: v.costPrice,
    barcode: v.barcode,
    parentProductId: parent.id,
    isVariant: true,
  ));
}

void _decrementVariant({
  required CartNotifier notifier,
  required List<CartItem> cart,
  required _VariantInfo v,
}) {
  final existing = cart.where((c) => c.productUnitId == v.unitId).firstOrNull;
  if (existing == null) return;
  // setEffectiveQty menangani penghapusan & penyesuaian induk saat qty <= 0.
  notifier.setEffectiveQty(v.unitId, existing.qty - 1);
}

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
  const KasirScreen({super.key, this.addToTxId});

  /// Bila terisi, layar kasir berada dalam mode "tambah belanjaan" untuk
  /// transaksi [addToTxId]: memakai keranjang terpisah dan tombol bayar
  /// menjadi "Bayar Selisih". Bila null, mode kasir biasa.
  final String? addToTxId;

  @override
  ConsumerState<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends ConsumerState<KasirScreen> {
  /// Slot keranjang aktif: keranjang utama, atau keranjang tambah belanjaan.
  String get _cartId => widget.addToTxId ?? kMainCartId;
  bool get _isAddMode => widget.addToTxId != null;
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

  // Senter (torch) scanner
  bool _torchOn = false;

  // Debounce deteksi berulang barcode yang sama
  String? _lastScan;
  int _lastScanMs = 0;

  // Panel pesanan ditahan inline (slide dari atas, mendorong katalog ke bawah).
  bool _heldPanelOpen = false;

  // Sheet keranjang sedang terbuka? Dipakai agar scan eksternal berturut-turut
  // tetap diproses saat sheet terbuka, dan agar tidak membuka sheet ganda.
  bool _cartSheetOpen = false;

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
    // Lewati jika layar kasir bukan rute teratas — KECUALI saat sheet keranjang
    // yang kita buka sendiri sedang tampil (agar scan berturut-turut tetap jalan).
    if (!_cartSheetOpen && !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }

    final now = DateTime.now();
    final gapMs = now.difference(_lastKeyTime).inMilliseconds;
    _lastKeyTime = now;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final code = _hwScanBuffer.toString().trim();
      _hwScanBuffer.clear();
      if (code.length >= _kMinBarcodeLen) {
        _handleBarcode(code, fromExternal: true);
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
      _torchOn = false;
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
      _torchOn = false;
    });
  }

  Future<void> _toggleTorch() async {
    final ctrl = _scannerCtrl;
    if (ctrl == null) return;
    await ctrl.toggleTorch();
    if (mounted) setState(() => _torchOn = !_torchOn);
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
    final cart = ref.read(cartProvider(_cartId));
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

    ref.read(cartProvider(_cartId).notifier).addItem(CartItem(
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

  Future<void> _handleBarcode(String barcode, {bool fromExternal = false}) async {
    // Debounce: abaikan deteksi berulang barcode sama dalam 1.5 detik.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (barcode == _lastScan && nowMs - _lastScanMs < 1500) return;
    _lastScan = barcode;
    _lastScanMs = nowMs;

    // Scanner eksternal (HID): tambah ke keranjang, beri haptik, lalu buka
    // sheet keranjang sebagai konfirmasi visual (mode kamera tak terpakai).
    if (fromExternal) {
      final resolved = await _resolveBarcode(barcode);
      if (resolved == null) {
        if (mounted) _showBanner('Barcode tidak ditemukan: $barcode');
        return;
      }
      await _ensureParentInCart(resolved.item);
      ref.read(cartProvider(_cartId).notifier).addItem(resolved.item);
      HapticFeedback.heavyImpact();
      _openCartSheet();
      return;
    }

    if (!_continuousScan) {
      _closeScanner();
      final resolved = await _resolveBarcode(barcode);
      if (resolved == null) {
        if (mounted) _showBanner('Barcode tidak ditemukan: $barcode');
        return;
      }
      await _ensureParentInCart(resolved.item);
      ref.read(cartProvider(_cartId).notifier).addItem(resolved.item);
      HapticFeedback.heavyImpact();
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
    final notifier = ref.read(cartProvider(_cartId).notifier);
    await _ensureParentInCart(item);
    notifier.addItem(item);
    HapticFeedback.heavyImpact();
    final newQty = notifier.qtyForUnit(item.productUnitId).round();
    _showOrUpdateToast(item, newQty);
  }

  /// Buka sheet keranjang. Bila sudah terbuka, isi diperbarui otomatis lewat
  /// provider — tidak membuka sheet kedua.
  void _openCartSheet() {
    if (_cartSheetOpen) return;
    _cartSheetOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CartSheet(cartId: _cartId),
    ).whenComplete(() => _cartSheetOpen = false);
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
    final notifier = ref.read(cartProvider(_cartId).notifier);
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
    final notifier = ref.read(cartProvider(_cartId).notifier);
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
      builder: (_) => ItemEntrySheet(product: product, cartId: _cartId),
    );
  }

  /// Tahan keranjang aktif. Bila pelanggan sudah dipilih, langsung pakai
  /// namanya sebagai label (tanpa dialog). Bila belum, minta penanda.
  Future<void> _holdCurrent() async {
    final cart = ref.read(cartProvider(_cartId));
    if (cart.isEmpty) return;
    final meta = ref.read(cartMetaProvider(_cartId));

    String label;
    if (meta.hasCustomer) {
      label = meta.customerName!;
    } else {
      final entered = await _askHoldLabel();
      if (entered == null) return; // dibatalkan
      label = entered;
    }

    final db = ref.read(databaseProvider);
    final payload = jsonEncode({
      'items': cart.map((c) => c.toJson()).toList(),
      'meta': meta.toJson(),
    });
    await db.holdOrder(id: _kasirUuid.v4(), label: label, cartJson: payload);
    ref.read(cartProvider(_cartId).notifier).clear();
    ref.read(cartMetaProvider(_cartId).notifier).clear();
    if (mounted) {
      setState(() => _heldPanelOpen = false);
      _showBanner('Pesanan "$label" ditahan', InlineBannerType.success);
    }
  }

  Future<String?> _askHoldLabel() async {
    final ctrl = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tahan Pesanan'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nama / penanda',
              hintText: 'Contoh: Bu Sari',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Batal')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(
                  ctrl.text.trim().isEmpty ? 'Pesanan' : ctrl.text.trim()),
              child: const Text('Tahan'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _resumeHeld(HeldOrder order) async {
    final parsed = _parseHeldPayload(order.cartJson);
    if (parsed.items.isEmpty) {
      _showBanner('Data pesanan rusak — tidak ada item yang bisa dipulihkan');
      return;
    }
    final cart = ref.read(cartProvider(_cartId));
    if (cart.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ganti Keranjang?'),
          content: const Text(
              'Keranjang saat ini akan diganti dengan pesanan yang ditahan. '
              'Tahan dulu keranjang aktif jika tidak ingin hilang.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Ganti')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    await ref.read(databaseProvider).deleteHeldOrder(order.id);
    ref.read(cartProvider(_cartId).notifier).replaceAll(parsed.items);
    ref.read(cartMetaProvider(_cartId).notifier).replaceAll(parsed.meta);
    if (mounted) {
      setState(() => _heldPanelOpen = false);
      _showBanner('Melanjutkan pesanan: ${order.label}',
          InlineBannerType.success);
    }
  }

  /// Tambah cepat 1 satuan dasar (produk satuan tunggal).
  void _quickAdd(Product product, CatalogDetail detail) {
    ref.read(cartProvider(_cartId).notifier).addItem(CartItem(
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
            IconButton(
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
              tooltip: 'Senter',
              onPressed: _toggleTorch,
            ),
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
            // Overlay panduan visual (dekoratif — TIDAK membatasi area deteksi;
            // engine tetap membaca barcode dari seluruh frame).
            const Positioned.fill(
              child: IgnorePointer(
                child: _ScanGuideOverlay(),
              ),
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

    final cart = ref.watch(cartProvider(_cartId));
    final cartNotifier = ref.read(cartProvider(_cartId).notifier);
    final query = ref.watch(_kasirSearchProvider);
    final isGrid = ref.watch(kasirGridProvider);
    final heldCount = ref.watch(_heldCountProvider).valueOrNull ?? 0;
    final productsAsync = ref.watch(_kasirProductsProvider(query));
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _isAddMode
          ? AppBar(
              title: const Text('Tambah Belanjaan'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Batal',
                onPressed: () => context.pop(),
              ),
            )
          : null,
      body: Column(
        children: [
          _KasirTopbar(
            searchCtrl: _searchCtrl,
            searchFocus: _searchFocus,
            onSearch: (v) => ref.read(_kasirSearchProvider.notifier).state = v,
            onScan: _openScanner,
            onHeld: () => setState(() => _heldPanelOpen = !_heldPanelOpen),
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
          // Panel pesanan ditahan — slide inline dari atas (mendorong katalog
          // ke bawah, bukan overlay modal).
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _heldPanelOpen
                ? _HeldInlinePanel(
                    onResume: _resumeHeld,
                    onClose: () => setState(() => _heldPanelOpen = false),
                  )
                : const SizedBox(width: double.infinity),
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
                      cartId: _cartId,
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
                    cartId: _cartId,
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
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tab folder pelanggan & pegawai + tombol tahan — hanya di mode
                // kasir biasa (mode tambah belanjaan mengikuti transaksi asli).
                if (!_isAddMode)
                  _CartMetaTab(
                    cartId: _cartId,
                    onHold: _holdCurrent,
                  ),
                _CartBar(
                  total: cartNotifier.totalAmount,
                  count: cart.length,
                  payLabel: _isAddMode ? 'Bayar Selisih' : null,
                  lastItem: _isAddMode ? null : cartNotifier.lastTouchedItem,
                  lastEffQty: cartNotifier.lastTouchedItem == null
                      ? 0
                      : cartNotifier
                          .effectiveQtyFor(cartNotifier.lastTouchedItem!),
                  onView: _openCartSheet,
                  onPay: () => _isAddMode
                      ? context.push('/kasir/tambah/${widget.addToTxId}/bayar')
                      : context.go('/kasir/bayar'),
                ),
              ],
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

/// Kurangi 1 satuan dasar produk [productId] dari keranjang. Item dihapus bila
/// effective qty turun ke 0. Dipakai oleh tombol minus di kartu & list produk.
void _decrementProduct(
    List<CartItem> cart, CartNotifier notifier, String productId) {
  final items = cart.where((c) => c.productId == productId);
  if (items.isEmpty) return;
  final item = items.first;
  final eff = notifier.effectiveQtyFor(item);
  if (eff <= 1) {
    notifier.removeItem(item.productUnitId);
  } else {
    notifier.setEffectiveQty(item.productUnitId, eff - 1);
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
    required this.cartId,
    required this.onTapBody,
    required this.onQuickAdd,
    required this.onOpenEntry,
  });

  final Product product;
  final String cartId;
  final VoidCallback onTapBody;
  final void Function(Product, CatalogDetail) onQuickAdd;
  final VoidCallback onOpenEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final grad = _gradFor(product.name);
    final detailAsync = ref.watch(_catalogDetailProvider(product.id));
    final cart = ref.watch(cartProvider(cartId));
    final notifier = ref.read(cartProvider(cartId).notifier);
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
                        // "+" selalu menambah satuan dasar induk, walau produk
                        // punya varian. Pilih varian via tahan item / ketuk body.
                        if (d.baseUnitId.isEmpty) {
                          onOpenEntry();
                        } else {
                          onQuickAdd(product, d);
                        }
                      },
                      onMinus: qty > 0
                          ? () => _decrementProduct(
                              cart, notifier, product.id)
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

class _ProductListTile extends ConsumerStatefulWidget {
  const _ProductListTile({
    required this.product,
    required this.cartId,
    required this.onTapBody,
    required this.onQuickAdd,
    required this.onOpenEntry,
  });

  final Product product;
  final String cartId;
  final VoidCallback onTapBody;
  final void Function(Product, CatalogDetail) onQuickAdd;
  final VoidCallback onOpenEntry;

  @override
  ConsumerState<_ProductListTile> createState() => _ProductListTileState();
}

class _ProductListTileState extends ConsumerState<_ProductListTile> {
  bool _expanded = false;

  Product get product => widget.product;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grad = _gradFor(product.name);
    final detailAsync = ref.watch(_catalogDetailProvider(product.id));
    final cart = ref.watch(cartProvider(widget.cartId));
    final notifier = ref.read(cartProvider(widget.cartId).notifier);
    final qty = cart
        .where((c) => c.productId == product.id)
        .fold<double>(0, (s, c) => s + notifier.effectiveQtyFor(c));
    final hasVariants = detailAsync.maybeWhen(
        data: (d) => d.hasVariants, orElse: () => false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: widget.onTapBody,
          // Tahan item dengan varian → buka/tutup dropdown varian inline.
          onLongPress:
              hasVariants ? () => setState(() => _expanded = !_expanded) : null,
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          if (hasVariants) ...[
                            const SizedBox(width: 4),
                            Icon(
                              _expanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                          ],
                        ],
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
                      // "+" selalu menambah satuan dasar induk, walau punya
                      // varian. Pilih varian via tahan item / ketuk body.
                      if (d.baseUnitId.isEmpty) {
                        widget.onOpenEntry();
                      } else {
                        widget.onQuickAdd(product, d);
                      }
                    },
                    onMinus: qty > 0
                        ? () => _decrementProduct(cart, notifier, product.id)
                        : null,
                  ),
                  orElse: () => const SizedBox(width: 34, height: 34),
                ),
              ],
            ),
          ),
        ),
        // Dropdown varian inline — mendorong item di bawahnya, bukan popup.
        if (_expanded && hasVariants)
          _VariantDropdown(
            parent: product,
            parentDetail: detailAsync.asData?.value,
            cartId: widget.cartId,
          ),
      ],
    );
  }
}

/// Daftar varian inline di bawah item produk. Tiap baris punya kontrol +/-
/// dengan desain sama seperti tombol di item produk.
class _VariantDropdown extends ConsumerWidget {
  const _VariantDropdown({
    required this.parent,
    required this.parentDetail,
    required this.cartId,
  });

  final Product parent;
  final CatalogDetail? parentDetail;
  final String cartId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final variantsAsync = ref.watch(_variantsProvider(parent.id));
    final cart = ref.watch(cartProvider(cartId));
    final notifier = ref.read(cartProvider(cartId).notifier);

    return Container(
      color: cs.surfaceContainerHighest.withOpacity(0.4),
      padding: const EdgeInsets.only(left: 54, right: 12, top: 2, bottom: 6),
      child: variantsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
        error: (_, __) => const SizedBox.shrink(),
        data: (variants) {
          if (variants.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Tidak ada varian',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            );
          }
          return Column(
            children: [
              for (final v in variants)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500)),
                            Text(
                              '${formatRupiah(v.price)} /${v.unitName}',
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Builder(builder: (_) {
                        final vQty = cart
                            .where((c) => c.productUnitId == v.unitId)
                            .fold<double>(0, (s, c) => s + c.qty);
                        return _AddControl(
                          qty: vQty,
                          size: 28,
                          onTap: () {
                            final d = parentDetail;
                            if (d == null) return;
                            _incrementVariant(
                              notifier: notifier,
                              cart: cart,
                              parent: parent,
                              parentDetail: d,
                              v: v,
                            );
                          },
                          onMinus: vQty > 0
                              ? () => _decrementVariant(
                                  notifier: notifier, cart: cart, v: v)
                              : null,
                        );
                      }),
                    ],
                  ),
                ),
            ],
          );
        },
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
    this.payLabel,
    this.lastItem,
    this.lastEffQty = 0,
  });

  final int total;
  final int count;
  final VoidCallback onView;
  final VoidCallback onPay;
  final String? payLabel;

  /// Produk terakhir yang ditambahkan/disentuh — ditampilkan ringkas di bawah
  /// total. null bila tidak relevan (mis. mode tambah belanjaan).
  final CartItem? lastItem;
  final double lastEffQty;

  /// Ringkasan satu baris item terakhir: "2 pcs · **Indomie Goreng** · Rp 2.500".
  ({String prefix, String name, String suffix})? _lastItemParts() {
    final it = lastItem;
    if (it == null || lastEffQty <= 0) return null;
    final qtyStr =
        lastEffQty % 1 == 0 ? lastEffQty.toInt().toString() : '$lastEffQty';
    final unit = it.unitName.isEmpty ? '' : ' ${it.unitName}';
    return (
      prefix: '$qtyStr$unit · ',
      name: it.productName,
      suffix: ' · ${formatRupiah(it.price)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final lastParts = _lastItemParts();

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      padding: EdgeInsets.fromLTRB(14, 12, 14, 12 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Total diperbesar & di-center, dengan badge jumlah item di kiri.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
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
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    formatRupiah(total),
                    style: AppTheme.numStyle(context,
                        size: 23, weight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
          if (lastParts != null) ...[
            const SizedBox(height: 5),
            Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
                children: [
                  TextSpan(text: lastParts.prefix),
                  TextSpan(
                    text: lastParts.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: lastParts.suffix),
                ],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          // Tombol Lihat & Bayar sejajar penuh di bawah total.
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onView,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: cs.outlineVariant),
                    foregroundColor: cs.onSurface,
                  ),
                  child: const Text(
                    'Lihat',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onPay,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    payLabel ?? 'Bayar',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Tab folder pelanggan/pegawai + tahan ──────────────────────────────────

/// Tab berbentuk trapesium (seperti label folder) yang menempel di atas cart
/// bar. Berisi chip pelanggan, chip pegawai, dan tombol tahan pesanan.
class _CartMetaTab extends ConsumerWidget {
  const _CartMetaTab({required this.cartId, required this.onHold});

  final String cartId;
  final VoidCallback onHold;

  Future<void> _pickCustomer(BuildContext context, WidgetRef ref) async {
    final meta = ref.read(cartMetaProvider(cartId));
    final pick = await showCustomerPickerSheet(context, ref,
        currentName: meta.customerName);
    if (pick == null) return;
    ref.read(cartMetaProvider(cartId).notifier).setCustomer(pick.id, pick.name);
  }

  Future<void> _pickEmployee(BuildContext context, WidgetRef ref) async {
    final meta = ref.read(cartMetaProvider(cartId));
    final pick = await showEmployeePickerSheet(context, ref,
        currentId: meta.employeeId);
    if (pick == null) return;
    ref.read(cartMetaProvider(cartId).notifier).setEmployee(pick.id, pick.name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final meta = ref.watch(cartMetaProvider(cartId));
    final notifier = ref.read(cartMetaProvider(cartId).notifier);
    const slant = 14.0;

    return Align(
      alignment: Alignment.centerLeft,
      child: Transform.translate(
        // Geser turun 1px agar dasar tab menutup garis batas atas cart bar →
        // tampak menyatu seperti tab folder yang menonjol dari bar.
        offset: const Offset(0, 1),
        child: CustomPaint(
          painter: _TabPainter(
            fill: cs.surface,
            border: cs.outlineVariant,
            slant: slant,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(slant + 10, 7, slant + 10, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MetaChip(
                  icon: Icons.person_outline,
                  label: meta.hasCustomer ? meta.customerName! : 'Pelanggan',
                  active: meta.hasCustomer,
                  onTap: () => _pickCustomer(context, ref),
                  onClear:
                      meta.hasCustomer ? () => notifier.clearCustomer() : null,
                ),
                const SizedBox(width: 4),
                _MetaChip(
                  icon: Icons.badge_outlined,
                  label: meta.hasEmployee ? meta.employeeName! : 'Pegawai',
                  active: meta.hasEmployee,
                  onTap: () => _pickEmployee(context, ref),
                  onClear:
                      meta.hasEmployee ? () => notifier.clearEmployee() : null,
                ),
                const SizedBox(width: 4),
                // Tombol tahan pesanan.
                InkWell(
                  onTap: onHold,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pause_circle_outline,
                            size: 16, color: cs.primary),
                        const SizedBox(width: 4),
                        Text('Tahan',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: cs.primary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = active ? cs.onSurface : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? cs.primary : fg),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  fontStyle: active ? FontStyle.normal : FontStyle.italic,
                  color: fg,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Icon(Icons.close, size: 14, color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabPainter extends CustomPainter {
  _TabPainter({required this.fill, required this.border, required this.slant});

  final Color fill;
  final Color border;
  final double slant;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(slant, 0)
      ..lineTo(size.width - slant, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, Paint()..color = fill);

    // Garis tepi hanya pada sisi atas + dua sisi miring (dasar dibiarkan
    // terbuka agar menyatu dengan cart bar).
    final stroke = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final edge = Path()
      ..moveTo(0, size.height)
      ..lineTo(slant, 0)
      ..lineTo(size.width - slant, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(edge, stroke);
  }

  @override
  bool shouldRepaint(covariant _TabPainter old) =>
      old.fill != fill || old.border != border || old.slant != slant;
}

// ─── Panel pesanan ditahan (inline) ────────────────────────────────────────

class _HeldInlinePanel extends ConsumerWidget {
  const _HeldInlinePanel({required this.onResume, required this.onClose});

  final void Function(HeldOrder) onResume;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final heldAsync = ref.watch(_heldOrdersListProvider);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'PESANAN DITAHAN',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          heldAsync.when(
            data: (held) {
              if (held.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text('Tidak ada pesanan ditahan.',
                      style: TextStyle(
                          fontSize: 12.5, color: cs.onSurfaceVariant)),
                );
              }
              return SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: held.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 9),
                  itemBuilder: (_, i) =>
                      _HeldCard(order: held[i], onTap: () => onResume(held[i])),
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('Error: $e',
                  style: TextStyle(fontSize: 12, color: cs.error)),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeldCard extends StatelessWidget {
  const _HeldCard({required this.order, required this.onTap});

  final HeldOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parsed = _parseHeldPayload(order.cartJson);
    final itemCount = parsed.items.where((c) => !c.isVariant).length;
    final total = parsed.items.fold<int>(0, (s, c) => s + c.subtotal);
    final time =
        '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 158,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              order.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              '$itemCount item · $time',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const Spacer(),
            Text(
              formatRupiah(total),
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }
}
