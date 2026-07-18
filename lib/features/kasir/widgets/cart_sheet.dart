import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/services/order_parser_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/item_count_badge.dart';
import '../cart_meta_provider.dart';
import '../cart_provider.dart';
import 'add_control.dart';

/// Item 24d — true bila device INI perlu digerbang: role Pegawai
/// (`deviceRole == 'kasir'`) TANPA izin `terima_pembayaran`. Owner/Asisten
/// TIDAK PERNAH digerbang (selalu bisa Bayar langsung).
final _needsHandoffGateProvider = FutureProvider.autoDispose<bool>((ref) async {
  final device = ref.watch(deviceProvider);
  if (device.deviceRole != 'kasir') return false;
  final db = ref.watch(databaseProvider);
  return !(await db.isPermissionEnabled('terima_pembayaran'));
});

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

  /// Item 24d — pegawai tanpa izin `terima_pembayaran`: tombol "Bayar"
  /// beralih jadi QR berisi keranjang (format `#PSN:` + baris `Pegawai:`),
  /// sepenuhnya offline. Owner/asisten scan QR ini lewat scanner kasir yang
  /// sudah ada — hasilnya masuk ANTRIAN (`held_orders` awaitingPayment),
  /// BUKAN langsung ke keranjang aktif mereka (lihat PLAN.md Item 24d).
  Future<void> _showHandoffQr(
    BuildContext context,
    WidgetRef ref,
    List<CartItem> cart,
  ) async {
    final device = ref.read(deviceProvider);
    final meta = ref.read(cartMetaProvider(widget.cartId));
    final employeeName =
        meta.hasEmployee ? meta.employeeName! : device.deviceName;
    final qrText = OrderParserService.encodeHandoff(
      items: cart,
      employeeName: employeeName,
      customerName: meta.hasCustomer ? meta.customerName : null,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => _HandoffQrSheet(
        qrText: qrText,
        itemCount: cart.where((c) => !c.isVariant).length,
        total: cart.fold<int>(0, (s, c) => s + (c.price * c.qty).round()),
        // QR (bukan network) adalah SATU-SATUNYA jalur transport — antrian
        // `held_orders` ditulis di device OWNER saat MEREKA scan QR ini
        // (lihat `_handleOrderCode` di kasir_screen.dart), BUKAN di device
        // pegawai sendiri. Di sisi pegawai, "selesai" cuma berarti
        // membersihkan keranjang lokal (dianggap sudah terkirim/diserahkan).
        // Cuma tutup sheet QR-nya sendiri (bukan CartSheet di baliknya
        // sekalian) — dua pop beruntun di frame yang sama pernah bikin
        // animasi Navigator macet tak pernah selesai di widget test.
        onDone: () async {
          ref.read(cartProvider(widget.cartId).notifier).clear();
          ref.read(cartMetaProvider(widget.cartId).notifier).clear();
          if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider(widget.cartId));
    final notifier = ref.read(cartProvider(widget.cartId).notifier);
    final scheme = Theme.of(context).colorScheme;
    final total = notifier.totalAmount;
    // Item 24d — gerbang HANYA untuk transaksi nyata (kasir utama & Tambah
    // Belanjaan), TIDAK untuk mode Katalog (bukan transaksi sungguhan).
    final needsGate = widget.cartId != kCatalogCartId &&
        (ref.watch(_needsHandoffGateProvider).valueOrNull ?? false);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
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
                const Spacer(),
                TextButton(
                  onPressed: cart.isEmpty
                      ? null
                      : () async {
                          final ok = await showDialog<bool>(
                            context: ctx,
                            builder: (dCtx) => AlertDialog(
                              title: const Text('Kosongkan Keranjang?'),
                              content: const Text(
                                  'Semua item akan dihapus dari keranjang.'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.of(dCtx).pop(false),
                                    child: const Text('Batal')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.of(dCtx).pop(true),
                                    child: const Text('Kosongkan')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            notifier.clear();
                            ref
                                .read(cartMetaProvider(widget.cartId).notifier)
                                .clear();
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          }
                        },
                  child: const Text('Kosongkan'),
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
                ItemCountBadge(
                    count: cart.where((c) => !c.isVariant).length),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Total',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            )),
                    Text(
                      formatRupiah(total),
                      style: AppTheme.numStyle(context,
                          size: 22, weight: FontWeight.w700, color: scheme.primary),
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
                    child: Text(needsGate ? 'Kirim ke Owner/Asisten' : 'Bayar'),
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

class _CartItemTile extends ConsumerWidget {
  const _CartItemTile({
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
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider(cartId).notifier);
    final scheme = Theme.of(context).colorScheme;
    final isZeroed = !isVariant && effectiveQty == 0;
    final subtotal = (item.price * effectiveQty).round();

    return Opacity(
      opacity: isZeroed ? 0.45 : 1.0,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(left: isVariant ? 32 : 8, right: 4),
        // Checklist verifikasi barang sebelum bayar — independen dari tap
        // baris (yang membuka modal edit). Leading widget eksplisit (bukan
        // CheckboxListTile) supaya kedua gesture ini tidak tumpang tindih.
        leading: Checkbox(
          value: item.checked,
          onChanged: (v) =>
              notifier.setChecked(item.productUnitId, v ?? false),
        ),
        title: Row(
          children: [
            if (isVariant)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.subdirectory_arrow_right,
                    size: 15, color: scheme.onSurfaceVariant),
              ),
            Expanded(
              child: Text(item.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: isVariant ? 15 : 17,
                      color: isVariant ? scheme.onSurfaceVariant : null)),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant),
                      children: [
                        TextSpan(text: '${item.unitName} · '),
                        TextSpan(
                            text: formatRupiah(item.price),
                            style: AppTheme.numStyle(context,
                                size: 13, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.priceOverridden) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 12, color: scheme.tertiary),
                ],
                if (isZeroed) ...[
                  const SizedBox(width: 4),
                  Text('via varian',
                      style: TextStyle(fontSize: 12, color: scheme.primary)),
                ],
              ],
            ),
            if (item.itemNote != null && item.itemNote!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 3, 6, 3),
                  decoration: BoxDecoration(
                    border: Border(
                        left: BorderSide(
                            width: 3,
                            color: scheme.tertiary.withOpacity(0.5))),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Item 4 (usulan user) — stepper disamakan persis dgn gaya
            // stepper produk di halaman kasir (`AddControl`, shared widget),
            // menggantikan tombol ±/field qty lama.
            AddControl(
              qty: effectiveQty,
              size: 30,
              onTap: () => notifier.setEffectiveQty(
                  item.productUnitId, effectiveQty + 1),
              onMinus: isZeroed
                  ? null
                  : () => notifier.setEffectiveQty(
                      item.productUnitId, effectiveQty - 1),
            ),
            const SizedBox(width: 8),
            Text(
              formatRupiah(subtotal),
              style: AppTheme.numStyle(context,
                  size: 15,
                  weight: FontWeight.w600,
                  color: isZeroed ? scheme.onSurfaceVariant : scheme.primary),
            ),
          ],
        ),
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
      ),
    );
  }
}

/// Item 24d — QR handoff pesanan pegawai. `onDone` dipanggil saat pegawai
/// menandai sudah menunjukkan/discan owner — barulah keranjang lokal
/// dibersihkan (bukan otomatis saat sheet dibuka, supaya QR tetap bisa
/// ditunjukkan ulang kalau scan pertama gagal).
class _HandoffQrSheet extends StatelessWidget {
  const _HandoffQrSheet({
    required this.qrText,
    required this.itemCount,
    required this.total,
    required this.onDone,
  });

  final String qrText;
  final int itemCount;
  final int total;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Kirim ke Owner/Asisten',
                style: Theme.of(context).textTheme.titleMedium),
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
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: onDone,
                child: const Text('Sudah Dikirim, Kosongkan Keranjang'),
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
