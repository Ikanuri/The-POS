import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
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
                : ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: cart.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 56),
                    itemBuilder: (ctx2, i) =>
                        _CartItemTile(index: i, item: cart[i]),
                  ),
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
  const _CartItemTile({required this.index, required this.item});
  final int index;
  final CartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      dense: true,
      title: Text(item.productName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Text(item.unitName,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          if (item.priceOverridden) ...[
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 10, color: scheme.tertiary),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: () => notifier.setQty(
                item.productUnitId, item.qty - 1),
          ),
          SizedBox(
            width: 32,
            child: Text(
              item.qty % 1 == 0
                  ? item.qty.toInt().toString()
                  : item.qty.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: () => notifier.setQty(
                item.productUnitId, item.qty + 1),
          ),
          const SizedBox(width: 4),
          Text(
            formatRupiah(item.subtotal),
            style: TextStyle(
                color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
      onLongPress: () => _showItemOptions(context, ref),
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
                notifier.removeItemByIndex(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPriceEdit(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController(text: item.price.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah Harga'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(prefixText: 'Rp '),
        ),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              final price = int.tryParse(ctrl.text) ?? item.price;
              ref.read(cartProvider.notifier).overridePrice(index, price);
              ctx.pop();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showNoteEdit(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController(text: item.itemNote ?? '');
    showDialog(
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
              ref.read(cartProvider.notifier).setNote(index, note);
              ctx.pop();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
