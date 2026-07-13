import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/services/order_parser_service.dart';
import '../../../core/services/price_service.dart';
import '../../../core/theme/app_theme.dart';
import '../cart_meta_provider.dart';
import '../cart_provider.dart';

/// Sheet "Tempel Pesanan": kasir menempel teks pesanan yang dikirim balik
/// pelanggan (hasil Katalog Pesanan, lihat `OrderPageService`) lalu semua
/// item otomatis masuk keranjang kasir.
///
/// Harga & HPP SELALU di-resolve ulang dari DB lokal saat ini (lihat
/// [OrderParserService]) — bukan dipercaya dari teks — jadi katalog yang
/// sedikit basi tidak pernah membuat transaksi salah hitung.
class PasteOrderSheet extends ConsumerStatefulWidget {
  const PasteOrderSheet({super.key, this.cartId = kMainCartId, this.initialText});

  final String cartId;

  /// Item 24d — bila terisi (mis. hasil scan QR pesanan pelanggan), field
  /// teks pra-diisi & langsung diproses otomatis begitu sheet dibuka, tanpa
  /// perlu kasir tempel manual.
  final String? initialText;

  @override
  ConsumerState<PasteOrderSheet> createState() => _PasteOrderSheetState();
}

class _PasteOrderSheetState extends ConsumerState<PasteOrderSheet> {
  late final _textCtrl = TextEditingController(text: widget.initialText);
  ParsedOrder? _result;
  bool _processing = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _process());
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _process() async {
    final text = _textCtrl.text;
    if (text.trim().isEmpty) return;
    setState(() => _processing = true);
    final db = ref.read(databaseProvider);
    final result = await OrderParserService.parse(db: db, text: text);
    if (mounted) {
      setState(() {
        _result = result;
        _processing = false;
      });
    }
  }

  /// Sama seperti `_ensureParentInCart` di layar kasir utama (dijaga sengaja
  /// TIDAK dibagi/impor dari sana). Jaga invariant storedQty induk =
  /// base + Σvarian dengan menambahkan placeholder qty 0 untuk induk yang
  /// belum ada di keranjang sebelum varian ditambahkan.
  Future<void> _ensureParentInCart(ParsedOrderItem variantItem) async {
    if (!variantItem.isVariant || variantItem.parentProductId == null) return;
    final cart = ref.read(cartProvider(widget.cartId));
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

    ref.read(cartProvider(widget.cartId).notifier).addItem(CartItem(
          productId: parent.id,
          productUnitId: base.id,
          productName: parent.name,
          unitName: unitType?.name ?? 'Satuan',
          qty: 0,
          price: resolved.price,
          originalPrice: resolved.price,
          costPrice: resolved.costPrice,
        ));
  }

  Future<void> _addToCart() async {
    final result = _result;
    if (result == null || result.items.isEmpty || _adding) return;
    setState(() => _adding = true);

    final notifier = ref.read(cartProvider(widget.cartId).notifier);
    // Induk dulu (agar placeholder siap) baru varian, sesuai urutan yang
    // dipakai _ensureParentInCart di alur kasir biasa.
    for (final item in result.items.where((i) => !i.isVariant)) {
      notifier.addItem(item.toCartItem());
    }
    for (final item in result.items.where((i) => i.isVariant)) {
      await _ensureParentInCart(item);
      if (!mounted) return;
      ref.read(cartProvider(widget.cartId).notifier).addItem(item.toCartItem());
    }

    // Nama pelanggan (bila ada) pra-isi ke metadata keranjang — sama seperti
    // pola pelanggan ad-hoc bernama tanpa record terdaftar. Nomor HP &
    // catatan sengaja tidak ada tempatnya di metadata keranjang saat ini,
    // ditampilkan di preview saja untuk referensi kasir.
    if (result.customerName != null) {
      ref
          .read(cartMetaProvider(widget.cartId).notifier)
          .setCustomer(null, result.customerName);
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = _result;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
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
                  Text('Tempel Pesanan',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Tempel teks pesanan yang dikirim pelanggan dari '
                    'Katalog Pesanan.',
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _textCtrl,
                    maxLines: 6,
                    minLines: 4,
                    decoration: InputDecoration(
                      hintText: 'PESANAN — Toko Anda\n…\n#PSN:...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _processing ? null : _process,
                      icon: _processing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.playlist_add_check, size: 18),
                      label:
                          Text(_processing ? 'Memproses…' : 'Proses Pesanan'),
                    ),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 16),
                    if (!result.hasMachineCode)
                      _WarnBanner(
                        icon: Icons.error_outline,
                        color: scheme.error,
                        text: 'Teks ini tidak mengandung kode pesanan '
                            '(baris "#PSN:..."). Pastikan ditempel utuh dari '
                            'hasil "Kirim via WhatsApp" / "Salin Teks Pesanan" '
                            'di Katalog Pesanan.',
                      )
                    else ...[
                      if (result.customerName != null ||
                          result.customerPhone != null ||
                          result.note != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (result.customerName != null)
                                Text('Nama: ${result.customerName}',
                                    style: const TextStyle(fontSize: 12.5)),
                              if (result.customerPhone != null)
                                Text('HP: ${result.customerPhone}',
                                    style: const TextStyle(fontSize: 12.5)),
                              if (result.note != null)
                                Text('Catatan: ${result.note}',
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                      if (result.items.isEmpty && result.notFound.isEmpty)
                        _WarnBanner(
                          icon: Icons.info_outline,
                          color: scheme.onSurfaceVariant,
                          text: 'Tidak ada barang di pesanan ini.',
                        ),
                      ...result.items.map((item) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.check_circle,
                                size: 18, color: scheme.primary),
                            title: Text(item.productName,
                                style: const TextStyle(fontSize: 13.5)),
                            subtitle: Text(
                                '${item.qty % 1 == 0 ? item.qty.toInt() : item.qty} '
                                '${item.unitName} × ${formatRupiah(item.price)}',
                                style: const TextStyle(fontSize: 11.5)),
                            trailing: Text(formatRupiah(item.subtotal),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          )),
                      if (result.notFound.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _WarnBanner(
                            icon: Icons.warning_amber_rounded,
                            color: scheme.error,
                            text:
                                '${result.notFound.length} barang tidak ditemukan '
                                '(mungkin sudah dihapus/dinonaktifkan sejak '
                                'katalog dibuat) — dilewati, barang lain tetap '
                                'masuk keranjang.',
                          ),
                        ),
                      if (result.items.isNotEmpty) ...[
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            Text(formatRupiah(result.total),
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.primary,
                                    fontSize: 16)),
                          ],
                        ),
                      ],
                    ],
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
            if (result != null && result.items.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, MediaQuery.of(context).padding.bottom + 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _adding ? null : _addToCart,
                    child: Text(_adding
                        ? 'Menambahkan…'
                        : 'Masukkan ${result.items.length} Barang ke Keranjang'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WarnBanner extends StatelessWidget {
  const _WarnBanner(
      {required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, style: TextStyle(fontSize: 12, color: color))),
        ],
      ),
    );
  }
}
