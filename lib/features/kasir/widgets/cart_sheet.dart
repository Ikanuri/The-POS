import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_formatters.dart';
import '../cart_provider.dart';

class CartSheet extends ConsumerWidget {
  const CartSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final total = notifier.totalAmount;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
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
                Text('Keranjang',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: cart.isEmpty
                      ? null
                      : () {
                          notifier.clear();
                          Navigator.of(ctx).pop();
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
                            context.push('/kasir/bayar');
                          },
                    child: const Text('Bayar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemTile extends ConsumerWidget {
  const _CartItemTile({
    required this.index,
    required this.item,
    this.isVariant = false,
    required this.effectiveQty,
  });
  final int index;
  final CartItem item;
  final bool isVariant;
  final double effectiveQty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
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
        subtitle: Row(
          children: [
            Text(item.unitName,
                style:
                    TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
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
            _QtyField(item: item, effectiveQty: effectiveQty),
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
        onLongPress: () => _showItemOptions(context, ref),
      ),
    );
  }

  Future<void> _showItemOptions(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(cartProvider.notifier);
    final device = ref.read(deviceProvider);
    bool canOverrideHarga = device.deviceRole != 'kasir';
    if (!canOverrideHarga) {
      canOverrideHarga =
          await ref.read(databaseProvider).isPermissionEnabled('override_harga');
    }
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canOverrideHarga)
              ListTile(
                leading: const Icon(Icons.price_change_outlined),
                title: const Text('Ubah Harga'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showPriceEdit(context, ref);
                },
              ),
            ListTile(
              leading: const Icon(Icons.note_alt_outlined),
              title: const Text('Catatan Item'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showNoteEdit(context, ref);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text('Hapus', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () {
                Navigator.of(ctx).pop();
                notifier.removeItem(item.productUnitId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPriceEdit(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(
        text: ThousandsSeparatorFormatter.format(item.price));
    try {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ubah Harga'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: const [ThousandsSeparatorFormatter()],
            decoration: const InputDecoration(prefixText: 'Rp '),
          ),
          actions: [
            TextButton(
                onPressed: () => ctx.pop(),
                child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                final parsed = ThousandsSeparatorFormatter.parseValue(ctrl.text);
                final price = parsed > 0 ? parsed : item.price;
                ref.read(cartProvider.notifier).overridePrice(item.productUnitId, price);
                ctx.pop();
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _showNoteEdit(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: item.itemNote ?? '');
    try {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Catatan Item'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Contoh: tanpa saus'),
          ),
          actions: [
            TextButton(
                onPressed: () => ctx.pop(),
                child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                final note = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
                ref.read(cartProvider.notifier).setNote(item.productUnitId, note);
                ctx.pop();
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }
}

/// Qty yang bisa di-tap untuk inline edit. Tap → TextField kecil di tempat;
/// blur/submit → setEffectiveQty. Desain tombol ± di sekitarnya tidak berubah.
class _QtyField extends ConsumerStatefulWidget {
  const _QtyField({required this.item, required this.effectiveQty});
  final CartItem item;
  final double effectiveQty;

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
      ref.read(cartProvider.notifier)
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
