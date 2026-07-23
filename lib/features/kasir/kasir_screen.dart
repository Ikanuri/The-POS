import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
import '../../core/providers/low_stock_alert_provider.dart';
import '../../core/providers/product_providers.dart';
import '../../core/services/order_page_service.dart';
import '../../core/services/order_parser_service.dart';
import '../../core/services/price_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/inline_banner.dart';
import '../../core/widgets/item_count_badge.dart';
import '../produk/catalog/catalog_models.dart';
import '../produk/catalog/catalog_share.dart';
import '../produk/catalog/catalog_store.dart';
import '../shell/sync_status_banner.dart';
import 'cart_meta_provider.dart';
import 'cart_provider.dart';
import 'handoff_gate_provider.dart';
import 'widgets/add_control.dart';
import 'widgets/cart_meta_pickers.dart';
import 'widgets/cart_sheet.dart';
import 'widgets/item_entry_sheet.dart';
import 'widgets/paste_order_sheet.dart';
import 'widgets/tx_history_sheet.dart';

const _kasirUuid = Uuid();

/// Query pencarian, di-key per slot keranjang (kasir utama vs mode katalog
/// vs tambah belanjaan). Dulu satu StateProvider global: teks yang diketik di
/// kasir ikut memfilter mode katalog (dan sebaliknya) padahal field pencarian
/// layar itu kosong — filter aktif tapi tombol hapusnya tersembunyi.
/// autoDispose membuat query mode non-utama hilang saat layarnya ditutup.
final _kasirSearchProvider =
    StateProvider.autoDispose.family<String, String>((ref, cartId) => '');

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
  double qty;
  final int price;
  Timer? timer;
}

/// Sama seperti label `AddControl` — tampilkan bulat tanpa desimal kalau
/// memang bulat (mis. "2"), tapi TIDAK dibulatkan kalau desimal (mis.
/// "0.25") — dulu toast scan memakai `.round()` sebelum sampai di sini,
/// membuat qty pecahan (produk timbang) hilang jadi "0".
String _fmtToastQty(double qty) =>
    qty % 1 == 0 ? qty.toInt().toString() : qty.toString();

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
            ConstrainedBox(
              // minWidth (bukan width tetap) — angka pecahan (mis. "1.25",
              // produk timbang) lebih panjang dari 1-2 digit biasa, lebar
              // tetap dulu bikin RenderFlex Row ini overflow.
              constraints: const BoxConstraints(minWidth: 28),
              child: Text(_fmtToastQty(toast.qty),
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

// ─── Item 24f — kapsul kontrol scanner melayang di frame kamera ────────────
// Gaya kamera bawaan HP (mis. pill zoom "0.6 · 1X · 2"): kapsul-kapsul kecil
// TERPISAH, bukan digabung 1 panel besar/menu titik-tiga — supaya gampang
// dijangkau jempol & tidak menutupi area bidik tengah.

const _kScanCapsuleBg = Color(0x73000000); // hitam semi-transparan (~45%)

/// Satu tombol icon melayang (mis. tutup/senter).
class _ScanCapsuleIconButton extends StatelessWidget {
  const _ScanCapsuleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kScanCapsuleBg,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}

/// Segmented pill "Sekali | Berulang".
class _ScanModeSegment extends StatelessWidget {
  const _ScanModeSegment({required this.continuous, required this.onChanged});

  final bool continuous;
  final ValueChanged<bool> onChanged;

  Widget _seg(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kScanCapsuleBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _seg('Sekali', !continuous, () => onChanged(false)),
            _seg('Berulang', continuous, () => onChanged(true)),
          ],
        ),
      ),
    );
  }
}

/// Kapsul toggle label + icon (dipakai untuk "Tap to Scan").
class _ScanCapsuleToggle extends StatelessWidget {
  const _ScanCapsuleToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: value ? AppTheme.accent : _kScanCapsuleBg,
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value
                  ? Icons.center_focus_strong
                  : Icons.center_focus_weak_outlined,
              size: 15,
              color: Colors.white,
            ),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Kapsul kecil siklus durasi toast (tap untuk pindah 3s → 5s → 10s → ...).
class _ScanDurationCapsule extends StatelessWidget {
  const _ScanDurationCapsule({required this.seconds, required this.onTap});

  final int seconds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _kScanCapsuleBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text('Pesan ${seconds}s',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Tombol bidik manual (tap-to-scan) — muncul/hilang dgn animasi "plop"
/// (scale+fade, sedikit overshoot), TIDAK dipaksakan di mode auto-continuous.
class _ScanShutterButton extends StatelessWidget {
  const _ScanShutterButton({
    super.key,
    required this.visible,
    required this.enabled,
    required this.onTap,
  });

  final bool visible;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1 : 0.7,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: GestureDetector(
            onTap: enabled ? onTap : null,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border:
                    Border.all(color: Colors.white.withOpacity(0.35), width: 4),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Icon(
                Icons.center_focus_strong,
                color: enabled ? AppTheme.accent : Colors.grey,
                size: 30,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pemicu animasi pulse garis scan — dipanggil saat produk berhasil discan
/// dalam mode berulang (kamera tetap terbuka).
class ScanPulseController extends ChangeNotifier {
  void pulse() => notifyListeners();
}

/// Panduan visual scanner: kotak transparan dengan empat sudut + garis tengah.
/// Murni dekoratif — tidak memengaruhi area deteksi (engine tetap fullframe).
/// Garis tengah berdenyut (menebal + hijau) sesaat saat [controller] memicu
/// pulse, sebagai konfirmasi visual produk berhasil discan.
class _ScanGuideOverlay extends StatefulWidget {
  const _ScanGuideOverlay({required this.controller});

  final ScanPulseController controller;

  @override
  State<_ScanGuideOverlay> createState() => _ScanGuideOverlayState();
}

class _ScanGuideOverlayState extends State<_ScanGuideOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPulse);
  }

  void _onPulse() {
    _anim.forward(from: 0);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPulse);
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        // Naik cepat ke puncak (menebal+hijau) lalu turun kembali ke garis
        // tipis merah — kurva segitiga sederhana berbasis sin agar mulus.
        final t = (math.sin(_anim.value * math.pi)).clamp(0.0, 1.0);
        return CustomPaint(painter: _ScanGuidePainter(pulse: t));
      },
    );
  }
}

class _ScanGuidePainter extends CustomPainter {
  _ScanGuidePainter({this.pulse = 0});

  /// 0 = garis merah normal (2px), 1 = puncak denyut (6px, hijau).
  final double pulse;

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
    canvas.drawLine(
        rect.topRight, rect.topRight + const Offset(-cLen, 0), corner);
    canvas.drawLine(
        rect.topRight, rect.topRight + const Offset(0, cLen), corner);
    // Kiri-bawah
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft + const Offset(cLen, 0), corner);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft + const Offset(0, -cLen), corner);
    // Kanan-bawah
    canvas.drawLine(
        rect.bottomRight, rect.bottomRight + const Offset(-cLen, 0), corner);
    canvas.drawLine(
        rect.bottomRight, rect.bottomRight + const Offset(0, -cLen), corner);

    // Garis tengah — merah normal, menebal & hijau sesaat saat pulse aktif.
    final color = Color.lerp(
        Colors.red.withOpacity(0.8), const Color(0xFF22C55E), pulse)!;
    final line = Paint()
      ..color = color
      ..strokeWidth = 2 + pulse * 4
      ..strokeCap = StrokeCap.round;
    final midY = top + boxH / 2;
    canvas.drawLine(
        Offset(left + 12, midY), Offset(left + boxW - 12, midY), line);
  }

  @override
  bool shouldRepaint(covariant _ScanGuidePainter oldDelegate) =>
      oldDelegate.pulse != pulse;
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
/// `awaitingPayment` (Item 24d) — true untuk handoff pegawai via QR (lihat
/// `cart_sheet.dart` `_showHandoffQr`), beda tampilan di `_HeldCard`.
/// `employeeName` (susulan Item 24d) — nama pegawai PENGIRIM handoff,
/// disimpan TERPISAH dari `label` (yang sekarang jadi nama pelanggan)
/// supaya keduanya bisa tampil bersamaan di `_HeldCard` (tab pegawai +
/// judul kartu pelanggan).
({
  List<CartItem> items,
  CartMeta meta,
  bool awaitingPayment,
  String? employeeName,
}) _parseHeldPayload(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is List) {
      // Format lama: hanya daftar item.
      final items = decoded
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return (
        items: items,
        meta: const CartMeta(),
        awaitingPayment: false,
        employeeName: null,
      );
    }
    if (decoded is Map<String, dynamic>) {
      final itemsRaw = decoded['items'] as List? ?? const [];
      final metaRaw = decoded['meta'] as Map<String, dynamic>?;
      final items = itemsRaw
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return (
        items: items,
        meta: metaRaw != null ? CartMeta.fromJson(metaRaw) : const CartMeta(),
        awaitingPayment: decoded['awaitingPayment'] as bool? ?? false,
        employeeName: decoded['employeeName'] as String?,
      );
    }
  } catch (_) {/* data rusak → kosong */}
  return (
    items: const <CartItem>[],
    meta: const CartMeta(),
    awaitingPayment: false,
    employeeName: null,
  );
}

final _kasirProductsProvider =
    StreamProvider.family<List<Product>, (String, int?)>((ref, args) {
  final db = ref.watch(databaseProvider);
  return db.watchProductsForKasir(query: args.$1, groupId: args.$2);
});

/// Item 54 — chip kategori tab Kasir: kategori terurut `sortOrder` (drag
/// reorder) + kategori yang sedang difilter (single-select, null = "Semua").
final _kasirGroupsProvider =
    StreamProvider.autoDispose<List<ProductGroup>>((ref) {
  return ref.watch(databaseProvider).watchProductGroupsForKasir();
});
final _kasirSelectedGroupProvider = StateProvider<int?>((ref) => null);

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
  ref.watch(_kasirProductsProvider(('', null)));
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
  final base = units.firstWhere((u) => u.isBaseUnit, orElse: () => units.first);
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

List<Color> _gradFor(String name) => _kAvatarGradients[
    (name.isEmpty ? 0 : name.codeUnitAt(0)) % _kAvatarGradients.length];

/// Item 46 — observer rute navigator shell, dipakai `_KasirScreenState`
/// (RouteAware) untuk tahu kapan pengguna KEMBALI ke kasir (dari layar
/// bayar/struk) → saat itulah banner "stok menipis" ditampilkan. Dipasang di
/// `ShellRoute.observers` (app_router.dart).
final RouteObserver<ModalRoute<void>> kasirRouteObserver =
    RouteObserver<ModalRoute<void>>();

class KasirScreen extends ConsumerStatefulWidget {
  const KasirScreen({super.key, this.addToTxId, this.catalogMode = false});

  /// Bila terisi, layar kasir berada dalam mode "tambah belanjaan" untuk
  /// transaksi [addToTxId]: memakai keranjang terpisah dan tombol bayar
  /// menjadi "Bayar Selisih". Bila null, mode kasir biasa.
  final String? addToTxId;

  /// Bila true, layar kasir "dipinjam" untuk membuat katalog: memakai keranjang
  /// terpisah (kCatalogCartId), menyembunyikan tombol Antrian/Riwayat & tab
  /// tahan, dan cart bar diganti aksi Simpan/Bagikan katalog.
  final bool catalogMode;

  @override
  ConsumerState<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends ConsumerState<KasirScreen> with RouteAware {
  /// Slot keranjang aktif: katalog, tambah belanjaan, atau keranjang utama.
  String get _cartId =>
      widget.catalogMode ? kCatalogCartId : (widget.addToTxId ?? kMainCartId);
  bool get _isAddMode => widget.addToTxId != null;
  bool get _isCatalogMode => widget.catalogMode;
  static const _prefContinuous = 'scanner_continuous';
  static const _prefToastDuration = 'scanner_toast_duration';
  static const _prefTapToScan = 'scanner_tap_to_scan';

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  /// Set oleh kartu/tile produk (lewat `onBeforeTap`) tepat sebelum tap
  /// "+"/badan-produk terjadi, HANYA bila field cari sedang expanded &
  /// berisi teks. Dibaca-lalu-direset oleh Listener pengecil field cari di
  /// bawah topbar — mencegah field mengecil/kehilangan fokus akibat tap
  /// yang sebenarnya membuka modal pilih harga / quick-add, bukan tap "di
  /// luar" yang genuin. Listener descendant (kartu produk) selalu menerima
  /// PointerDownEvent lebih dulu daripada Listener ancestor (urutan hit-test
  /// Flutter: leaf → root), jadi flag ini sudah ter-set sebelum ancestor
  /// memutuskan unfocus atau tidak.
  bool _skipNextSearchCollapse = false;

  /// true SELAMA modal ItemEntrySheet terbuka akibat tap badan produk (bukan
  /// tap "+"biasa) yang dipicu saat field cari sedang expanded & berisi
  /// teks — lihat `_openEntry`. Menahan `_KasirTopbar` tetap melebar walau
  /// FocusNode field kehilangan fokus asli (diambil alih route/modal baru).
  bool _searchForceExpanded = false;

  void _markSkipSearchCollapse() {
    if (_searchFocus.hasFocus && _searchCtrl.text.isNotEmpty) {
      _skipNextSearchCollapse = true;
    }
  }

  bool _scannerOpen = false;
  MobileScannerController? _scannerCtrl;
  final _scanPulseController = ScanPulseController();

  // ── Scanner barcode eksternal (HID: USB OTG / Bluetooth HID) ──────────────
  // Scanner HID mengirim barcode seperti ketikan keyboard sangat cepat yang
  // diakhiri Enter. Kita kumpulkan karakter di buffer dan proses saat Enter.
  // Tidak ada konflik dengan printer Bluetooth (printer pakai profil SPP).
  final StringBuffer _hwScanBuffer = StringBuffer();
  DateTime _lastKeyTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _kHumanGapMs = 200; // jeda antar-tombol manusia > 200ms
  static const _kMinBarcodeLen = 3;

  // Item 24d susulan — kode `#PSN:` (handoff pegawai/pesanan pelanggan) itu
  // multi-baris (kode mesin + baris opsional Pegawai:/Nama:/HP:/Catatan:).
  // Scanner eksternal (keyboard wedge) mengirim newline DI DALAM payload
  // QR sebagai keystroke Enter TERPISAH — jadi 1 scan QR pecah jadi
  // beberapa "scan" beruntun dari sudut pandang app ini (baris pertama
  // #PSN:... tiba TANPA baris Pegawai:/Nama: yang menyusul, salah rute ke
  // "Tempel Pesanan" alih-alih antrian). Gabungkan kembali fragmen yang
  // datang SEGERA setelah baris #PSN: sebelumnya.
  String? _pendingOrderCodeBuffer;
  Timer? _orderCodeMergeTimer;
  static const _kOrderCodeMergeWindow = Duration(milliseconds: 350);

  // Mode scanner
  bool _continuousScan = false;
  int _toastDurationSeconds = 5;

  // Item 24e — tap-to-scan: opsi tambahan (bukan pengganti default), untuk
  // situasi presisi lebih penting daripada kecepatan (mis. rak dengan
  // banyak barcode berdekatan, rawan salah pindai kalau auto-continuous).
  // Saat aktif: barcode yang terdeteksi kamera TIDAK langsung diproses,
  // cuma ditampung di _pendingBarcode sampai pengguna tap tombol bidik.
  bool _tapToScan = false;
  String? _pendingBarcode;

  // Item 24e susulan — kamera masih bisa melaporkan barcode yang SUDAH
  // disingkirkan fisik (frame basi akibat latensi pipeline kamera,
  // terutama di HP kelas bawah) SESAAT setelah bidik ditap — tanpa
  // penjagaan ini, deteksi basi itu meng-isi ulang `_pendingBarcode`
  // dengan barcode yang SAMA, membuat tap bidik berikutnya (dimaksudkan
  // no-op krn tidak ada barcode di frame) justru mengulang barang lama.
  String? _lastConfirmedBarcode;
  DateTime? _lastConfirmedAt;
  static const _kStaleDetectionCooldown = Duration(milliseconds: 1200);

  // Toast melayang (mode continuous)
  _ScanToast? _activeToast;

  // Senter (torch) scanner
  bool _torchOn = false;

  // Debounce deteksi berulang barcode yang sama
  String? _lastScan;
  int _lastScanMs = 0;

  // Panel pesanan ditahan inline (slide dari atas, mendorong katalog ke bawah).
  bool _heldPanelOpen = false;
  final _heldPanelKey = GlobalKey();

  // Sheet keranjang sedang terbuka? Dipakai agar scan eksternal berturut-turut
  // tetap diproses saat sheet terbuka, dan agar tidak membuka sheet ganda.
  bool _cartSheetOpen = false;

  // Hint swipe-ke-atas: tampil hingga pengguna memakai gesture 3 kali.
  bool _swipeHintVisible = false;
  static const _kSwipeHintCountKey = 'kasir_swipe_hint_count';

  // Banner notifikasi inline (bukan SnackBar overlay)
  String? _bannerMsg;
  InlineBannerType _bannerType = InlineBannerType.error;
  Duration _bannerDuration = const Duration(seconds: 4);

  void _showBanner(String msg,
      [InlineBannerType type = InlineBannerType.error,
      Duration duration = const Duration(seconds: 4)]) {
    setState(() {
      _bannerMsg = msg;
      _bannerType = type;
      _bannerDuration = duration;
    });
  }

  /// Item 46 — tampilkan banner peringatan stok menipis yang mengantre dari
  /// checkout terakhir, LALU kuras antriannya. Digabung jadi satu banner
  /// (~5 detik) bila lebih dari satu produk. [onlyIfCurrent] dipakai jalur
  /// build/post-frame (rebuild bisa terjadi saat kasir masih tertutup layar
  /// struk) agar banner TIDAK muncul selagi kasir belum jadi rute teratas;
  /// jalur RouteAware (didPush/didPopNext) memanggil tanpa guard karena
  /// keduanya hanya terpicu saat kasir memang sudah jadi rute teratas.
  void _drainLowStockAlerts({bool onlyIfCurrent = false}) {
    if (!mounted || widget.catalogMode) return;
    if (onlyIfCurrent && !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final alerts = ref.read(pendingLowStockAlertsProvider);
    if (alerts.isEmpty) return;
    ref.read(pendingLowStockAlertsProvider.notifier).state = const [];
    _showBanner(alerts.join('\n'), InlineBannerType.warning,
        const Duration(seconds: 5));
  }

  Future<void> _initSwipeHint() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_kSwipeHintCountKey) ?? 0;
    if (mounted && count < 3) setState(() => _swipeHintVisible = true);
  }

  Future<void> _incrementSwipeHint() async {
    if (!_swipeHintVisible) return;
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_kSwipeHintCountKey) ?? 0) + 1;
    await prefs.setInt(_kSwipeHintCountKey, count);
    if (count >= 3 && mounted) setState(() => _swipeHintVisible = false);
  }

  @override
  void initState() {
    super.initState();
    _loadScannerPrefs();
    _initSwipeHint();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Item 46 — berlangganan observer rute agar tahu saat kasir kembali jadi
    // rute teratas (didPopNext) untuk menampilkan banner stok menipis.
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void>) {
      kasirRouteObserver.subscribe(this, route);
    }
  }

  /// Kasir baru pertama kali muncul (mis. buka app langsung di /kasir) —
  /// antrian biasanya kosong; drain aman (no-op bila kosong).
  @override
  void didPush() => _drainLowStockAlerts();

  /// Kembali ke kasir dari layar bayar/struk → tampilkan banner stok menipis.
  @override
  void didPopNext() => _drainLowStockAlerts();

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
      if (code.isEmpty) return false;

      if (code.startsWith(OrderPageService.machineCodePrefix)) {
        _beginOrderCodeMerge(code);
        return true;
      }
      if (_pendingOrderCodeBuffer != null && _looksLikeOrderCodeLine(code)) {
        _continueOrderCodeMerge(code);
        return true;
      }

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

  bool _looksLikeOrderCodeLine(String code) =>
      code.startsWith('Pegawai:') ||
      code.startsWith('Nama:') ||
      code.startsWith('HP:') ||
      code.startsWith('Catatan:');

  void _beginOrderCodeMerge(String firstLine) {
    _orderCodeMergeTimer?.cancel();
    _pendingOrderCodeBuffer = firstLine;
    _scheduleOrderCodeFinalize();
  }

  void _continueOrderCodeMerge(String nextLine) {
    _orderCodeMergeTimer?.cancel();
    _pendingOrderCodeBuffer = '${_pendingOrderCodeBuffer!}\n$nextLine';
    _scheduleOrderCodeFinalize();
  }

  void _scheduleOrderCodeFinalize() {
    _orderCodeMergeTimer = Timer(_kOrderCodeMergeWindow, () {
      final text = _pendingOrderCodeBuffer;
      _pendingOrderCodeBuffer = null;
      if (text != null) _handleBarcode(text, fromExternal: true);
    });
  }

  Future<void> _loadScannerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _continuousScan = prefs.getBool(_prefContinuous) ?? false;
      _toastDurationSeconds = prefs.getInt(_prefToastDuration) ?? 5;
      _tapToScan = prefs.getBool(_prefTapToScan) ?? false;
    });
  }

  Future<void> _setContinuous(bool v) async {
    setState(() => _continuousScan = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefContinuous, v);
  }

  Future<void> _setTapToScan(bool v) async {
    setState(() {
      _tapToScan = v;
      _pendingBarcode = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefTapToScan, v);
  }

  /// Item 24e — proses barcode yang sedang ditampung (tap-to-scan).
  /// Langsung dikosongkan begitu diproses — bidik ditombol lagi TANPA
  /// deteksi baru (mis. kamera diarahkan ke tempat kosong) TIDAK boleh
  /// mengulang barang yang sama; harus ada barcode terdeteksi FRESH dulu.
  void _confirmPendingScan() {
    final code = _pendingBarcode;
    if (code == null) return;
    setState(() => _pendingBarcode = null);
    _lastConfirmedBarcode = code;
    _lastConfirmedAt = DateTime.now();
    _handleBarcode(code);
  }

  Future<void> _setToastDuration(int s) async {
    setState(() => _toastDurationSeconds = s);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefToastDuration, s);
  }

  @override
  void dispose() {
    kasirRouteObserver.unsubscribe(this);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _activeToast?.timer?.cancel();
    _scannerCtrl?.dispose();
    _scanPulseController.dispose();
    _orderCodeMergeTimer?.cancel();
    super.dispose();
  }

  void _openScanner() {
    setState(() {
      _scannerOpen = true;
      _torchOn = false;
      _pendingBarcode = null;
      _lastConfirmedBarcode = null;
      _lastConfirmedAt = null;
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
      _pendingBarcode = null;
      _lastConfirmedBarcode = null;
      _lastConfirmedAt = null;
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
    final hasParent = cart
        .any((c) => c.productId == variantItem.parentProductId && !c.isVariant);
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

  Future<void> _handleBarcode(String barcode,
      {bool fromExternal = false}) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Debounce lebih pendek untuk scanner eksternal (150 ms — diturunkan
    // dari 300ms krn user lapor scan dobel cepat yg disengaja/qty 2 ikut
    // ke-drop; 300ms terlalu lama utk scanner yg cukup cepat) agar scan
    // berturut produk sama tetap responsif TAPI masih ada jaring anti-echo
    // hardware. TIDAK bisa diverifikasi otomatis di sini (perilaku echo
    // scanner sungguhan tidak bisa disimulasikan widget test) — WAJIB
    // dicoba manual di device asli dgn scanner fisik sebelum dianggap
    // beres (lihat PLAN.md Item 32).
    // Kamera tetap 1.5 s karena barcode bisa terus terdeteksi selama terlihat.
    final debounceMs = fromExternal ? 150 : 1500;
    if (barcode == _lastScan && nowMs - _lastScanMs < debounceMs) return;
    _lastScan = barcode;
    _lastScanMs = nowMs;

    // Item 24d — kode pesanan (#PSN:), BUKAN barcode produk biasa. Dua jenis:
    // handoff pegawai (baris "Pegawai:") → antrian held_orders; pesanan
    // pelanggan biasa → buka "Tempel Pesanan" pra-diisi (perilaku lama,
    // sebelumnya cuma bisa tempel manual).
    if (barcode.startsWith(OrderPageService.machineCodePrefix)) {
      await _handleOrderCode(barcode);
      return;
    }

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
      _openCartSheet(scrollToBottom: true);
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
    _scanPulseController.pulse();
    // Toast menampilkan & memanipulasi qty EFEKTIF (tombol ± toast memanggil
    // setEffectiveQty). Kalau pakai stored qty, produk induk yang keranjangnya
    // sudah berisi varian akan melompat sebesar total varian saat ± ditekan.
    CartItem? inCart;
    for (final c in ref.read(cartProvider(_cartId))) {
      if (c.productUnitId == item.productUnitId) {
        inCart = c;
        break;
      }
    }
    final newQty = inCart == null ? 0.0 : notifier.effectiveQtyFor(inCart);
    _showOrUpdateToast(item, newQty);
  }

  /// Item 24d — proses kode `#PSN:` hasil scan (kamera ATAU scanner
  /// eksternal — keduanya bermuara ke sini lewat `_handleBarcode`).
  /// Dua alur: `employeeName` terisi → handoff pegawai, masuk antrian
  /// `held_orders` LOKAL device ini (owner/asisten yang scan), TIDAK
  /// langsung ke keranjang aktif (supaya tidak bentrok kalau device ini
  /// sedang melayani transaksi lain). `employeeName` null → pesanan
  /// pelanggan biasa, buka "Tempel Pesanan" pra-diisi (preview & konfirmasi
  /// seperti alur tempel manual yang sudah ada, tidak berubah).
  Future<void> _handleOrderCode(String text) async {
    final db = ref.read(databaseProvider);
    final parsed = await OrderParserService.parse(db: db, text: text);
    if (!mounted) return;

    if (!parsed.hasMachineCode || parsed.items.isEmpty) {
      if (_scannerOpen) _closeScanner();
      _showBanner('Kode pesanan tidak valid / tidak ada barang dikenali');
      return;
    }

    final employeeName = parsed.employeeName;
    if (employeeName != null) {
      // Item 24d/24b susulan — pelanggan (bila pegawai/owner/asisten
      // pengirim sempat memilih di keranjangnya) ikut lewat baris "Nama:"
      // yang sama dgn Tempel Pesanan (lihat `encodeHandoff`). Item 4/57 —
      // `customerId` (kalau ada & tervalidasi ada lokal, lihat
      // `OrderParserService.parse`) ikut disertakan supaya penerima TIDAK
      // perlu ubah dari "Umum" lalu pilih manual lagi. `label` kartu
      // antrian jadi nama PELANGGAN (bukan nama pengirim — pengirim
      // ditampilkan lewat tab terpisah di `_HeldCard`, lihat `employeeName`
      // di payload).
      final customerName = parsed.customerName;
      final meta = (customerName != null && customerName.isNotEmpty)
          ? CartMeta(
              customerId: parsed.customerId,
              customerName: customerName,
              reservedLocalId: parsed.reservedLocalId,
            )
          : CartMeta(reservedLocalId: parsed.reservedLocalId);
      final payload = jsonEncode({
        'items': parsed.items.map((i) => i.toCartItem().toJson()).toList(),
        'meta': meta.toJson(),
        'awaitingPayment': true,
        'employeeName': employeeName,
      });
      await db.holdOrder(
        id: _kasirUuid.v4(),
        label: (customerName != null && customerName.isNotEmpty)
            ? customerName
            : 'Tanpa Nama',
        cartJson: payload,
      );
      if (!mounted) return;
      if (_scannerOpen) _closeScanner();
      _showBanner(
          'Pesanan dari $employeeName masuk antrian', InlineBannerType.success);
      return;
    }

    if (_scannerOpen) _closeScanner();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => PasteOrderSheet(cartId: _cartId, initialText: text),
    );
  }

  /// Buka sheet keranjang. Bila sudah terbuka, isi diperbarui otomatis lewat
  /// provider — tidak membuka sheet kedua.
  ///
  /// Saat pengguna mengetuk item di keranjang, sheet ditutup dan mengembalikan
  /// id produk yang akan diedit. Modal entri item lalu dibuka langsung di atas
  /// layar kasir (bukan bertumpuk di atas DraggableScrollableSheet keranjang,
  /// yang memutus koneksi input keyboard pada field harga). Setelah selesai,
  /// keranjang dibuka kembali agar pengguna tetap dalam alur.
  Future<void> _openCartSheet({bool scrollToBottom = false}) async {
    if (_cartSheetOpen) return;
    _cartSheetOpen = true;
    final payRoute =
        _isAddMode ? '/kasir/tambah/${widget.addToTxId}/bayar' : '/kasir/bayar';
    final editProductId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CartSheet(
        cartId: _cartId,
        scrollToBottom: scrollToBottom,
        payRoute: payRoute,
      ),
    );
    _cartSheetOpen = false;
    if (editProductId == null || !mounted) return;

    final product =
        await ref.read(databaseProvider).getProductById(editProductId);
    if (product == null || !mounted) return;
    final navigatedAway = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ItemEntrySheet(product: product, cartId: _cartId),
    );
    // Buka lagi keranjang setelah edit, selama masih ada isinya — TAPI jangan
    // kalau ItemEntrySheet ditutup karena navigasi ke layar lain (mis. tombol
    // "Edit produk" → ProdukFormScreen, pop dengan `true`): membuka sheet
    // lagi di situ akan menumpuk di belakang layar baru & membuat
    // `_onHardwareKey` salah kira sheet keranjang masih aktif (menelan input
    // digit yang seharusnya masuk ke field di layar baru itu).
    if (navigatedAway == true) return;
    if (mounted && ref.read(cartProvider(_cartId)).isNotEmpty) _openCartSheet();
  }

  void _showOrUpdateToast(CartItem item, double qty) {
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

  Future<void> _openEntry(Product product) async {
    // Modal (route baru) mengambil alih fokus dari field cari secara alami
    // lewat mekanisme FocusScope Flutter sendiri — beda dari tap "+" biasa
    // yang cuma lewat Listener kita (lihat `_skipNextSearchCollapse`).
    // `_searchForceExpanded` menahan kolom cari tetap lebar SELAMA modal
    // terbuka, lalu fokus dikembalikan setelah modal ditutup.
    final wasSearchActive =
        _searchFocus.hasFocus && _searchCtrl.text.isNotEmpty;
    if (wasSearchActive) setState(() => _searchForceExpanded = true);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ItemEntrySheet(product: product, cartId: _cartId),
    );
    if (wasSearchActive && mounted) {
      setState(() => _searchForceExpanded = false);
      _searchFocus.requestFocus();
    }
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
              onPressed: () => Navigator.of(ctx)
                  .pop(ctrl.text.trim().isEmpty ? 'Pesanan' : ctrl.text.trim()),
              child: const Text('Tahan'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  /// Tap kartu antrian (ditahan biasa maupun handoff pegawai via QR) —
  /// langsung resume ke keranjang, tanpa sheet verifikasi centang (fitur
  /// itu dihapus: pengirim sudah menyusun barangnya sendiri, tidak perlu
  /// dicek ulang lagi oleh penerima sebelum lanjut bayar).
  void _onHeldCardTap(HeldOrder order) => _resumeHeld(order);

  Future<void> _resumeHeld(HeldOrder order) async {
    final parsed = _parseHeldPayload(order.cartJson);
    if (parsed.items.isEmpty) {
      _showBanner('Data pesanan rusak — tidak ada item yang bisa dipulihkan');
      return;
    }
    // Item 18: keranjang aktif TIDAK dibuang saat beralih — otomatis ditahan
    // balik (tanpa dialog, tanpa kehilangan) supaya kasir bisa lompat antar
    // pesanan cepat di jam sibuk.
    final autoHeldLabel = await _autoHoldCurrentIfAny();
    if (!mounted) return;
    await ref.read(databaseProvider).deleteHeldOrder(order.id);
    ref.read(cartProvider(_cartId).notifier).replaceAll(parsed.items);
    ref.read(cartMetaProvider(_cartId).notifier).replaceAll(parsed.meta);
    if (mounted) {
      setState(() => _heldPanelOpen = false);
      _showBanner(
          autoHeldLabel != null
              ? 'Pesanan "$autoHeldLabel" ditahan · lanjut: ${order.label}'
              : 'Melanjutkan pesanan: ${order.label}',
          InlineBannerType.success);
    }
  }

  /// Tahan keranjang aktif secara OTOMATIS (tanpa dialog label) sebelum
  /// beralih ke pesanan lain. Label: nama pelanggan bila ada, selain itu
  /// dibuat otomatis dari jam (nol-friksi). Mengembalikan label yang dipakai,
  /// atau null bila keranjang kosong (tidak ada yang perlu disimpan).
  Future<String?> _autoHoldCurrentIfAny() async {
    final cart = ref.read(cartProvider(_cartId));
    if (cart.isEmpty) return null;
    final meta = ref.read(cartMetaProvider(_cartId));
    final label = meta.hasCustomer ? meta.customerName! : _autoHoldLabel();
    final payload = jsonEncode({
      'items': cart.map((c) => c.toJson()).toList(),
      'meta': meta.toJson(),
    });
    await ref
        .read(databaseProvider)
        .holdOrder(id: _kasirUuid.v4(), label: label, cartJson: payload);
    ref.read(cartProvider(_cartId).notifier).clear();
    ref.read(cartMetaProvider(_cartId).notifier).clear();
    return label;
  }

  String _autoHoldLabel() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return 'Tanpa Nama $hh:$mm';
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
    // Item 46 — fallback jalur `context.go('/kasir')` (menutup struk dgn
    // MENGHAPUS halaman, bukan pop → RouteObserver.didPopNext belum tentu
    // terpicu, tapi KasirScreen di-rebuild oleh shell). Tampilkan banner
    // stok menipis via post-frame, HANYA bila kasir sudah jadi rute teratas
    // (guard: rebuild juga terjadi saat provider di-set selagi kasir masih
    // tertutup layar struk). Jalur pop (tombol back HP) ditangani didPopNext.
    // Item 46 — fallback jalur `context.go('/kasir')` (menutup struk dgn
    // MENGHAPUS halaman, bukan pop → RouteObserver.didPopNext belum tentu
    // terpicu, tapi KasirScreen di-rebuild oleh shell). Tampilkan banner
    // stok menipis via post-frame, HANYA bila kasir sudah jadi rute teratas
    // (guard: rebuild juga terjadi saat provider di-set selagi kasir masih
    // tertutup layar struk). Jalur pop (tombol back HP) ditangani didPopNext.
    if (ref.watch(pendingLowStockAlertsProvider).isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _drainLowStockAlerts(onlyIfCurrent: true));
    }
    if (_scannerOpen && _scannerCtrl != null) {
      // Item 24f — kontrol scanner sebagai kapsul-kapsul kecil melayang
      // langsung di frame kamera (gaya kamera bawaan HP, mis. pill zoom
      // "0.6 · 1X · 2"), BUKAN satu panel besar/menu titik-tiga — supaya
      // gampang dijangkau jempol & tidak menutupi area bidik tengah.
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            MobileScanner(
              controller: _scannerCtrl!,
              onDetect: (capture) {
                final barcode = capture.barcodes.firstOrNull?.rawValue;
                if (barcode == null) return;
                if (_tapToScan) {
                  // Frame basi dari SEBELUM barcode disingkirkan (latensi
                  // pipeline kamera) bisa masih melaporkan barcode yang
                  // BARU SAJA dikonfirmasi — abaikan dalam jendela singkat
                  // ini supaya tidak meng-isi ulang _pendingBarcode dgn
                  // barang yang sama (lihat komentar _lastConfirmedBarcode).
                  if (barcode == _lastConfirmedBarcode &&
                      _lastConfirmedAt != null &&
                      DateTime.now().difference(_lastConfirmedAt!) <
                          _kStaleDetectionCooldown) {
                    return;
                  }
                  if (_pendingBarcode != barcode) {
                    setState(() => _pendingBarcode = barcode);
                  }
                } else {
                  _handleBarcode(barcode);
                }
              },
            ),
            // Overlay panduan visual (dekoratif — TIDAK membatasi area deteksi;
            // engine tetap membaca barcode dari seluruh frame).
            Positioned.fill(
              child: IgnorePointer(
                child: _ScanGuideOverlay(controller: _scanPulseController),
              ),
            ),
            SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ScanCapsuleIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Tutup scanner',
                      onTap: _closeScanner,
                    ),
                    _ScanCapsuleIconButton(
                      icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                      tooltip: 'Senter',
                      onTap: _toggleTorch,
                    ),
                  ],
                ),
              ),
            ),
            // Tombol bidik manual (tap-to-scan) — muncul/hilang dgn animasi
            // "plop" halus (scale+fade, sedikit overshoot), TIDAK dipaksakan
            // saat mode auto-continuous supaya tidak membingungkan.
            Positioned(
              left: 0,
              right: 0,
              bottom: 118,
              child: Center(
                child: _ScanShutterButton(
                  key: const Key('scan_shutter_button'),
                  visible: _tapToScan,
                  enabled: _pendingBarcode != null,
                  onTap: _confirmPendingScan,
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ScanModeSegment(
                        continuous: _continuousScan,
                        onChanged: _setContinuous,
                      ),
                      _ScanCapsuleToggle(
                        label: 'Tap to Scan',
                        value: _tapToScan,
                        onChanged: _setTapToScan,
                      ),
                      _ScanDurationCapsule(
                        seconds: _toastDurationSeconds,
                        onTap: () {
                          const options = [3, 5, 10];
                          final i = options.indexOf(_toastDurationSeconds);
                          _setToastDuration(options[(i + 1) % options.length]);
                        },
                      ),
                    ],
                  ),
                ),
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
    // Item 55 — nomor nota (di-reserve `_CartMetaTab`) ditampilkan di cart
    // bar; watch (bukan read) supaya bar ikut update begitu reservasi
    // selesai async tanpa perlu rebuild dari trigger lain.
    final cartMeta = ref.watch(cartMetaProvider(_cartId));
    final query = ref.watch(_kasirSearchProvider(_cartId));
    final isGrid = ref.watch(kasirGridProvider);
    final heldCount = ref.watch(_heldCountProvider).valueOrNull ?? 0;
    final selectedGroup = ref.watch(_kasirSelectedGroupProvider);
    final productsAsync =
        ref.watch(_kasirProductsProvider((query, selectedGroup)));
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _isCatalogMode
          ? AppBar(
              title: Text(ref.watch(catalogEditProvider) != null
                  ? 'Edit Katalog'
                  : 'Buat Katalog'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Tutup',
                onPressed: () => context.pop(),
              ),
            )
          : _isAddMode
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
            forceExpanded: _searchForceExpanded,
            onSearch: (v) =>
                ref.read(_kasirSearchProvider(_cartId).notifier).state = v,
            onScan: _openScanner,
            onHeld: () => setState(() => _heldPanelOpen = !_heldPanelOpen),
            onHistory: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const TxHistorySheet(),
            ),
            // Tempel Pesanan (Katalog Pesanan). Hanya di mode kasir biasa
            // (bukan katalog/tambah-belanjaan) agar tidak menambah
            // kebingungan di alur yang sudah ada.
            onPasteOrder: (!_isCatalogMode && !_isAddMode)
                ? () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => PasteOrderSheet(cartId: _cartId),
                    )
                : null,
            heldCount: heldCount,
            isGrid: isGrid,
            onToggleGrid: () => ref.read(kasirGridProvider.notifier).toggle(),
            // Mode katalog: sembunyikan Antrian & Riwayat agar tak ambigu.
            showQueueAndHistory: !_isCatalogMode,
          ),
          const _KasirCategoryChipRow(),
          Expanded(
            // Tap atau scroll di mana pun di bawah topbar keluar dari state
            // input pencarian (fokus hilang → kolom shrink lewat listener di
            // _KasirTopbar), TANPA menghapus teks yang sudah diketik.
            // Listener (bukan GestureDetector) agar tap tetap diteruskan
            // normal ke kartu produk/tombol di bawahnya, tidak "dicuri".
            // Pengecualian: tap "+" / badan kartu produk (buka modal pilih
            // harga dll.) SAAT field cari sedang expanded & berisi teks TIDAK
            // mengecilkan/keluar dari field — lihat `_markSkipSearchCollapse`.
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                if (_skipNextSearchCollapse) {
                  _skipNextSearchCollapse = false;
                  return;
                }
                _searchFocus.unfocus();
                // Tap/swipe di LUAR wadah panel pesanan ditahan → tutup
                // panelnya saja (AnimatedSize yang membungkusnya di bawah
                // sudah kasih animasi smooth), tanpa mengganggu tap DI DALAM
                // panel (mis. tap kartu antrian, tombol X, scroll strip-nya).
                if (_heldPanelOpen) {
                  final box = _heldPanelKey.currentContext?.findRenderObject()
                      as RenderBox?;
                  final local = box?.globalToLocal(event.position);
                  final insidePanel = box != null &&
                      local != null &&
                      (Offset.zero & box.size).contains(local);
                  if (!insidePanel) {
                    setState(() => _heldPanelOpen = false);
                  }
                }
              },
              child: NotificationListener<ScrollStartNotification>(
                onNotification: (_) {
                  _searchFocus.unfocus();
                  return false;
                },
                child: Column(
                  children: [
                    const SyncStatusBanner(),
                    InlineBanner(
                      message: _bannerMsg,
                      type: _bannerType,
                      duration: _bannerDuration,
                      onDismiss: () => setState(() => _bannerMsg = null),
                    ),
                    // Panel pesanan ditahan — slide inline dari atas (mendorong
                    // katalog ke bawah, bukan overlay modal).
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _heldPanelOpen
                          ? _HeldInlinePanel(
                              key: _heldPanelKey,
                              onResume: _onHeldCardTap,
                              onClose: () =>
                                  setState(() => _heldPanelOpen = false),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    Expanded(
                      child: StepperActiveScope(
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
                                  onBeforeTap: _markSkipSearchCollapse,
                                ),
                              );
                            }
                            return ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: prods.length,
                              separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  indent: 62,
                                  color: cs.outlineVariant),
                              itemBuilder: (_, i) => _ProductListTile(
                                product: prods[i],
                                cartId: _cartId,
                                onTapBody: () => _openEntry(prods[i]),
                                onQuickAdd: _quickAdd,
                                onOpenEntry: () => _openEntry(prods[i]),
                                onBeforeTap: _markSkipSearchCollapse,
                              ),
                            );
                          },
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(child: Text('Error: $e')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _isCatalogMode
              ? _CatalogBar(
                  count: cart.length,
                  lastItem: cartNotifier.lastTouchedItem,
                  onView: _openCatalogItemsSheet,
                  onSave: _saveCatalog,
                  onShare: _shareCatalog,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tab folder pelanggan & pegawai + tombol tahan — hanya di
                    // mode kasir biasa (tambah belanjaan ikut transaksi asli).
                    if (!_isAddMode)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _CartMetaTab(
                          cartId: _cartId,
                          onHold: _holdCurrent,
                          // `_isAddMode` sudah dipastikan false oleh guard
                          // `if (!_isAddMode)` di atas — rute bayar SELALU
                          // `/kasir/bayar` di sini (mode tambah belanjaan
                          // punya rute sendiri & TIDAK menampilkan tab ini).
                          onBayar: () => context.push('/kasir/bayar'),
                        ),
                      ),
                    // Geser ke atas untuk membuka sheet keranjang.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragEnd: (d) {
                        if (d.velocity.pixelsPerSecond.dy < -300) {
                          _incrementSwipeHint().ignore();
                          _openCartSheet();
                        }
                      },
                      child: _CartBar(
                        total: cartNotifier.totalAmount,
                        count: cart.length,
                        lastItem:
                            _isAddMode ? null : cartNotifier.lastTouchedItem,
                        lastEffQty: cartNotifier.lastTouchedItem == null
                            ? 0
                            : cartNotifier
                                .effectiveQtyFor(cartNotifier.lastTouchedItem!),
                        showSwipeHint: _swipeHintVisible,
                        orderNumber:
                            _isAddMode ? null : cartMeta.displayOrderNumber,
                      ),
                    ),
                  ],
                ),
    );
  }

  // ── Mode katalog: aksi simpan, bagikan, dan tinjau item ──────────────────

  Future<void> _shareCatalog() async {
    final items = ref.read(cartProvider(_cartId));
    if (items.isEmpty) return;
    final lines = await buildCatalogLines(ref, items);
    if (!mounted) return;
    await showCatalogPreviewSheet(context, ref,
        title: _catalogTitle, lines: lines);
  }

  /// Judul default: judul katalog yang sedang diedit, atau 'Daftar Harga'.
  String get _catalogTitle =>
      ref.read(catalogEditProvider)?.title ?? 'Daftar Harga';

  Future<void> _saveCatalog() async {
    final items = ref.read(cartProvider(_cartId));
    if (items.isEmpty) return;
    final editing = ref.read(catalogEditProvider);
    final titleCtrl = TextEditingController(text: _catalogTitle);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(editing == null ? 'Simpan Katalog' : 'Simpan Perubahan'),
        content: TextField(
          controller: titleCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Judul katalog',
            hintText: 'mis. Update Harga Juni',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    final title = titleCtrl.text.trim();
    titleCtrl.dispose();
    if (ok != true || !mounted) return;

    final lines = await buildCatalogLines(ref, items);
    final store = ref.read(catalogStoreProvider.notifier);
    if (editing != null) {
      // Perbarui katalog yang sama (pertahankan id & waktu dibuat).
      await store.update(SavedCatalog(
        id: editing.id,
        title: title.isEmpty ? editing.title : title,
        createdAtMs: editing.createdAtMs,
        lines: lines,
      ));
    } else {
      await store.add(SavedCatalog(
        id: 'cat-${DateTime.now().millisecondsSinceEpoch}',
        title: title.isEmpty ? 'Daftar Harga' : title,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        lines: lines,
      ));
    }
    // Bersihkan keranjang & konteks edit, lalu kembali ke daftar katalog.
    ref.read(cartProvider(_cartId).notifier).clear();
    ref.read(catalogEditProvider.notifier).state = null;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(editing == null
            ? 'Katalog disimpan'
            : 'Perubahan katalog disimpan')));
    context.pop();
  }

  Future<void> _openCatalogItemsSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CatalogItemsSheet(cartId: _cartId),
    );
  }
}

// ─── Topbar ──────────────────────────────────────────────────────────────────

/// Durasi & kurva animasi expand/collapse kolom cari — dipakai bersama oleh
/// field pencarian (lebar) dan tombol-tombol di sampingnya (opacity) supaya
/// keduanya terasa satu gerakan (field "menimpa" tombol), bukan dua animasi
/// terpisah yang kebetulan searah.
const _kSearchAnimDuration = Duration(milliseconds: 260);
const _kSearchAnimCurve = Curves.easeOutCubic;

/// Jarak antar tombol topbar (scan↔antrian↔riwayat↔dst) — dipakai juga
/// sebagai jarak field cari↔tombol scan saat collapsed, supaya "rapi"
/// (jaraknya konsisten, bukan menimpa tombol scan).
const _kTbGap = 4.0;

/// Item 54 — chip kategori tab Kasir: tombol kecil di bawah topbar, tap
/// untuk filter (single-select — union kategori utama + tag tambahan,
/// lihat [AppDatabase.watchProductsForKasir]), hold+drag untuk reorder
/// (tersimpan ke `sortOrder` via [AppDatabase.reorderProductGroups]).
/// Kosong total (tidak ada kategori bernama) → tidak render apa pun.
class _KasirCategoryChipRow extends ConsumerWidget {
  const _KasirCategoryChipRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(_kasirGroupsProvider);
    final groups = groupsAsync.valueOrNull ?? const <ProductGroup>[];
    if (groups.isEmpty) return const SizedBox.shrink();
    final selected = ref.watch(_kasirSelectedGroupProvider);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 40,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        onReorder: (oldIndex, newIndex) {
          final ids = groups.map((g) => g.id).toList();
          if (newIndex > oldIndex) newIndex--;
          final moved = ids.removeAt(oldIndex);
          ids.insert(newIndex, moved);
          ref.read(databaseProvider).reorderProductGroups(ids);
        },
        children: [
          for (var i = 0; i < groups.length; i++)
            // Delayed (hold-then-drag), bukan drag-langsung — supaya tap
            // singkat biasa tetap terdeteksi FilterChip.onSelected (drag
            // langsung akan "mencuri" gestur tap chip).
            ReorderableDelayedDragStartListener(
              key: ValueKey(groups[i].id),
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(groups[i].name!,
                      style: const TextStyle(fontSize: 12)),
                  selected: selected == groups[i].id,
                  onSelected: (_) => ref
                      .read(_kasirSelectedGroupProvider.notifier)
                      .state = selected == groups[i].id ? null : groups[i].id,
                  visualDensity: VisualDensity.compact,
                  selectedColor: scheme.primaryContainer,
                  checkmarkColor: scheme.onPrimaryContainer,
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _KasirTopbar extends StatefulWidget {
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
    this.showQueueAndHistory = true,
    this.onPasteOrder,
    this.forceExpanded = false,
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

  /// Tampilkan tombol Antrian (tahan) & Riwayat. Disembunyikan di mode katalog.
  final bool showQueueAndHistory;

  /// Buka sheet "Tempel Pesanan". null = sembunyikan tombol (mode katalog /
  /// tambah belanjaan).
  final VoidCallback? onPasteOrder;

  /// true = tetap tampil expanded walau `searchFocus` kehilangan fokus asli
  /// (dipakai saat modal ItemEntrySheet mengambil alih fokus dari route
  /// baru) — lihat `_KasirScreenState._openEntry`.
  final bool forceExpanded;

  @override
  State<_KasirTopbar> createState() => _KasirTopbarState();
}

class _KasirTopbarState extends State<_KasirTopbar> {
  /// Mengikuti `searchFocus.hasFocus` — begitu field disentuh (dapat fokus)
  /// kolom melebar; begitu fokus hilang (tap/scroll di luar, atau tombol x
  /// saat kosong) kolom mengecil lagi. Teks yang sudah diketik TIDAK ikut
  /// hilang saat collapse — hanya lebar visual yang berubah.
  late bool _expanded = widget.searchFocus.hasFocus;

  @override
  void initState() {
    super.initState();
    widget.searchFocus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.searchFocus.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    // Saat field cari dapat fokus ulang & sudah ada teks lama, select-all
    // seluruh kata — supaya ketik langsung menimpa (cari produk berikutnya
    // tanpa harus jangkau tombol x dulu), atau geser cursor untuk koreksi.
    // Post-frame: TextField default menaruh cursor di ujung saat fokus, jadi
    // selection kita harus dipasang SETELAH itu agar tidak ditimpa.
    if (widget.searchFocus.hasFocus && widget.searchCtrl.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.searchFocus.hasFocus) return;
        final len = widget.searchCtrl.text.length;
        if (len == 0) return;
        widget.searchCtrl.selection =
            TextSelection(baseOffset: 0, extentOffset: len);
      });
    }
    if (widget.searchFocus.hasFocus != _expanded) {
      setState(() => _expanded = widget.searchFocus.hasFocus);
    }
  }

  /// Status expanded yang benar-benar dipakai untuk render — gabungan fokus
  /// asli field DAN `forceExpanded` (dipertahankan manual saat modal
  /// mengambil fokus). Field `_expanded` sendiri tetap murni mengikuti fokus
  /// asli (dipakai `didUpdateWidget` dkk.), jadi jangan disatukan.
  bool get _visuallyExpanded => _expanded || widget.forceExpanded;

  /// Lebar total baris tombol topbar (scan/antrian/riwayat/grid/tempel
  /// pesanan) — dihitung persis dari ukuran `_TbBtn` (36px ikon-saja, 44px
  /// yang punya label) + jarak antar-tombol, BUKAN ditaksir/hardcode. Field
  /// cari collapsed harus berhenti tepat di sini + 1 jarak tombol supaya
  /// tidak pernah menimpa tombol scan meski daftar tombol berubah per mode
  /// (mis. mode katalog menyembunyikan Antrian & Riwayat).
  double get _buttonRowWidth {
    final widths = <double>[36]; // scan
    if (widget.showQueueAndHistory) {
      widths.addAll([44, 44]); // antrian, riwayat
    }
    widths.add(36); // grid toggle
    if (widget.onPasteOrder != null) {
      widths.add(44); // tempel pesanan
    }
    final total = widths.fold<double>(0, (a, b) => a + b);
    final gaps = (widths.length - 1) * _kTbGap;
    return total + gaps;
  }

  /// Lebar field cari saat collapsed: sisa ruang setelah baris tombol +
  /// SATU jarak tombol (`_kTbGap`) — persis sama seperti jarak scan↔antrian.
  double _collapsedWidth(double maxW) =>
      (maxW - _buttonRowWidth - _kTbGap).clamp(44.0, maxW);

  /// Tombol x di ujung kanan field (hanya tampil saat expanded): kosong →
  /// shrink (unfocus, teks tetap seperti apa adanya/kosong); ada isi →
  /// hapus semua karakter TAPI tetap expanded (tidak shrink).
  void _onClearOrShrink() {
    if (widget.searchCtrl.text.isEmpty) {
      widget.searchFocus.unfocus();
    } else {
      widget.searchCtrl.clear();
      widget.onSearch('');
    }
  }

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
            // Bottom diperbesar (10 -> 16) supaya label 2 baris di bawah
            // tombol (mis. "Riwayat Transaksi") tidak menyentuh/terpotong
            // oleh divider di bawahnya — beri sedikit napas.
            padding: EdgeInsets.fromLTRB(12, topPadding + 8, 12, 16),
            child: Row(
              // Sejajarkan kotak ikon di atas; keterangan menggantung di bawah
              // tanpa menggeser tombol lain (tetap rapi di HP & tablet).
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxW = constraints.maxWidth;
                      return SizedBox(
                        // 56 (bukan 44) — cukup untuk kotak ikon 36px + label
                        // 2 baris di bawahnya (mis. "Riwayat Transaksi") tanpa
                        // terpotong. clipBehavior none tetap dipasang sebagai
                        // jaring pengaman tambahan.
                        height: 56,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Baris tombol — di belakang, faded + non-tappable
                            // saat kolom cari melebar "menimpa" nya.
                            Positioned(
                              right: 0,
                              top: 0,
                              child: AnimatedOpacity(
                                duration: _kSearchAnimDuration,
                                curve: _kSearchAnimCurve,
                                opacity: _visuallyExpanded ? 0 : 1,
                                child: IgnorePointer(
                                  ignoring: _visuallyExpanded,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _TbBtn(
                                          icon: Icons.qr_code_scanner_rounded,
                                          onTap: widget.onScan,
                                          fg: AppTheme.scanFg,
                                          bg: AppTheme.scanBg),
                                      if (widget.showQueueAndHistory) ...[
                                        const SizedBox(width: 4),
                                        _TbBtn(
                                          icon: Icons
                                              .pause_circle_outline_rounded,
                                          onTap: widget.onHeld,
                                          badgeCount: widget.heldCount,
                                          label: 'Antrian',
                                          fg: AppTheme.antrianFg,
                                          bg: AppTheme.antrianBg,
                                        ),
                                        const SizedBox(width: 4),
                                        _TbBtn(
                                          icon: Icons.history_rounded,
                                          onTap: widget.onHistory,
                                          label: 'Riwayat\nTransaksi',
                                          fg: AppTheme.riwayatFg,
                                          bg: AppTheme.riwayatBg,
                                        ),
                                      ],
                                      const SizedBox(width: 4),
                                      _TbBtn(
                                        icon: widget.isGrid
                                            ? Icons.view_list_rounded
                                            : Icons.grid_view_rounded,
                                        onTap: widget.onToggleGrid,
                                      ),
                                      if (widget.onPasteOrder != null) ...[
                                        const SizedBox(width: 4),
                                        _TbBtn(
                                          icon: Icons.content_paste_go_rounded,
                                          onTap: widget.onPasteOrder!,
                                          label: 'Tempel\nPesanan',
                                          fg: AppTheme.tempelFg,
                                          bg: AppTheme.tempelBg,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Field cari — di depan, lebar dianimasikan dari
                            // sempit (collapsed) sampai penuh (menimpa tombol).
                            AnimatedPositioned(
                              duration: _kSearchAnimDuration,
                              curve: _kSearchAnimCurve,
                              left: 0,
                              top: 0,
                              height: 44,
                              width: _visuallyExpanded
                                  ? maxW
                                  : _collapsedWidth(maxW),
                              child: Container(
                                // Latar solid (bukan transparan) supaya benar-
                                // benar "menimpa" tombol di belakangnya, bukan
                                // cuma memotong ruang layout-nya.
                                color: cs.surface,
                                child: ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: widget.searchCtrl,
                                  builder: (context, value, _) {
                                    return TextField(
                                      controller: widget.searchCtrl,
                                      focusNode: widget.searchFocus,
                                      decoration: InputDecoration(
                                        hintText: 'Cari produk…',
                                        prefixIcon: const Icon(
                                            Icons.search_rounded,
                                            size: 18),
                                        suffixIcon: _visuallyExpanded
                                            ? IconButton(
                                                icon: const Icon(
                                                    Icons.clear_rounded,
                                                    size: 16),
                                                onPressed: _onClearOrShrink,
                                              )
                                            : null,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        isDense: true,
                                      ),
                                      onChanged: widget.onSearch,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
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
  const _TbBtn({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
    this.label,
    this.fg,
    this.bg,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  /// Keterangan opsional di bawah ikon (mis. 'Antrian'). Boleh berisi '\n'
  /// untuk memaksa dua baris. Lebar dibatasi agar tidak menabrak tombol lain.
  final String? label;

  /// Item 33 — aksen soft per-fungsi (mis. `AppTheme.scanFg`/`scanBg`).
  /// Null = netral (dipakai grid/list toggle, murni preferensi tampilan).
  final Color Function(bool isDark)? fg;
  final Color Function(bool isDark)? bg;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = fg?.call(isDark) ?? cs.onSurfaceVariant;
    final bgColor = bg?.call(isDark) ?? cs.surface;
    final child = Icon(icon, size: 18, color: iconColor);
    final box = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant, width: 0.75),
      ),
      child: badgeCount > 0
          ? Badge(label: Text('$badgeCount'), child: child)
          : child,
    );
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          box,
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 44,
                child: Text(
                  label!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    height: 1.05,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kurangi 1 satuan dasar produk [productId] dari keranjang. Item dihapus bila
/// effective qty turun ke 0. Dipakai oleh tombol minus di kartu & list produk.
///
/// Item 16: bila produk punya >1 baris satuan NON-varian di keranjang (mis.
/// Dus + Pcs), tombol minus TIDAK menebak baris mana yang dikurangi — beri
/// info & arahkan atur lewat keranjang. Kasus umum (1 satuan) tetap langsung.
void _decrementProduct(BuildContext context, List<CartItem> cart,
    CartNotifier notifier, String productId) {
  final unitLines =
      cart.where((c) => c.productId == productId && !c.isVariant).toList();
  if (unitLines.isEmpty) return;
  if (unitLines.length > 1) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Produk ini punya beberapa satuan di keranjang — '
            'atur jumlahnya lewat keranjang.'),
      ));
    return;
  }
  final item = unitLines.first;
  final eff = notifier.effectiveQtyFor(item);
  if (eff <= 1) {
    notifier.removeItem(item.productUnitId);
  } else {
    notifier.setEffectiveQty(item.productUnitId, eff - 1);
  }
}

// ─── Add / counter control ────────────────────────────────────────────────────

// ─── Product grid card ────────────────────────────────────────────────────────

class _ProductCard extends ConsumerWidget {
  const _ProductCard({
    required this.product,
    required this.cartId,
    required this.onTapBody,
    required this.onQuickAdd,
    required this.onOpenEntry,
    this.onBeforeTap,
  });

  final Product product;
  final String cartId;
  final VoidCallback onTapBody;
  final void Function(Product, CatalogDetail) onQuickAdd;
  final VoidCallback onOpenEntry;

  /// Dipanggil tepat sebelum tap (badan kartu ATAU tombol "+") diproses —
  /// dipakai layar kasir untuk menahan field cari agar tidak mengecil bila
  /// sedang expanded & berisi teks. Lihat `_markSkipSearchCollapse`.
  final VoidCallback? onBeforeTap;

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

    return Listener(
      onPointerDown: onBeforeTap == null ? null : (_) => onBeforeTap!(),
      behavior: HitTestBehavior.translucent,
      child: Material(
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
                  // Item 25a — kosmetik saja (warnai nama, tidak nonaktifkan
                  // "+"; itu wewenang izin "Izinkan Stok Minus"). Pakai warna
                  // nama (bukan badge terpisah) supaya tidak menambah lebar/
                  // tinggi baris & memicu overflow di kartu grid yang sempit.
                  product.markedOutOfStock
                      ? '${product.name} · Habis'
                      : product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: product.markedOutOfStock ? cs.error : null,
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
                      data: (d) => AddControl(
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
                                context, cart, notifier, product.id)
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
    this.onBeforeTap,
  });

  final Product product;
  final String cartId;
  final VoidCallback onTapBody;
  final void Function(Product, CatalogDetail) onQuickAdd;
  final VoidCallback onOpenEntry;

  /// Dipanggil tepat sebelum tap (badan tile, tombol "+", atau baris varian
  /// di dropdown inline) diproses — dipakai layar kasir untuk menahan field
  /// cari agar tidak mengecil bila sedang expanded & berisi teks.
  final VoidCallback? onBeforeTap;

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
    final hasVariants =
        detailAsync.maybeWhen(data: (d) => d.hasVariants, orElse: () => false);

    return Listener(
      onPointerDown:
          widget.onBeforeTap == null ? null : (_) => widget.onBeforeTap!(),
      behavior: HitTestBehavior.translucent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.onTapBody,
            // Tahan item dengan varian → buka/tutup dropdown varian inline.
            onLongPress: hasVariants
                ? () => setState(() => _expanded = !_expanded)
                : null,
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
                            if (product.markedOutOfStock) ...[
                              const SizedBox(width: 6),
                              // Item 25a — kosmetik saja, tidak menonaktifkan
                              // tombol +/- (itu wewenang izin stok minus).
                              Text('Habis',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: cs.error)),
                            ],
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
                    data: (d) => AddControl(
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
                          ? () => _decrementProduct(
                              context, cart, notifier, product.id)
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
      ),
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
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
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
                        return AddControl(
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
    this.lastItem,
    this.lastEffQty = 0,
    this.showSwipeHint = false,
    this.orderNumber,
  });

  final int total;
  final int count;

  /// Item 55 — segmen terakhir nomor nota (mis. "17"), null selama belum
  /// direservasi (keranjang baru saja mulai diisi) atau mode tambah
  /// belanjaan (memakai nomor nota transaksi ASLI, ditampilkan di struk,
  /// bukan di sini).
  final String? orderNumber;

  /// Produk terakhir yang ditambahkan/disentuh — ditampilkan ringkas di bawah
  /// total. null bila tidak relevan (mis. mode tambah belanjaan).
  final CartItem? lastItem;
  final double lastEffQty;
  final bool showSwipeHint;

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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Total diperbesar & di-center, dengan badge jumlah item di kiri.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ItemCountBadge(count: count),
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
              if (showSwipeHint) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.keyboard_arrow_up_rounded,
                        size: 14, color: cs.onSurfaceVariant.withOpacity(0.5)),
                    const SizedBox(width: 3),
                    Text(
                      'Geser ke atas untuk lihat keranjang',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant.withOpacity(0.5)),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (orderNumber != null)
            Positioned(
              top: -2,
              right: 0,
              child: Text('#$orderNumber',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

// ─── Cart bar mode katalog ─────────────────────────────────────────────────

/// Pengganti [_CartBar] saat mode katalog: menampilkan jumlah produk & item
/// terakhir, dengan aksi Lihat / Simpan / Bagikan (bukan Bayar).
class _CatalogBar extends StatelessWidget {
  const _CatalogBar({
    required this.count,
    required this.onView,
    required this.onSave,
    required this.onShare,
    this.lastItem,
  });

  final int count;
  final VoidCallback onView;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final CartItem? lastItem;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final last = lastItem;
    final lastLabel = last == null
        ? null
        : '${last.productName}'
            '${last.unitName.isEmpty ? '' : ' · ${last.unitName}'}'
            ' · ${formatRupiah(last.price)}';

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('$count',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Katalog · $count produk',
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                    if (lastLabel != null)
                      Text(
                        lastLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onView,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: cs.outlineVariant),
                    foregroundColor: cs.onSurface,
                  ),
                  child: const Text('Lihat',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onSave,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: cs.outlineVariant),
                    foregroundColor: cs.onSurface,
                  ),
                  child: const Text('Simpan',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onShare,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Bagikan',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sheet tinjau item katalog — daftar produk yang akan masuk katalog, dengan
/// opsi hapus per item. Tanpa tombol bayar (beda dari keranjang transaksi).
class _CatalogItemsSheet extends ConsumerWidget {
  const _CatalogItemsSheet({required this.cartId});
  final String cartId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider(cartId));
    final notifier = ref.read(cartProvider(cartId).notifier);
    final cs = Theme.of(context).colorScheme;
    final ordered = orderCartItems(cart);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Item Katalog',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${cart.length} produk',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Text('Belum ada produk',
                        style: TextStyle(color: cs.onSurfaceVariant)))
                : ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: ordered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16),
                    itemBuilder: (_, i) {
                      final item = ordered[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.only(
                            left: item.isVariant ? 30 : 16, right: 8),
                        leading: item.isVariant
                            ? Icon(Icons.subdirectory_arrow_right,
                                size: 16, color: cs.onSurfaceVariant)
                            : null,
                        title: Text(item.productName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          item.unitName,
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(formatRupiah(item.price),
                                style: TextStyle(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Hapus',
                              onPressed: () =>
                                  notifier.removeItem(item.productUnitId),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
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
  const _CartMetaTab(
      {required this.cartId, required this.onHold, required this.onBayar});

  final String cartId;
  final VoidCallback onHold;
  final VoidCallback onBayar;

  /// Item 55 — reserve nomor nota SEKALI begitu tab ini pertama kali
  /// terlihat dgn keranjang berisi (tab cuma dirender saat cart non-kosong,
  /// lihat `bottomNavigationBar: cart.isEmpty ? null : ...` di parent).
  /// `ensureReservedLocalId` sendiri no-op kalau sudah punya nomor/sedang
  /// reserve, aman dipanggil ulang tiap build.
  void _ensureReserved(WidgetRef ref) {
    final device = ref.read(deviceProvider);
    final db = ref.read(databaseProvider);
    ref
        .read(cartMetaProvider(cartId).notifier)
        .ensureReservedLocalId(() => db.reserveLocalId(device.deviceCode));
  }

  Future<void> _pickCustomer(BuildContext context, WidgetRef ref) async {
    final meta = ref.read(cartMetaProvider(cartId));
    final pick = await showCustomerPickerSheet(context, ref,
        currentName: meta.customerName);
    if (pick == null) return;
    ref.read(cartMetaProvider(cartId).notifier).setCustomer(pick.id, pick.name);
  }

  Future<void> _pickEmployee(BuildContext context, WidgetRef ref) async {
    final meta = ref.read(cartMetaProvider(cartId));
    final pick =
        await showEmployeePickerSheet(context, ref, currentId: meta.employeeId);
    if (pick == null) return;
    ref.read(cartMetaProvider(cartId).notifier).setEmployee(pick.id, pick.name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final meta = ref.watch(cartMetaProvider(cartId));
    final notifier = ref.read(cartMetaProvider(cartId).notifier);
    // Item 56 — pegawai TANPA izin `terima_pembayaran` tidak dapat segmen
    // Bayar sama sekali (tombol utamanya di cart sheet sudah jadi "Kirim ke
    // Owner/Asisten" — lihat cart_sheet.dart). Owner/asisten/pegawai
    // berizin selalu dapat.
    final needsGate = ref.watch(needsPaymentGateProvider).valueOrNull ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureReserved(ref));
    const slant = 14.0;

    return Transform.translate(
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
          padding: const EdgeInsets.fromLTRB(slant + 10, 7, slant, 8),
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
              // Item 56 — segmen "Bayar" terracotta, menempel setelah Tahan
              // (Varian A) — tap langsung ke layar bayar (`/kasir/bayar`),
              // TANPA lewat sheet keranjang dulu (checkout cepat).
              if (!needsGate) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: onBayar,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.payments_outlined,
                            size: 16, color: Colors.white),
                        SizedBox(width: 4),
                        Text('Bayar',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
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
                  child:
                      Icon(Icons.close, size: 14, color: cs.onSurfaceVariant),
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
  const _HeldInlinePanel(
      {super.key, required this.onResume, required this.onClose});

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
                  child:
                      Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
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
                // Redesign kartu antrian — chip status di baris atas
                // (dalam kartu, bukan tab lipat terpisah) bikin semua kartu
                // sama tinggi tanpa Spacer() kosong, jadi lebih pendek dari
                // 152 sebelumnya.
                height: 134,
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

/// Redesign kartu antrian — satu bentuk kartu utk pesanan ditahan biasa
/// maupun handoff pegawai (Item 24d), beda status lewat WARNA chip di baris
/// atas (dalam kartu), bukan tab lipat + badge merah terpisah seperti
/// sebelumnya. Chip terracotta (`AppTheme.accent`) berisi nama pegawai
/// pengirim + jam masuk utk handoff; chip abu netral "Ditahan" utk pesanan
/// biasa. Semua kartu jadi sama tinggi tanpa ruang kosong (tidak ada lagi
/// `Spacer()` internal yang dulu wajib demi menyamai tinggi kartu bertab).
class _HeldCard extends StatelessWidget {
  const _HeldCard({required this.order, required this.onTap});

  final HeldOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parsed = _parseHeldPayload(order.cartJson);
    final itemCount = parsed.items.where((c) => !c.isVariant).length;
    // Pakai perhitungan efektif — storedQty induk sudah memuat qty varian,
    // menjumlah subtotal mentah membuat varian terhitung dua kali.
    final total = cartTotalOf(parsed.items);
    final time =
        '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';
    final isHandoff = parsed.awaitingPayment && parsed.employeeName != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 172,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isHandoff
                  ? AppTheme.accent.withOpacity(0.35)
                  : cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Chip terracotta (warna tetap, TIDAK ikut role onPrimary yang
            // berubah di dark mode) supaya teks putih di dalamnya selalu
            // terbaca — lihat gotcha "teks putih tak terbaca" di CLAUDE.md.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isHandoff ? AppTheme.accent : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isHandoff) ...[
                    const Icon(Icons.person, size: 9, color: Colors.white),
                    const SizedBox(width: 3),
                  ],
                  // `Flexible` WAJIB — tanpa ini Row(mainAxisSize.min) melayout
                  // Text di lebar natural (tak terbatas), overflow kalau nama
                  // pegawai panjang meski card sudah dibatasi lebarnya.
                  Flexible(
                    child: Text(
                      isHandoff ? '${parsed.employeeName} · $time' : 'Ditahan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isHandoff ? Colors.white : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                // Item 55 — nomor nota (di-reserve sejak keranjang diisi/
                // ditahan), sama dgn yg tampil di cart bar.
                if (parsed.meta.displayOrderNumber != null) ...[
                  const SizedBox(width: 4),
                  Text('#${parsed.meta.displayOrderNumber}',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant)),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              isHandoff
                  ? '$itemCount item · siap dibayarkan'
                  : '$itemCount item · $time',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatRupiah(total),
                  style: AppTheme.numStyle(context,
                      size: 15, weight: FontWeight.w700, color: cs.primary),
                ),
                Icon(Icons.chevron_right, size: 16, color: cs.outlineVariant),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

