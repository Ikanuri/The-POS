import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/order_parser_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/item_count_badge.dart';
import '../cart_meta_provider.dart';
import '../cart_provider.dart';
import '../handoff_gate_provider.dart';
import 'add_control.dart';
import 'paste_order_sheet.dart';

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
    final qrText = OrderParserService.encodeHandoff(
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
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HandoffQrSheet(
        // Judul beda konteks: pegawai TANPA izin SELALU melempar ke
        // owner/asisten (satu arah pasti); transfer bebas (Item 56) bisa
        // ke device manapun, judul generik.
        title: needsGate ? 'Kirim ke Owner/Asisten' : 'Transfer Transaksi',
        qrText: qrText,
        itemCount: cart.where((c) => !c.isVariant).length,
        total: cart.fold<int>(0, (s, c) => s + (c.price * c.qty).round()),
      ),
    );
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
    if (ctx.mounted) Navigator.of(ctx).pop();
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
                    subtitle: const Text(
                        'Tap pertama tombol minus cuma bergetar sbg '
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
                  const Spacer(),
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
                        builder: (_) => PasteOrderSheet(cartId: widget.cartId),
                      ),
                      icon: const Icon(Icons.content_paste_go),
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
            const Divider(height: 1),
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
                children: [
                  // Badge jumlah item — gaya sama dgn cart bar kasir, supaya
                  // representasi "jumlah barang" konsisten di seluruh alur.
                  ItemCountBadge(count: cart.where((c) => !c.isVariant).length),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Total',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  )),
                      Text(
                        formatRupiah(total),
                        style: AppTheme.numStyle(context,
                            size: 22,
                            weight: FontWeight.w700,
                            color: scheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
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
                    size: 30,
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
    required this.qrText,
    required this.itemCount,
    required this.total,
  });

  final String title;
  final String qrText;
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
              child: QrImageView(data: qrText, size: 220),
            ),
            const SizedBox(height: 12),
            Text(
              'Minta owner/asisten scan QR ini lewat scanner kasir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 10),
            // Jalur cadangan kalau scan QR susah (kamera rusak/pencahayaan
            // kurang) — teks pesanan yang SAMA persis dgn isi QR bisa
            // ditempel manual lewat WhatsApp/Telegram, lalu owner buka
            // "Tempel Pesanan" di kasir (parser sudah baca format ini).
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: qrText));
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
                onPressed: () => Share.share(qrText),
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
