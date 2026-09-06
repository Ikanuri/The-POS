import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/cart_item.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/order_parser_service.dart';
import '../../../core/services/price_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/item_count_badge.dart';
import '../cart_meta_provider.dart';
import '../cart_prabayar_provider.dart';
import '../cart_price_category_provider.dart';
import '../cart_provider.dart';
import '../handoff_gate_provider.dart';
import 'debt_payment_sheet.dart';
import 'add_control.dart';
import 'cart_meta_pickers.dart';
import 'cart_preview_paper.dart';
import 'paste_order_sheet.dart';
import 'payment_qris_view.dart';

/// Susulan (permintaan user): posisi scroll TERAKHIR per keranjang (key:
/// `cartId`) — supaya kalau sheet ditutup (mis. misclick tap item yang
/// membuka modal entri, lalu balik lagi) & dibuka ulang, user tidak perlu
/// scroll ulang ke posisi semula, terutama saat belanjaan banyak & sedang
/// mencentang barang satu-satu. In-memory saja (bukan disimpan ke disk) —
/// cukup bertahan selama app berjalan, otomatis reset saat app ditutup total
/// (sama seperti keranjang itu sendiri secara konsep, walau keranjangnya
/// sendiri disimpan persisten di SharedPreferences terpisah).
final Map<String, double> _cartScrollMemory = {};

/// Test-only seam utk `_cartScrollMemory` (private ke file ini) — supaya
/// widget test bisa baca/tulis/bersihkan tanpa akses private, sama pola
/// dgn `debugAddProposal`/`debugClearProposals` di `LanSyncService`.
@visibleForTesting
class CartSheetScrollTestSeam {
  CartSheetScrollTestSeam._();
  static double? get(String cartId) => _cartScrollMemory[cartId];
  static void set(String cartId, double offset) =>
      _cartScrollMemory[cartId] = offset;
  static void clear() => _cartScrollMemory.clear();
}

class CartSheet extends ConsumerStatefulWidget {
  const CartSheet({
    super.key,
    this.cartId = kMainCartId,
    this.scrollToBottom = false,
    this.payRoute = '/kasir/bayar',
  });
  final String cartId;
  final bool scrollToBottom;
  final String payRoute;

  @override
  ConsumerState<CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends ConsumerState<CartSheet> {
  int _prevCount = 0;
  bool _needsInitialScroll = false;
  bool _scrollRestoreAttached = false;

  @override
  void initState() {
    super.initState();
    _needsInitialScroll = widget.scrollToBottom;
  }

  void _scheduleScroll(ScrollController sc) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !sc.hasClients) return;
      sc.animateTo(
        sc.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Item 24d/56 — transfer keranjang lewat QR, sepenuhnya offline. Dua
  /// pemicu berbeda pakai method yang SAMA persis: (1) pegawai TANPA izin
  /// `terima_pembayaran` — tombol Bayar utama otomatis beralih jadi ini
  /// (lihat `needsGate` di [build]); (2) owner/asisten/pegawai BERIZIN —
  /// tombol ikon Transfer terpisah (Item 56), utk melempar transaksi ke
  /// device lain (mis. sedang tidak bisa proses, minta owner/asisten lain
  /// lanjutkan). Penerima scan QR ini lewat scanner kasir yang sudah ada
  /// — hasilnya masuk ANTRIAN (`held_orders` awaitingPayment) di device
  /// PENERIMA, BUKAN langsung ke keranjang aktif mereka (lihat PLAN.md
  /// Item 24d) — lihat `_handleOrderCode` di kasir_screen.dart.
  Future<void> _showHandoffQr(
    BuildContext context,
    WidgetRef ref,
    List<CartItem> cart,
  ) async {
    final device = ref.read(deviceProvider);
    final meta = ref.read(cartMetaProvider(widget.cartId));
    final employeeName =
        meta.hasEmployee ? meta.employeeName! : device.deviceName;
    final needsGate = ref.read(needsPaymentGateProvider).valueOrNull ?? false;
    // Fitur Pra-Bayar — entri terkunci di keranjang INI ikut dibawa (data
    // mentah, keputusan adopsi ada di device PENERIMA — lihat dok
    // `OrderParserService.encodeHandoff`/`parse`).
    final prabayarPayload = ref
        .read(cartPrabayarProvider(widget.cartId))
        .map((e) => (
              amount: e.amount,
              method: e.method,
              methodName: e.methodName,
              lockedAtMs: e.lockedAt.millisecondsSinceEpoch,
            ))
        .toList();
    // Susulan (permintaan user, 14 Agt 2026): payload QR dipisah dari teks
    // Copy/Share. `OrderParserService.parse` HANYA membaca baris `#PSN:...`
    // + baris meta (Pegawai/Nama/dst) lewat regex per-baris — blok
    // manusiawi "PESANAN — toko / daftar produk / Total" (digerbang param
    // `storeName`, lihat dok Item 54 di `encodeHandoff`) SAMA SEKALI TIDAK
    // ikut di-parse, baik lewat scan kamera/HID maupun Tempel Pesanan. Blok
    // itu jadi beban murni di gambar QR (utk keranjang banyak baris/
    // catatan, blok inilah kontributor terbesar panjang teks) — makin
    // banyak modul, makin padat & rawan gagal-scan, TANPA manfaat
    // fungsional apa pun krn memang tidak pernah dibaca ulang. QR sekarang
    // pakai `storeName: null` (cuma kode mesin, padat modul rendah);
    // Copy/Share TETAP teks lengkap (enak dibaca manusia via WhatsApp/dst).
    final qrOnlyCodeText = OrderParserService.encodeHandoff(
      items: cart,
      employeeName: employeeName,
      customerName: meta.hasCustomer ? meta.customerName : null,
      customerId: meta.customerId,
      reservedLocalId: meta.reservedLocalId,
      trustPrices: !needsGate,
      storeName: null,
      prabayar: prabayarPayload,
    );
    final shareText = OrderParserService.encodeHandoff(
      items: cart,
      employeeName: employeeName,
      customerName: meta.hasCustomer ? meta.customerName : null,
      // Item 4/57 — bawa customerId supaya penerima auto-resolve pelanggan
      // (tidak perlu ubah dari "Umum" lalu pilih manual lagi).
      customerId: meta.customerId,
      // Item 55/56 — nomor nota yang SUDAH direservasi di device INI ikut
      // dibawa utuh, supaya "urutan pelanggan yang harus dilayani" tetap
      // sama di penerima (bukan reservasi baru).
      reservedLocalId: meta.reservedLocalId,
      // Susulan (kekhawatiran user, valid): device TANPA izin
      // terima_pembayaran (needsGate true — tombol Bayar-nya otomatis
      // jadi "Kirim ke Owner/Asisten") bisa menyetel Harga Lain/override
      // manual di keranjangnya sendiri TANPA gerbang izin apa pun. Kalau
      // harga itu dipercaya mentah-mentah, owner menerima harga yang
      // belum pernah divalidasi dari device tak berizin. Untuk pengirim
      // begini, harga TETAP di-resolve ulang fresh dari DB penerima
      // (perilaku lama) — hanya device BERIZIN (owner/asisten/pegawai
      // terima_pembayaran) yang harganya dipercaya penuh.
      trustPrices: !needsGate,
      // Item 54 — keterangan item + Total manusia-bisa-baca di depan kode
      // mesin, format sama dgn katalog HTML (`buildOrderText`).
      storeName: device.storeName,
      prabayar: prabayarPayload,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HandoffQrSheet(
        // Judul beda konteks: pegawai TANPA izin SELALU melempar ke
        // owner/asisten (satu arah pasti); transfer bebas (Item 56) bisa
        // ke device manapun, judul generik.
        title: needsGate ? 'Kirim ke Owner/Asisten' : 'Transfer Transaksi',
        qrCodeText: qrOnlyCodeText,
        shareText: shareText,
        itemCount: cart.where((c) => !c.isVariant).length,
        total: cart.fold<int>(0, (s, c) => s + (c.price * c.qty).round()),
      ),
    );
  }

  /// Susulan (permintaan user): "Tahan Pesanan" juga bisa dipicu LANGSUNG
  /// dari header keranjang yang sedang terbuka (di samping "Tempel
  /// Pesanan") — sebelumnya cuma bisa lewat tab folder di `kasir_screen.
  /// dart` (`_CartMetaTab`/`_holdCurrent`), yang tersembunyi begitu sheet
  /// keranjang ini dibuka. Logikanya SENGAJA disalin (bukan dibagi lewat
  /// fungsi bersama) — `_holdCurrent` versi kasir_screen.dart terikat erat
  /// ke state layar itu (`_heldPanelOpen`, banner kustom `_showBanner`),
  /// menyatukannya lewat abstraksi baru berisiko mengubah perilaku yang
  /// sudah berjalan tanpa ada yang memintanya. HANYA tersedia utk
  /// `kMainCartId` (gerbang sama persis dgn `_CartMetaTab` — mode Katalog
  /// bukan transaksi sungguhan, mode Tambah Belanjaan ikut transaksi asli
  /// yang tidak bisa "ditahan" terpisah).
  ///
  /// Susulan (permintaan user): kalau belum ada pelanggan terpilih, dialog
  /// pengisi label PERSIS dropdown "Pelanggan" di cart bar shrinked
  /// (`showCustomerPickerSheet`, dipakai bareng `_CartMetaTab`) — cari
  /// pelanggan terdaftar (lengkap atribut hutangnya) atau ketik nama
  /// manual, BUKAN dialog polos terpisah. Pelanggan terdaftar yang dipilih
  /// ikut disematkan ke `cartMetaProvider` (bukan cuma dipakai sbg teks
  /// label) — payload `held_order` jadi bawa `customerId` sungguhan,
  /// bukan cuma nama, konsisten dgn nota yang checkout normal.
  Future<void> _holdCurrent(BuildContext ctx, WidgetRef ref) async {
    final cart = ref.read(cartProvider(widget.cartId));
    if (cart.isEmpty) return;
    var meta = ref.read(cartMetaProvider(widget.cartId));

    String label;
    if (meta.hasCustomer) {
      label = meta.customerName!;
    } else {
      final pick = await showCustomerPickerSheet(ctx, ref);
      if (pick == null) return; // dibatalkan (tap di luar sheet)
      if (pick.id != null && pick.name != null) {
        ref
            .read(cartMetaProvider(widget.cartId).notifier)
            .setCustomer(pick.id, pick.name);
        meta = ref.read(cartMetaProvider(widget.cartId));
        label = pick.name!;
      } else {
        // "Umum" (tanpa nama) atau nama manual kosong -> fallback label
        // default, sama persis perilaku lama saat field label dikosongkan.
        final manual = pick.name?.trim();
        label = (manual == null || manual.isEmpty) ? 'Pesanan' : manual;
      }
    }

    final db = ref.read(databaseProvider);
    final prabayarNotifier =
        ref.read(cartPrabayarProvider(widget.cartId).notifier);
    final prabayar = ref.read(cartPrabayarProvider(widget.cartId));
    final priceCategoryId = ref.read(cartPriceCategoryProvider(widget.cartId));
    final payload = jsonEncode({
      'items': cart.map((c) => c.toJson()).toList(),
      'meta': meta.toJson(),
      'prabayar': prabayar.map((e) => e.toJson()).toList(),
      // Fitur "kembalian sudah diambil" — ikut ditahan/dipulihkan sama
      // persis siklus hidup entri Pra-Bayar sendiri (lihat dok
      // `CartPrabayarNotifier.replaceAll`).
      'prabayarChangeTaken': prabayarNotifier.changeTakenTotal,
      'priceCategory': priceCategoryId,
    });
    await db.holdOrder(id: const Uuid().v4(), label: label, cartJson: payload);
    ref.read(cartProvider(widget.cartId).notifier).clear();
    ref.read(cartMetaProvider(widget.cartId).notifier).clear();
    ref.read(cartPrabayarProvider(widget.cartId).notifier).clear();
    ref.read(cartPriceCategoryProvider(widget.cartId).notifier).clear();
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text('Pesanan "$label" ditahan')),
    );
    Navigator.of(ctx).pop();
  }

  /// Fase C "Kategori Harga" — tap chip toggle (termasuk chip "Normal" =
  /// [newCategoryId] null). Re-price SEMUA baris keranjang (kecuali
  /// `priceOverridden`) SEBELUM state provider-nya diganti — supaya rebuild
  /// berikutnya langsung menampilkan harga baru sekaligus dgn kategori
  /// aktif yang baru (bukan dua rebuild terpisah yg bisa kelihatan
  /// "berkedip").
  Future<void> _onCategoryToggle(WidgetRef ref, String? newCategoryId) async {
    final cart = ref.read(cartProvider(widget.cartId));
    final priceService = PriceService(ref.read(databaseProvider));
    final repriced = await repriceCartForCategoryChange(
      priceService: priceService,
      cart: cart,
      newCategoryId: newCategoryId,
    );
    if (!mounted) return;
    ref.read(cartProvider(widget.cartId).notifier).replaceAll(repriced);
    ref
        .read(cartPriceCategoryProvider(widget.cartId).notifier)
        .setCategory(newCategoryId);
  }

  /// Fitur Pra-Bayar — buka kalkulator pelunasan yang SUDAH ADA
  /// (`showDebtPaymentSheet`, dipakai juga oleh "Tambah Bayar" di
  /// receipt_screen.dart/tx_history_sheet.dart) dgn `remaining` = sisa yang
  /// BELUM terkunci (`total keranjang - totalLocked`, clamp 0 — sheet-nya
  /// sendiri sudah punya kalkulator bebas ketik nominal apa pun lebih dari
  /// itu, TIDAK di-cap paksa di sini). Hasilnya jadi satu [PrabayarEntry]
  /// baru (akumulatif, TIDAK menimpa entri lama).
  Future<void> _addPrabayar(BuildContext ctx, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final notifier = ref.read(cartProvider(widget.cartId).notifier);
    final prabayarNotifier =
        ref.read(cartPrabayarProvider(widget.cartId).notifier);
    final remaining =
        (notifier.totalAmount - prabayarNotifier.totalLocked).clamp(0, 99999999).toInt();
    final result = await showDebtPaymentSheet(
      ctx,
      db,
      remaining: remaining,
      title: 'Pra-Bayar',
    );
    if (result == null || result.amount <= 0) return;
    prabayarNotifier.add(PrabayarEntry(
      id: const Uuid().v4(),
      amount: result.amount,
      method: result.method,
      methodName: result.methodName,
      lockedAt: DateTime.now(),
    ));
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text('Pra-Bayar ${formatRupiah(result.amount)} dikunci')),
    );
  }

  /// Daftar entri Pra-Bayar terkunci — tiap entri bisa dihapus lagi selama
  /// belum checkout (kasir salah input).
  Future<void> _showPrabayarList(BuildContext ctx, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      builder: (sheetCtx) => Consumer(
        builder: (consumerCtx, sheetRef, _) {
          final entries = sheetRef.watch(cartPrabayarProvider(widget.cartId));
          final scheme = Theme.of(consumerCtx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text('Entri Pra-Bayar',
                      style: Theme.of(consumerCtx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('Belum ada entri Pra-Bayar',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(formatRupiah(e.amount),
                                style:
                                    const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                                '${e.methodName ?? _methodLabel(e.method)} · '
                                '${_fmtTime(e.lockedAt)}',
                                style: const TextStyle(fontSize: 12)),
                            trailing: IconButton(
                              tooltip: 'Hapus',
                              icon: Icon(Icons.delete_outline,
                                  color: scheme.error, size: 20),
                              onPressed: () => sheetRef
                                  .read(cartPrabayarProvider(widget.cartId)
                                      .notifier)
                                  .remove(e.id),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                      child: const Text('Tutup'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _methodLabel(String type) => switch (type) {
        'tunai' => 'Tunai',
        'qris' => 'QRIS',
        'bank' => 'Transfer Bank',
        'ewallet' => 'E-Wallet',
        'tempo' => 'Tempo',
        _ => type,
      };

  static String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  /// Item 56 — Kosongkan keranjang (ikon tempat sampah, dialog konfirmasi
  /// tetap ada) — juga melepas reservasi nomor nota (Item 55) supaya
  /// nomor itu tidak "hangus" selamanya kalau keranjang dibatalkan.
  Future<void> _confirmClear(BuildContext ctx, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Kosongkan Keranjang?'),
        content: const Text('Semua item akan dihapus dari keranjang.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dCtx).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(dCtx).pop(true),
              child: const Text('Kosongkan')),
        ],
      ),
    );
    if (ok != true) return;
    final meta = ref.read(cartMetaProvider(widget.cartId));
    if (meta.reservedLocalId != null) {
      await ref.read(databaseProvider).releaseLocalId(meta.reservedLocalId!);
    }
    ref.read(cartProvider(widget.cartId).notifier).clear();
    ref.read(cartMetaProvider(widget.cartId).notifier).clear();
    ref.read(cartPrabayarProvider(widget.cartId).notifier).clear();
    if (ctx.mounted) Navigator.of(ctx).pop();
  }

  Future<
      ({
        String name,
        String address,
        String phone,
        String whatsapp,
        String telegram,
        String header,
        String footer,
      })> _getStorePrefsForPreview() async {
    final db = ref.read(databaseProvider);
    return (
      name: await db.getSetting('store_name') ?? '',
      address: await db.getSetting('store_address') ?? '',
      phone: await db.getSetting('store_phone') ?? '',
      whatsapp: await db.getSetting('store_whatsapp') ?? '',
      telegram: await db.getSetting('store_telegram') ?? '',
      header: await db.getSetting('receipt_header') ?? '',
      footer: await db.getSetting('receipt_note') ?? '',
    );
  }

  /// Metode QRIS aktif pertama yang payload statisnya sudah diisi — sama
  /// persis pola `_activeQrisMethod` di receipt_screen.dart, tapi TANPA
  /// syarat status nota (di titik ini memang belum ada nota sama sekali).
  Future<PaymentMethod?> _activeQrisMethodForPreview() async {
    final db = ref.read(databaseProvider);
    final methods = await (db.select(db.paymentMethods)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    for (final m in methods) {
      if (m.type == 'qris' && (m.qrValue?.trim().isNotEmpty ?? false)) {
        return m;
      }
    }
    return null;
  }

  /// Susulan (permintaan user): "kadang pelanggan minta preview serta
  /// estimasi total" sebelum checkout — sheet share struk "Pratinjau
  /// Keranjang" (`CartPreviewPaper`), pola sheet & toggle QR SAMA persis
  /// dgn "Bagikan Struk" di receipt_screen.dart, tapi toggle-nya
  /// disimpan di key SharedPreferences terpisah (`cart_preview_show_qr`)
  /// — preferensi ini per-device utk pratinjau BELUM-checkout, tidak
  /// boleh ikut membocorkan/menimpa preferensi QR nota asli (mis. owner
  /// mau QR selalu tampil di pratinjau tapi tidak di struk lunas).
  Future<void> _showCartPreviewShareSheet(BuildContext ctx) async {
    final notifier = ref.read(cartProvider(widget.cartId).notifier);
    final items = List<CartItem>.from(ref.read(cartProvider(widget.cartId)));
    final meta = ref.read(cartMetaProvider(widget.cartId));
    final totalAmount = notifier.totalAmount;
    final customerName = (meta.customerName?.trim().isNotEmpty ?? false)
        ? meta.customerName!.trim()
        : 'Umum';

    final prefs = await _getStorePrefsForPreview();
    final device = ref.read(deviceProvider);
    if (!ctx.mounted) return;

    final qrisMethod = await _activeQrisMethodForPreview();
    if (!ctx.mounted) return;
    final sharedPrefs = await SharedPreferences.getInstance();
    var showQr = qrisMethod != null &&
        (sharedPrefs.getBool('cart_preview_show_qr') ?? false);
    var qrDynamic = sharedPrefs.getBool('cart_preview_qr_dynamic') ?? true;

    String? resolveQr() {
      if (!showQr || qrisMethod == null) return null;
      return resolveQrisPayload(
        staticPayload: qrisMethod.qrValue!,
        amount: totalAmount,
        dynamicMode: qrDynamic,
      ).data;
    }

    final boundaryKey = GlobalKey();
    var dragOverscroll = 0.0;
    if (!ctx.mounted) return;
    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(sheetCtx).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text('Bagikan Pratinjau',
                    style: Theme.of(sheetCtx).textTheme.titleMedium),
                const SizedBox(height: 12),
                Flexible(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is OverscrollNotification &&
                          n.dragDetails != null) {
                        dragOverscroll += n.overscroll;
                        if (dragOverscroll < -60) {
                          Navigator.of(sheetCtx).maybePop();
                        }
                      } else if (n is ScrollEndNotification) {
                        dragOverscroll = 0;
                      }
                      return false;
                    },
                    child: SingleChildScrollView(
                      child: RepaintBoundary(
                        key: boundaryKey,
                        child: CartPreviewPaper(
                          items: items,
                          effectiveQtyOf: notifier.effectiveQtyFor,
                          totalAmount: totalAmount,
                          customerName: customerName,
                          storeName: prefs.name.isNotEmpty
                              ? prefs.name
                              : device.storeName,
                          storeAddress: prefs.address,
                          storePhone: prefs.phone,
                          storeWhatsapp: prefs.whatsapp,
                          storeTelegram: prefs.telegram,
                          receiptHeader: prefs.header,
                          receiptFooter: prefs.footer,
                          qrData: resolveQr(),
                        ),
                      ),
                    ),
                  ),
                ),
                if (qrisMethod != null) ...[
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Tampilkan QR QRIS'),
                    subtitle: const Text(
                        'Muncul di pratinjau, nominal ikut estimasi total',
                        style: TextStyle(fontSize: 11)),
                    value: showQr,
                    onChanged: (v) {
                      setSheetState(() => showQr = v);
                      sharedPrefs.setBool('cart_preview_show_qr', v);
                    },
                  ),
                  if (showQr)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('QR Dinamis'),
                      subtitle: const Text(
                          'Nominal estimasi terkunci di QR — mati = QR statis polos',
                          style: TextStyle(fontSize: 11)),
                      value: qrDynamic,
                      onChanged: (v) {
                        setSheetState(() => qrDynamic = v);
                        sharedPrefs.setBool('cart_preview_qr_dynamic', v);
                      },
                    ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      _captureAndShareCartPreview(sheetCtx, boundaryKey),
                  icon: const Icon(Icons.share),
                  label: const Text('Bagikan Gambar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _captureAndShareCartPreview(
      BuildContext sheetCtx, GlobalKey boundaryKey) async {
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/pratinjau_keranjang_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Pratinjau Keranjang',
      );
      if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
    } catch (e) {
      if (sheetCtx.mounted) {
        ScaffoldMessenger.of(sheetCtx).showSnackBar(
          SnackBar(content: Text('Gagal membagikan: $e')),
        );
      }
    }
  }

  /// Susulan (permintaan user): dialog "Pengaturan Keranjang" — berisi
  /// posisi checkbox verifikasi (`CartCheckboxPosition`) DAN toggle
  /// konfirmasi tombol minus stepper (`cartMinusConfirmProvider`, mencegah
  /// missclick qty berkurang tanpa sengaja) — keduanya persisten
  /// (SharedPreferences), berlaku global utk semua keranjang, bukan
  /// per-`cartId`.
  void _showCartSettingsDialog(BuildContext ctx) {
    showDialog<void>(
      context: ctx,
      builder: (dCtx) => Consumer(
        builder: (context, dialogRef, _) {
          final current = dialogRef.watch(cartCheckboxPositionProvider);
          final minusConfirm = dialogRef.watch(cartMinusConfirmProvider);
          return AlertDialog(
            title: const Text('Pengaturan Keranjang'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Letak checkbox verifikasi',
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                  for (final pos in CartCheckboxPosition.values)
                    RadioListTile<CartCheckboxPosition>(
                      value: pos,
                      groupValue: current,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(pos.label),
                      onChanged: (v) {
                        if (v != null) {
                          dialogRef
                              .read(cartCheckboxPositionProvider.notifier)
                              .set(v);
                        }
                      },
                    ),
                  const Divider(height: 24),
                  SwitchListTile(
                    value: minusConfirm,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Konfirmasi sebelum kurangi qty'),
                    subtitle:
                        const Text('Tap pertama tombol minus cuma bergetar sbg '
                            'peringatan; tap berikutnya (selama stepper masih '
                            'membesar) baru benar-benar mengurangi qty'),
                    onChanged: (v) => dialogRef
                        .read(cartMinusConfirmProvider.notifier)
                        .set(v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dCtx).pop(),
                child: const Text('Tutup'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider(widget.cartId));
    final notifier = ref.read(cartProvider(widget.cartId).notifier);
    final meta = ref.watch(cartMetaProvider(widget.cartId));
    final scheme = Theme.of(context).colorScheme;
    final total = notifier.totalAmount;
    // Item 24d — gerbang HANYA untuk transaksi nyata (kasir utama & Tambah
    // Belanjaan), TIDAK untuk mode Katalog (bukan transaksi sungguhan).
    final needsGate = widget.cartId != kCatalogCartId &&
        (ref.watch(needsPaymentGateProvider).valueOrNull ?? false);
    // Item 56 — tombol Transfer QR: owner/asisten/pegawai BERIZIN (`!
    // needsGate`) bisa transfer transaksi ke device lain (mis. lempar ke
    // owner/asisten lain yg sedang tidak sibuk). Pegawai TANPA izin sudah
    // punya jalur sendiri (tombol Bayar utama otomatis jadi "Kirim ke
    // Owner/Asisten" — lihat di bawah), tidak perlu tombol tambahan.
    final canTransfer = widget.cartId != kCatalogCartId && !needsGate;
    // Fitur Pra-Bayar — HANYA keranjang utama kasir (bukan mode Katalog,
    // bukan Tambah Belanjaan — nota tambah belanjaan sudah lunas/checkout
    // sebelumnya, tidak relevan sama sekali, lihat dok `payment_screen.dart`)
    // & HANYA device dgn izin `terima_pembayaran` (sama persis gerbang
    // `canTransfer` di atas).
    final canPrabayar = widget.cartId == kMainCartId && !needsGate;
    final prabayarEntries = ref.watch(cartPrabayarProvider(widget.cartId));
    final prabayarTotal =
        prabayarEntries.fold<int>(0, (s, e) => s + e.amount);
    // Fitur "kembalian sudah diambil" — dibaca lewat notifier (bukan bagian
    // `state` yang di-watch di atas), tapi rebuild tetap terjamin: watch
    // `cartPrabayarProvider` di atas SUDAH cukup, karena
    // `CartPrabayarNotifier.recordChangeTaken` selalu re-assign `state`
    // (list baru) tiap kali nilai ini berubah — lihat dok di sana.
    final changeTakenTotal =
        ref.read(cartPrabayarProvider(widget.cartId).notifier).changeTakenTotal;

    // Fase C "Kategori Harga" — toggle HANYA di keranjang utama kasir (bukan
    // mode Katalog/Tambah Belanjaan, lihat briefing), device berizin
    // `override_harga` (gerbang SAMA beratnya dgn override harga manual),
    // DAN minimal ada 1 kategori terdaftar (kalau owner belum pernah bikin
    // kategori, baris ini tidak ada gunanya sama sekali).
    final priceCategories = widget.cartId == kMainCartId
        ? (ref.watch(priceCategoriesForToggleProvider).valueOrNull ?? const [])
        : const <PriceCategory>[];
    final canOverrideHarga =
        ref.watch(canOverrideHargaProvider).valueOrNull ?? false;
    final canToggleCategory = widget.cartId == kMainCartId &&
        priceCategories.isNotEmpty &&
        canOverrideHarga;
    final activeCategoryId = ref.watch(cartPriceCategoryProvider(widget.cartId));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        // Susulan (permintaan user) — pulihkan posisi scroll terakhir SEKALI
        // saja per instance sheet (builder ini bisa dipanggil ulang tiap
        // rebuild, mis. tiap kali cart berubah — listener/restore ganda
        // harus dihindari). Prioritas: `scrollToBottom` eksplisit (item baru
        // ditambah) MENANG dari posisi tersimpan — user jelas ingin lihat
        // item baru, bukan posisi lama.
        if (!_scrollRestoreAttached) {
          _scrollRestoreAttached = true;
          final saved = _cartScrollMemory[widget.cartId];
          if (saved != null && !_needsInitialScroll) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !scrollCtrl.hasClients) return;
              scrollCtrl.jumpTo(
                  saved.clamp(0.0, scrollCtrl.position.maxScrollExtent));
            });
          }
          scrollCtrl.addListener(() {
            if (scrollCtrl.hasClients) {
              _cartScrollMemory[widget.cartId] = scrollCtrl.offset;
            }
          });
        }
        if (_needsInitialScroll && cart.isNotEmpty) {
          _needsInitialScroll = false;
          _scheduleScroll(scrollCtrl);
        }
        if (cart.length > _prevCount && _prevCount > 0) {
          _scheduleScroll(scrollCtrl);
        }
        _prevCount = cart.length;
        return Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // Susulan (permintaan user): tombol "Bagikan Pratinjau" & fitur
              // Pra-Bayar menambah baris ikon jadi sampai 7 IconButton
              // sekaligus — dgn padding/minimumSize default (48dp) row ini
              // OVERFLOW di layar sempit sungguhan (360dp, lihat
              // cart_sheet_header_overflow_test.dart & gotcha overflow
              // tombol di CLAUDE.md). Persempit SEMUA IconButton di baris
              // ini via theme lokal (bukan satu-satu) TIDAK LAGI CUKUP begitu
              // jumlah ikon terus bertambah (7 ikon @36dp = 252dp, ditambah
              // judul "Keranjang" + "#nomor" tetap overflow di 360dp) —
              // blok ikon sekarang scroll horizontal sendiri (`reverse:
              // true`, jadi ikon PALING KANAN — Kosongkan — yang defaultnya
              // terlihat, bukan yang paling kiri), judul TETAP fixed & selalu
              // terlihat penuh di sisi kiri.
              child: IconButtonTheme(
                data: IconButtonThemeData(
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(4),
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(36, 36),
                  ),
                ),
                child: Row(
                  children: [
                    Text('Keranjang',
                        style: Theme.of(context).textTheme.titleMedium),
                    if (meta.displayOrderNumber != null) ...[
                      const SizedBox(width: 8),
                      Text('#${meta.displayOrderNumber}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant)),
                    ],
                    const SizedBox(width: 4),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                    // Susulan (permintaan user): "Tahan Pesanan" langsung dari
                    // header keranjang, di SAMPING KIRI "Tempel Pesanan" —
                    // gerbang sama persis dgn tab folder `_CartMetaTab` di
                    // kasir_screen.dart (cuma `kMainCartId`; mode Katalog
                    // bukan transaksi sungguhan, mode Tambah Belanjaan ikut
                    // transaksi asli yang tidak bisa ditahan terpisah).
                    if (widget.cartId == kMainCartId)
                      IconButton(
                        tooltip: 'Tahan Pesanan',
                        onPressed:
                            cart.isEmpty ? null : () => _holdCurrent(ctx, ref),
                        icon: const Icon(Icons.pause_circle_outline),
                      ),
                    // Susulan (revisi desain user): tombol "Pra-Bayar" pindah
                    // dari header ke baris footer (sebelah tombol Bayar) —
                    // lihat blok footer di bawah. Header sekarang tinggal 6
                    // ikon (Tahan Pesanan, Tempel Pesanan, Bagikan Pratinjau,
                    // Pengaturan Keranjang, Transfer QR, Kosongkan).
                    // Susulan (permintaan user): "Tempel Pesanan" juga bisa
                    // dipakai LANGSUNG dari keranjang yang sedang terbuka —
                    // berguna kalau ada pesanan tambahan (dari pelanggan via
                    // katalog HTML, atau pegawai tanpa izin terima_pembayaran
                    // yang mau menambah pesanan) sebelum keranjang ini
                    // di-checkout. Tidak tersedia di mode Katalog (bukan
                    // transaksi sungguhan). `PasteOrderSheet` sudah generik
                    // per-cartId & langsung merge ke keranjang ini (bukan
                    // bikin held_order baru) — tidak perlu logika baru.
                    if (widget.cartId != kCatalogCartId)
                      IconButton(
                        tooltip: 'Tempel Pesanan',
                        onPressed: () => showModalBottomSheet(
                          context: ctx,
                          isScrollControlled: true,
                          builder: (_) =>
                              PasteOrderSheet(cartId: widget.cartId),
                        ),
                        icon: const Icon(Icons.content_paste_go),
                      ),
                    // Susulan (permintaan user): "Bagikan Pratinjau" — kadang
                    // pelanggan minta lihat rincian & estimasi total SEBELUM
                    // checkout (mis. lewat WhatsApp). Struk gambarnya SENGAJA
                    // widget terpisah (`CartPreviewPaper`, bukan `_ReceiptPaper`
                    // dari receipt_screen.dart) supaya tidak ada risiko
                    // logic status lunas/tempo nota ASLI ikut kecampur dgn
                    // "belum checkout". Tidak tersedia di mode Katalog (bukan
                    // keranjang transaksi sungguhan).
                    if (widget.cartId != kCatalogCartId)
                      IconButton(
                        tooltip: 'Bagikan Pratinjau',
                        onPressed: cart.isEmpty
                            ? null
                            : () => _showCartPreviewShareSheet(ctx),
                        // `share_outlined`, bukan `ios_share` — disamakan dgn
                        // ikon "Bagikan Struk" di receipt_screen.dart (tombol
                        // yg fungsinya identik: buka sheet share, bukan aksi
                        // share langsung), supaya konsisten satu app.
                        icon: const Icon(Icons.share_outlined),
                      ),
                    // Susulan (permintaan user): tombol pengaturan keranjang —
                    // untuk sekarang isinya cuma posisi checkbox verifikasi
                    // (lihat `CartCheckboxPosition`), tapi dibuat generik
                    // ("Pengaturan Keranjang") supaya opsi lain bisa ditambah
                    // ke dialog yang sama nanti tanpa tombol baru lagi.
                    IconButton(
                      tooltip: 'Pengaturan Keranjang',
                      onPressed: () => _showCartSettingsDialog(ctx),
                      icon: const Icon(Icons.settings_outlined),
                    ),
                    if (canTransfer)
                      IconButton(
                        tooltip: 'Transfer via QR',
                        onPressed: cart.isEmpty
                            ? null
                            : () => _showHandoffQr(ctx, ref, cart),
                        icon: const _QrTransferIcon(),
                      ),
                    IconButton(
                      tooltip: 'Kosongkan',
                      onPressed:
                          cart.isEmpty ? null : () => _confirmClear(ctx, ref),
                      icon: Icon(Icons.delete_outline, color: scheme.error),
                    ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            // Fase C "Kategori Harga" — chip toggle "Normal" + tiap
            // PriceCategories terdaftar. Baris ini disembunyikan TOTAL bila
            // gerbang [canToggleCategory] tidak terpenuhi (lihat dok di atas).
            if (canToggleCategory)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Normal'),
                        selected: activeCategoryId == null,
                        onSelected: (_) => _onCategoryToggle(ref, null),
                      ),
                      for (final cat in priceCategories) ...[
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text(cat.name),
                          selected: activeCategoryId == cat.id,
                          onSelected: (_) => _onCategoryToggle(ref, cat.id),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (canToggleCategory) const Divider(height: 1),
            Expanded(
              child: cart.isEmpty
                  ? Center(
                      child: Text(
                        'Keranjang kosong',
                        style: TextStyle(
                            fontSize: 15, color: scheme.onSurfaceVariant),
                      ),
                    )
                  : Builder(builder: (_) {
                      final ordered = orderCartItems(cart);
                      return StepperActiveScope(
                        child: ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: ordered.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 56),
                          itemBuilder: (ctx2, i) {
                            final item = ordered[i];
                            final effQty = notifier.effectiveQtyFor(item);
                            return _CartItemTile(
                              // Susulan (permintaan user, fitur getar+tap-lagi
                              // minus): key stabil PER-ITEM wajib supaya state
                              // "bersenjata" (`_armed`)/timer TIDAK bocor ke
                              // baris lain kalau urutan keranjang berubah
                              // (mis. qty item lain diubah, ikut mengubah
                              // `orderCartItems`).
                              key: ValueKey(item.productUnitId),
                              index: i,
                              item: item,
                              isVariant: item.isVariant,
                              effectiveQty: effQty,
                              cartId: widget.cartId,
                            );
                          },
                        ),
                      );
                    }),
            ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Badge jumlah item — gaya sama dgn cart bar kasir, supaya
                  // representasi "jumlah barang" konsisten di seluruh alur.
                  ItemCountBadge(count: cart.where((c) => !c.isVariant).length),
                  const SizedBox(width: 10),
                  // Fitur Pra-Bayar (revisi desain user): ringkasan
                  // Pra-Bayar/Sisa/Kembalian sekarang jadi baris kecil DI
                  // BAWAH "Total" (bukan banner terpisah lagi) — tap area ini
                  // (bukan "Total"-nya sendiri) tetap buka daftar entri
                  // (`_showPrabayarList`), sama seperti banner lama.
                  Flexible(
                    child: InkWell(
                      onTap: (canPrabayar && prabayarEntries.isNotEmpty)
                          ? () => _showPrabayarList(ctx, ref)
                          : null,
                      borderRadius: BorderRadius.circular(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Total',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  )),
                          // Susulan (permintaan user): nominal Total dibuat
                          // DINAMIS (mengecil otomatis lewat FittedBox), bukan
                          // ukuran font tetap 22px — sejak ikon Pra-Bayar
                          // menempati ruang di sebelah tombol Bayar, lebar
                          // yang tersisa utk Total lebih sempit, harga besar
                          // (mis. "Rp 12.345.678") bisa terpotong jadi 2 baris
                          // tanpa ini.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              formatRupiah(total),
                              maxLines: 1,
                              style: AppTheme.numStyle(context,
                                  size: 22,
                                  weight: FontWeight.w700,
                                  color: scheme.primary),
                            ),
                          ),
                          if (canPrabayar && prabayarEntries.isNotEmpty)
                            _PrabayarFooterSummary(
                              cartId: widget.cartId,
                              total: total,
                              prabayarTotal: prabayarTotal,
                              changeTakenTotal: changeTakenTotal,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Susulan (revisi desain user): tombol "Pra-Bayar" pindah
                  // dari header ke sini (sebelah tombol Bayar) — sekunder,
                  // ikon saja tanpa label supaya tombol Bayar tetap dominan.
                  if (canPrabayar)
                    IconButton.filledTonal(
                      tooltip: 'Pra-Bayar',
                      onPressed:
                          cart.isEmpty ? null : () => _addPrabayar(ctx, ref),
                      icon: const Icon(Icons.lock_clock_outlined),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: cart.isEmpty
                          ? null
                          : needsGate
                              ? () => _showHandoffQr(context, ref, cart)
                              : () {
                                  Navigator.of(ctx).pop();
                                  context.push(widget.payRoute);
                                },
                      child:
                          Text(needsGate ? 'Kirim ke Owner/Asisten' : 'Bayar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Lama getar peringatan ("gesture warning") tombol minus saat toggle
/// "Konfirmasi sebelum kurangi qty" aktif.
const _kMinusShakeDuration = Duration(milliseconds: 400);

class _CartItemTile extends ConsumerStatefulWidget {
  const _CartItemTile({
    super.key,
    required this.index,
    required this.item,
    this.isVariant = false,
    required this.effectiveQty,
    required this.cartId,
  });
  final int index;
  final CartItem item;
  final bool isVariant;
  final double effectiveQty;
  final String cartId;

  @override
  ConsumerState<_CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends ConsumerState<_CartItemTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  // Susulan (perubahan desain KEDUA, permintaan user — jendela waktu tetap
  // 1.5 detik DIHAPUS TOTAL): "bersenjata" sekarang berlaku SELAMA stepper
  // baris ini masih membesar (`AddControl.activeStepper`, mekanisme
  // "pijakan jempol" yang SUDAH ADA — stepper tetap besar sampai user tap
  // AREA LAIN/scroll, lihat dok di `add_control.dart`), BUKAN sampai timer
  // habis. Alasan user: kadang butuh menekan minus berkali-kali TANPA
  // pindah jempol — jendela waktu tetap bikin tap kedua/ketiga/dst yang
  // terlambat (tapi jempol MASIH di situ) dianggap tap pertama lagi
  // (getar ulang, bukan mengurangi).
  final GlobalKey<State<AddControl>> _stepperKey = GlobalKey();
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _shakeController =
        AnimationController(vsync: this, duration: _kMinusShakeDuration);
    AddControl.activeStepper.addListener(_handleActiveStepperChanged);
  }

  @override
  void dispose() {
    AddControl.activeStepper.removeListener(_handleActiveStepperChanged);
    _shakeController.dispose();
    super.dispose();
  }

  /// Dipanggil setiap kali stepper YANG SEDANG MEMBESAR di seluruh layar
  /// berganti (mis. user tap stepper baris LAIN, tap area kosong, atau
  /// scroll — lihat `StepperActiveScope`/`AddControl.clearActive`). Kalau
  /// baris KITA tadinya bersenjata & TERNYATA bukan lagi stepper yang aktif
  /// (jempol sudah pindah), lepas status bersenjata.
  void _handleActiveStepperChanged() {
    if (_armed &&
        !identical(AddControl.activeStepper.value, _stepperKey.currentState)) {
      _disarm();
    }
  }

  void _disarm() {
    if (_armed && mounted) setState(() => _armed = false);
  }

  /// Tap PERTAMA (belum `_armed`): getarkan baris sbg warning — TIDAK
  /// mengurangi qty sama sekali. Tap KEDUA/ketiga/dst yang jatuh SELAMA
  /// stepper baris ini masih membesar (`_armed` masih true, lihat
  /// `_handleActiveStepperChanged`): benar-benar mengurangi qty tanpa
  /// dilepas statusnya — jempol boleh menekan minus berkali-kali beruntun
  /// tanpa perlu getar ulang tiap kali, PERSIS spt stepper `+` biasa.
  void _handleMinusTap(CartNotifier notifier) {
    if (_armed) {
      notifier.setEffectiveQty(
          widget.item.productUnitId, widget.effectiveQty - 1);
      return;
    }
    setState(() => _armed = true);
    _shakeController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isVariant = widget.isVariant;
    final effectiveQty = widget.effectiveQty;
    final cartId = widget.cartId;
    final notifier = ref.read(cartProvider(cartId).notifier);
    final scheme = Theme.of(context).colorScheme;
    final isZeroed = !isVariant && effectiveQty == 0;
    final subtotal = (item.price * effectiveQty).round();
    // Susulan (permintaan user): letak checkbox verifikasi sekarang bisa
    // diatur (dialog "Pengaturan Keranjang" di header `CartSheet`) — 4 opsi,
    // lihat `CartCheckboxPosition`. Widget-nya dibangun sekali di sini lalu
    // ditaruh di salah satu dari 4 posisi berbeda di bawah (mutually
    // exclusive, cuma satu cabang `if` yang aktif per build).
    final position = ref.watch(cartCheckboxPositionProvider);
    // Susulan (perubahan desain, permintaan user): toggle "Konfirmasi
    // sebelum kurangi qty" di dialog "Pengaturan Keranjang" — mencegah qty
    // berkurang tanpa sengaja (missclick) saat menekan tombol minus
    // stepper. Default OFF. Versi AWAL fitur ini pakai dialog konfirmasi —
    // diganti total krn butuh 1 tap ekstra + jempol biasanya sudah di atas
    // stepper (menutupi warning kalau cuma stepper yg digetarkan) — jadi
    // SELURUH baris ikut bergetar (lihat `_handleMinusTap`), lebih kentara
    // walau jempol/fokus mata sedang di area manapun pada baris ini.
    final minusConfirm = ref.watch(cartMinusConfirmProvider);
    final checkbox = Checkbox(
      value: item.checked,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onChanged: (v) => notifier.setChecked(item.productUnitId, v ?? false),
    );

    // Susulan (permintaan user): baris keranjang TIDAK lagi memakai
    // `ListTile`. Alasannya konkret — `ListTile` mengunci tinggi
    // leading/trailing-nya ke 48px (dense) apa pun tinggi barisnya, jadi
    // nominal subtotal MUSTAHIL ditumpuk di bawah stepper di dalam
    // `trailing` tanpa overflow (kena persis saat perubahan ini dibuat:
    // "RenderFlex overflowed by 14 pixels"). Disusun manual dengan `Row`
    // supaya blok kanan (centang + stepper + subtotal) bebas tinggi dan
    // tetap aman saat skala font sistem dibesarkan.
    return AnimatedBuilder(
      animation: _shakeController,
      // Osilasi horizontal meredam (amplitudo mengecil seiring waktu) —
      // pola getar umum utk warning "hati-hati" tanpa perlu paket animasi
      // tambahan.
      builder: (context, child) {
        final t = _shakeController.value;
        final dx = t == 0 ? 0.0 : sin(t * pi * 6) * 6 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Opacity(
        opacity: isZeroed ? 0.45 : 1.0,
        child: InkWell(
          // Tap item keranjang → tutup sheet keranjang sambil mengembalikan id
          // produk yang akan diedit. Kasir akan membuka modal entri item di atas
          // layar (bukan bertumpuk di atas DraggableScrollableSheet, yang
          // memutus koneksi input keyboard). Untuk varian, kirim id induk.
          onTap: () {
            final targetId = (item.isVariant && item.parentProductId != null)
                ? item.parentProductId!
                : item.productId;
            Navigator.of(context).pop(targetId);
          },
          child: Container(
            // Susulan (permintaan user): highlight soft utk item yang sudah
            // dicentang (verifikasi serah-terima) — supaya kelihatan sekilas
            // baris mana yang sudah/belum dicek, tanpa mengganggu keterbacaan
            // teks (opacity rendah, warna tema `primary`, bukan warna keras).
            color: item.checked
                ? scheme.primary.withOpacity(0.08)
                : Colors.transparent,
            child: Padding(
              // Susulan (permintaan user): jarak ke tepi layar diperlebar di
              // KEDUA sisi (dulu 8/4px — terlalu mepet, checklist+stepper nyaris
              // menempel tepi kanan, nama+nominal nyaris menempel tepi kiri).
              padding: EdgeInsets.fromLTRB(isVariant ? 40 : 16, 4, 16, 4),
              child: Row(
                children: [
                  // Susulan (permintaan user): checkbox verifikasi posisi
                  // "depan qty, paling kiri" — DEFAULT, tapi sekarang cuma satu
                  // dari 4 opsi yang bisa dipilih (lihat `position` di atas).
                  if (position == CartCheckboxPosition.depanQty) checkbox,
                  // Item 44 — badge jumlah qty di KIRI item (selain angka di
                  // stepper kanan), supaya qty langsung kebaca tanpa lihat ke
                  // stepper. Hanya tampil bila qty > 0 (baris "via varian" qty 0
                  // tidak diberi badge).
                  if (effectiveQty > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '${effectiveQty % 1 == 0 ? effectiveQty.toInt() : effectiveQty}\u00d7',
                        style: AppTheme.numStyle(context,
                            size: 13,
                            weight: FontWeight.w600,
                            color: scheme.onSurfaceVariant),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (isVariant)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(Icons.subdirectory_arrow_right,
                                    size: 15, color: scheme.onSurfaceVariant),
                              ),
                            Flexible(
                              // Permintaan user — nama produk panjang dulu terpotong 1 baris
                              // (ellipsis); sekarang auto-tumbuh sampai 2 baris. `ListTile`
                              // menyesuaikan tinggi baris ke title/subtitle-nya sendiri,
                              // leading/trailing (checkbox, stepper, harga) tetap fixed-size
                              // & otomatis center-vertikal — tidak perlu restrukturisasi.
                              //
                              // Item 52 redesain pre-order — label "Titip [qty]" (jaminan
                              // dititip) DISATUKAN ke text run yang SAMA (bukan Text/Container
                              // terpisah dgn jarak sendiri) — pola PERSIS badge "Habis" di
                              // katalog kasir (`'${product.name} · Habis'`), supaya
                              // keterangannya menempel rapat ke nama, bukan berjarak.
                              //
                              // Susulan (permintaan user): `Expanded` diganti `Flexible` —
                              // dibutuhkan supaya opsi checkbox "kanan nama" bisa menempel
                              // PAS setelah nama (bukan terdorong ke ujung kanan baris);
                              // `Flexible` (loose fit) membiarkan Text menyusut ke lebar
                              // aslinya, beda dari `Expanded` (tight fit) yang MEMAKSA lebar
                              // penuh ruang tersisa walau namanya pendek.
                              child: (item.depositQty != null &&
                                      item.depositQty! > 0)
                                  ? Text.rich(
                                      TextSpan(
                                        style: TextStyle(
                                            fontSize: isVariant ? 15 : 17,
                                            color: isVariant
                                                ? scheme.onSurfaceVariant
                                                : null),
                                        children: [
                                          TextSpan(text: item.productName),
                                          TextSpan(
                                            text:
                                                ' · Titip ${item.depositQty! % 1 == 0 ? item.depositQty!.toInt() : item.depositQty}',
                                            style: TextStyle(
                                                fontSize: isVariant ? 12 : 13,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.laciFg(
                                                    Theme.of(context)
                                                            .brightness ==
                                                        Brightness.dark)),
                                          ),
                                        ],
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : Text(item.productName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: isVariant ? 15 : 17,
                                          color: isVariant
                                              ? scheme.onSurfaceVariant
                                              : null)),
                            ),
                            if (position == CartCheckboxPosition.kananNama) ...[
                              const SizedBox(width: 2),
                              checkbox,
                            ],
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text.rich(
                                    TextSpan(
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: scheme.onSurfaceVariant),
                                      children: [
                                        TextSpan(text: '${item.unitName} · '),
                                        TextSpan(
                                            text: formatRupiah(item.price),
                                            style: AppTheme.numStyle(context,
                                                size: 13,
                                                color:
                                                    scheme.onSurfaceVariant)),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (item.priceOverridden) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.edit,
                                      size: 12, color: scheme.tertiary),
                                ] else if (item.priceFromCategoryId !=
                                    null) ...[
                                  // Fase C — penanda "harga dari toggle
                                  // kategori aktif", ikon SENGAJA beda dari
                                  // pensil override manual di atas (supaya
                                  // kasir bisa bedakan sekilas) — `else if`
                                  // krn keduanya seharusnya tidak pernah
                                  // bersamaan (lihat dok
                                  // `CartItem.priceFromCategoryId`).
                                  const SizedBox(width: 4),
                                  Icon(Icons.sell_outlined,
                                      size: 12, color: scheme.secondary),
                                ],
                                if (isZeroed) ...[
                                  const SizedBox(width: 4),
                                  Text('via varian',
                                      style: TextStyle(
                                          fontSize: 12, color: scheme.primary)),
                                ],
                              ],
                            ),
                            // Susulan (permintaan user): nominal subtotal taruh PERSIS di
                            // bawah baris satuan+harga ("Karung · Rp 65.000") — bukan di
                            // blok kanan (dulu sempat dicoba di bawah qty badge kiri, lalu
                            // di bawah stepper; keduanya BUKAN yang dimaksud user).
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                formatRupiah(subtotal),
                                style: AppTheme.numStyle(context,
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: isZeroed
                                        ? scheme.onSurfaceVariant
                                        : scheme.primary),
                              ),
                            ),
                            if (item.itemNote != null &&
                                item.itemNote!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 3, 6, 3),
                                  decoration: BoxDecoration(
                                    border: Border(
                                        left: BorderSide(
                                            width: 3,
                                            color: scheme.tertiary
                                                .withOpacity(0.5))),
                                    color: scheme.tertiary.withOpacity(0.06),
                                    borderRadius: const BorderRadius.horizontal(
                                        right: Radius.circular(4)),
                                  ),
                                  child: Text(
                                    item.itemNote!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                        color: scheme.tertiary),
                                  ),
                                ),
                              ),
                            // Susulan (permintaan user): peringatan mismatch harga
                            // transfer transaksi (lihat `CartItem.priceMismatchLocal`)
                            // — REUSE pola visual badge `itemNote` di atas (border kiri
                            // + background tint) tapi warna warning (`scheme.error`,
                            // bukan `scheme.tertiary`) & taruh sbg badge TERPISAH di
                            // bawah subtotal, BUKAN inline di baris "unitName · harga"
                            // yang sudah sesak (risiko overflow di HP sempit). Murni
                            // informasional — harga yang dipakai/tersimpan TETAP
                            // [item.price], badge ini TIDAK mengubah apa pun.
                            if (item.priceMismatchLocal != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 3, 6, 3),
                                  decoration: BoxDecoration(
                                    border: Border(
                                        left: BorderSide(
                                            width: 3,
                                            color: scheme.error
                                                .withOpacity(0.5))),
                                    color: scheme.error.withOpacity(0.06),
                                    borderRadius: const BorderRadius.horizontal(
                                        right: Radius.circular(4)),
                                  ),
                                  child: Text.rich(
                                    TextSpan(
                                      style: TextStyle(
                                          fontSize: 12, color: scheme.error),
                                      children: [
                                        const TextSpan(
                                            text: '⚠ Harga pengirim beda dari '
                                                'lokal: '),
                                        TextSpan(
                                          text: formatRupiah(
                                              item.priceMismatchLocal!),
                                          style: const TextStyle(
                                              decoration:
                                                  TextDecoration.lineThrough),
                                        ),
                                        const TextSpan(text: ' → '),
                                        TextSpan(
                                          text: formatRupiah(item.price),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Susulan (permintaan user): nominal PINDAH ke bawah baris
                  // satuan+harga (lihat blok kiri di atas) — blok kanan sekarang
                  // cuma stepper, KECUALI kalau posisi checkbox diatur ke
                  // "kiri stepper"/"belakang stepper" (lihat 2 cabang di bawah).
                  if (position == CartCheckboxPosition.kiriStepper) ...[
                    checkbox,
                    // Jarak supaya checkbox tidak ikut terpencet saat menekan
                    // tombol minus stepper (permintaan eksplisit user).
                    const SizedBox(width: 6),
                  ],
                  AddControl(
                    key: _stepperKey,
                    qty: effectiveQty,
                    // Keluhan user: stepper baris keranjang masih sering
                    // missclick (dibahas lebih lanjut nanti, lihat
                    // docs/HANDOFF.md) — pijakan jempol diperbesar 30->44
                    // (+~45%, sengaja SEDIKIT di bawah "setengah lebih besar"
                    // literal /1.5x/45 supaya nama produk 2-baris di sebelahnya
                    // tetap muat wajar di HP sempit, lihat
                    // `cart_stepper_size_test.dart`). Stepper LAIN (grid/list
                    // produk, baris varian — `kasir_screen.dart`) SENGAJA
                    // tidak ikut diperbesar: itu utk MENAMBAH item baru, bukan
                    // titik misclick yang dikeluhkan (mengubah qty transaksi).
                    size: 44,
                    onTap: () => notifier.setEffectiveQty(
                        item.productUnitId, effectiveQty + 1),
                    onMinus: isZeroed
                        ? null
                        : minusConfirm
                            ? () => _handleMinusTap(notifier)
                            : () => notifier.setEffectiveQty(
                                item.productUnitId, effectiveQty - 1),
                  ),
                  if (position == CartCheckboxPosition.belakangStepper) ...[
                    // Jarak supaya checkbox tidak ikut terpencet saat menekan
                    // tombol plus stepper (permintaan eksplisit user).
                    const SizedBox(width: 6),
                    checkbox,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Item 24d — QR handoff pesanan pegawai. Sheet ini murni menampilkan QR +
/// jalur cadangan (salin teks/share) — TIDAK ada tombol yang mengosongkan
/// keranjang di sini lagi (susulan: tombol "Sudah Dikirim, Kosongkan
/// Keranjang" persis di atas "Tutup" sering ke-misclick, menghapus
/// keranjang yang sebenarnya belum terkirim). Mengosongkan keranjang tetap
/// bisa lewat ikon tempat sampah di header `CartSheet` (`_confirmClear`,
/// ada dialog konfirmasi).
class _HandoffQrSheet extends StatelessWidget {
  const _HandoffQrSheet({
    required this.title,
    required this.qrCodeText,
    required this.shareText,
    required this.itemCount,
    required this.total,
  });

  final String title;

  /// Payload GAMBAR QR — cuma kode mesin (`#PSN:...` + baris meta), TANPA
  /// blok manusiawi "PESANAN — toko / daftar produk / Total" — lihat dok
  /// panjang di `_showHandoffQr`. Lebih pendek = modul QR lebih rendah =
  /// lebih gampang di-scan, TANPA mengubah apa pun yang diterima penerima
  /// (blok yang dibuang memang tidak pernah ikut ke-parse).
  final String qrCodeText;

  /// Teks utk tombol Salin/Share — TETAP lengkap (blok manusiawi + kode
  /// mesin) supaya enak dibaca kalau ditempel di WhatsApp/Telegram.
  final String shareText;
  final int itemCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '$itemCount item · ${formatRupiah(total)}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(data: qrCodeText, size: 220),
            ),
            const SizedBox(height: 12),
            Text(
              'Minta owner/asisten scan QR ini lewat scanner kasir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 10),
            // Jalur cadangan kalau scan QR susah (kamera rusak/pencahayaan
            // kurang) — teks pesanan (versi LENGKAP, beda dari isi QR yang
            // diperkecil demi kepadatan modul — lihat dok `shareText`) bisa
            // ditempel manual lewat WhatsApp/Telegram, lalu owner buka
            // "Tempel Pesanan" di kasir (parser sudah baca format ini).
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: shareText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Teks pesanan disalin')),
                );
              },
              icon: const Icon(Icons.copy_outlined, size: 16),
              label: const Text('Salin Teks Pesanan'),
            ),
            const SizedBox(height: 20),
            // Susulan (permintaan user): tombol "Sudah Dikirim, Kosongkan
            // Keranjang" di sini (persis di atas "Tutup") sering ke-misclick
            // — akibatnya keranjang yang SEBENARNYA belum terkirim malah
            // terhapus. Diganti tombol Share (kirim teks pesanan lewat
            // WhatsApp/dst) yang aman diklik — mengosongkan keranjang tetap
            // bisa lewat ikon tempat sampah di header (`_confirmClear`),
            // aksi destruktif jadi butuh langkah terpisah yang disengaja.
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () => Share.share(shareText),
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Share Pesanan'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fitur Pra-Bayar (revisi desain user) — ringkasan kecil di bawah nominal
/// "Total": baris "Pra-Bayar Rp X" (warna netral/teks biasa), lalu SATU baris
/// tambahan "Sisa Rp Z" (merah, `AppTheme.debtFg`) kalau masih kurang, ATAU
/// "Kembalian Rp Y" (hijau, `AppTheme.changeFg`) + checkbox "sudah diambil"
/// kalau sudah lebih — kalau pas (selisih 0) tidak ada baris kedua sama
/// sekali. Font kecil (11px) & `TextOverflow.ellipsis` sengaja — Column ini
/// sebelahan dgn `Expanded(Bayar)` di Row yang sama, nominal panjang (mis.
/// "Kembalian Rp 1.250.000") tidak boleh mendesak tombol Bayar (lihat gotcha
/// overflow di CLAUDE.md, WAJIB test 360dp).
///
/// Fitur "kembalian sudah diambil" — Sisa/Kembalian dihitung dari
/// `poolTersedia = prabayarTotal - changeTakenTotal`, BUKAN `prabayarTotal`
/// mentah (lihat dok `CartPrabayarNotifier.poolAvailable`) — begitu kasir
/// menyerahkan fisik kembalian yang SEDANG tampil & mencentang kotaknya,
/// nilai itu ditambahkan ke `changeTakenTotal` (via
/// `recordChangeTaken`) sehingga baris ini langsung recompute jadi Rp 0/
/// hilang; kalau nanti muncul kembalian baru (mis. barang dikurangi lagi),
/// baris ini muncul lagi dgn checkbox baru yang belum tercentang (checkbox
/// di sini SELALU tampil `value: false` — bukan penanda status permanen,
/// murni tombol aksi sekali-tap per kemunculan).
class _PrabayarFooterSummary extends ConsumerWidget {
  const _PrabayarFooterSummary({
    required this.cartId,
    required this.total,
    required this.prabayarTotal,
    required this.changeTakenTotal,
  });

  final String cartId;
  final int total;
  final int prabayarTotal;
  final int changeTakenTotal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pool = prabayarTotal - changeTakenTotal;
    final diff = total - pool;
    const baseStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Pra-Bayar ${formatRupiah(prabayarTotal)}',
          style: baseStyle,
          overflow: TextOverflow.ellipsis,
        ),
        if (diff > 0)
          Text(
            'Sisa ${formatRupiah(diff)}',
            style: baseStyle.copyWith(color: AppTheme.debtFg(isDark)),
            overflow: TextOverflow.ellipsis,
          )
        else if (diff < 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: false,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => ref
                      .read(cartPrabayarProvider(cartId).notifier)
                      .recordChangeTaken(-diff),
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Kembalian ${formatRupiah(-diff)}',
                  style: baseStyle.copyWith(color: AppTheme.changeFg(isDark)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Item 56 — ikon tombol Transfer: `qr_code_2` + panah kecil di pojok,
/// filosofi "kode QR yang dikirim/diteruskan" (bukan cuma ditampilkan).
class _QrTransferIcon extends StatelessWidget {
  const _QrTransferIcon();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.qr_code_2, size: 22, color: scheme.primary),
          Positioned(
            bottom: -3,
            right: -3,
            child: Icon(Icons.arrow_forward_rounded,
                size: 12, color: scheme.primary),
          ),
        ],
      ),
    );
  }
}
