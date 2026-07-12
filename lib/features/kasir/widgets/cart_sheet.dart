import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/theme/app_theme.dart';
import '../cart_meta_provider.dart';
import '../cart_provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider(widget.cartId));
    final notifier = ref.read(cartProvider(widget.cartId).notifier);
    final scheme = Theme.of(context).colorScheme;
    final total = notifier.totalAmount;

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
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : Builder(builder: (_) {
                    final ordered = orderCartItems(cart);
                    return ListView.separated(
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
                    );
                  }),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 12),
            child: Row(
              children: [
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
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: cart.isEmpty
                        ? null
                        : () {
                            Navigator.of(ctx).pop();
                            context.push(widget.payRoute);
                          },
                    child: const Text('Bayar'),
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
        contentPadding: EdgeInsets.only(left: isVariant ? 32 : 16, right: 4),
        title: Row(
          children: [
            if (isVariant)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.subdirectory_arrow_right,
                    size: 14, color: scheme.onSurfaceVariant),
              ),
            Expanded(
              child: Text(item.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: isVariant ? 13 : null,
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
                  child: Text('${item.unitName} · ${formatRupiah(item.price)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ),
                if (item.priceOverridden) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 10, color: scheme.tertiary),
                ],
                if (isZeroed) ...[
                  const SizedBox(width: 4),
                  Text('via varian',
                      style: TextStyle(fontSize: 10, color: scheme.primary)),
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
                        fontSize: 11,
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
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: isZeroed
                  ? null
                  : () => notifier.setEffectiveQty(
                      item.productUnitId, effectiveQty - 1),
            ),
            _QtyField(item: item, effectiveQty: effectiveQty, cartId: cartId),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: () => notifier.setEffectiveQty(
                  item.productUnitId, effectiveQty + 1),
            ),
            const SizedBox(width: 4),
            Text(
              formatRupiah(subtotal),
              style: TextStyle(
                  color: isZeroed
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
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

/// Qty yang bisa di-tap untuk inline edit. Tap → TextField kecil di tempat;
/// blur/submit → setEffectiveQty. Desain tombol ± di sekitarnya tidak berubah.
class _QtyField extends ConsumerStatefulWidget {
  const _QtyField({
    required this.item,
    required this.effectiveQty,
    required this.cartId,
  });
  final CartItem item;
  final double effectiveQty;
  final String cartId;

  @override
  ConsumerState<_QtyField> createState() => _QtyFieldState();
}

class _QtyFieldState extends ConsumerState<_QtyField> {
  bool _editing = false;
  late final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _fmt(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toString();

  void _startEdit() {
    setState(() {
      _editing = true;
      _ctrl.text = _fmt(widget.effectiveQty);
      _ctrl.selection =
          TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
    });
    _focus.requestFocus();
  }

  void _commit() {
    final parsed = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    if (parsed != null) {
      ref.read(cartProvider(widget.cartId).notifier)
          .setEffectiveQty(widget.item.productUnitId, parsed);
    }
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return SizedBox(
        width: 48,
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          autofocus: true,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 4),
          ),
          style: const TextStyle(fontWeight: FontWeight.w600),
          onSubmitted: (_) => _commit(),
        ),
      );
    }
    return GestureDetector(
      onTap: _startEdit,
      child: SizedBox(
        width: 32,
        child: Text(
          _fmt(widget.effectiveQty),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
