import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/cart_item.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../cart_provider.dart';

const _heldUuid = Uuid();

final _heldOrdersProvider = StreamProvider<List<HeldOrder>>((ref) {
  return ref.watch(databaseProvider).watchHeldOrders();
});

/// Sheet pesanan ditahan: tahan keranjang aktif, lanjutkan / hapus
/// pesanan yang ditahan sebelumnya.
class HeldOrdersSheet extends ConsumerWidget {
  const HeldOrdersSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heldAsync = ref.watch(_heldOrdersProvider);
    final cart = ref.watch(cartProvider);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              cart.isNotEmpty
                  ? 'Tahan atau lanjutkan pesanan'
                  : 'Pesanan Ditahan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (cart.isNotEmpty) ...[
              FilledButton.tonalIcon(
                onPressed: () => _holdCurrent(context, ref),
                icon: const Icon(Icons.pause),
                label: Text(
                    'Tahan Sekarang (${cart.length} item · ${formatRupiah(ref.read(cartProvider.notifier).totalAmount)})'),
              ),
              const SizedBox(height: 12),
            ],
            heldAsync.when(
              data: (held) {
                if (held.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Tidak ada pesanan ditahan.',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                  );
                }
                return ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.45),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: held.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) =>
                        _HeldTile(order: held[i]),
                  ),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _holdCurrent(BuildContext context, WidgetRef ref) async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    final labelCtrl = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tahan Pesanan'),
        content: TextField(
          controller: labelCtrl,
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
                labelCtrl.text.trim().isEmpty
                    ? 'Pesanan'
                    : labelCtrl.text.trim()),
            child: const Text('Tahan'),
          ),
        ],
      ),
    );
    if (label == null) return;

    final db = ref.read(databaseProvider);
    await db.holdOrder(
      id: _heldUuid.v4(),
      label: label,
      cartJson: jsonEncode(cart.map((c) => c.toJson()).toList()),
    );
    ref.read(cartProvider.notifier).clear();
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pesanan "$label" ditahan')),
      );
    }
  }
}

class _HeldTile extends ConsumerWidget {
  const _HeldTile({required this.order});
  final HeldOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final items = _parseItems(order.cartJson);
    final total = items.fold<int>(0, (s, c) => s + c.subtotal);
    final time =
        '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Icon(Icons.pause, color: scheme.onPrimaryContainer, size: 20),
      ),
      title: Text(order.label),
      subtitle: Text('${items.length} item · $time',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatRupiah(total),
              style: TextStyle(
                  color: scheme.primary, fontWeight: FontWeight.w600)),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: scheme.error),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      onTap: () => _resume(context, ref, items),
    );
  }

  List<CartItem> _parseItems(String json) {
    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _resume(
      BuildContext context, WidgetRef ref, List<CartItem> items) async {
    final cart = ref.read(cartProvider);
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
    if (!context.mounted) return;

    ref.read(cartProvider.notifier).replaceAll(items);
    await ref.read(databaseProvider).deleteHeldOrder(order.id);
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Melanjutkan: ${order.label}')),
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Pesanan Ditahan?'),
        content: Text('"${order.label}" akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await ref.read(databaseProvider).deleteHeldOrder(order.id);
    }
  }
}
