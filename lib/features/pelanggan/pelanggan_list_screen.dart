import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';

final _pelangganQueryProvider = StateProvider<String>((ref) => '');

final _canAddCustomerProvider = FutureProvider.autoDispose<bool>((ref) async {
  final device = ref.watch(deviceProvider);
  if (device.isOwner || device.deviceRole == 'asisten') return true;
  if (device.deviceRole != 'kasir') return false;
  return ref.watch(databaseProvider).isPermissionEnabled('tambah_pelanggan');
});

final _pelangganStreamProvider =
    StreamProvider.family<List<Customer>, String>((ref, query) {
  final db = ref.watch(databaseProvider);
  return db.watchCustomers(query: query);
});

class PelangganListScreen extends ConsumerStatefulWidget {
  const PelangganListScreen({super.key});

  @override
  ConsumerState<PelangganListScreen> createState() =>
      _PelangganListScreenState();
}

class _PelangganListScreenState extends ConsumerState<PelangganListScreen> {
  static const _itemExtent = 68.0;
  final _scrollCtrl = ScrollController();
  String? _activeLetter; // huruf yang sedang dipilih di index slider

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _firstLetter(String name) {
    if (name.isEmpty) return '#';
    final c = name[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
  }

  void _jumpToLetter(String letter, List<Customer> customers) {
    // Cari index pertama yang first-letter-nya == letter (atau >= untuk '#').
    int target = -1;
    for (var i = 0; i < customers.length; i++) {
      if (_firstLetter(customers[i].name) == letter) {
        target = i;
        break;
      }
    }
    if (target < 0 || !_scrollCtrl.hasClients) return;
    final offset = (target * _itemExtent)
        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.jumpTo(offset);
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(deviceProvider);
    final query = ref.watch(_pelangganQueryProvider);
    final customersAsync = ref.watch(_pelangganStreamProvider(query));
    final canEdit = device.isOwner || device.deviceRole == 'asisten';
    final canAdd = ref.watch(_canAddCustomerProvider).valueOrNull ?? canEdit;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pelanggan'),
        actions: [
          if (canAdd)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Tambah Pelanggan',
              onPressed: () => context.push('/pelanggan/baru'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Cari nama pelanggan…',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => ref
                            .read(_pelangganQueryProvider.notifier)
                            .state = '',
                      )
                    : null,
              ),
              onChanged: (v) =>
                  ref.read(_pelangganQueryProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: customersAsync.when(
              data: (customers) {
                if (customers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline,
                            size: 64, color: scheme.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          query.isEmpty
                              ? 'Belum ada pelanggan'
                              : 'Pelanggan tidak ditemukan',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                        if (canAdd && query.isEmpty) ...[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => context.push('/pelanggan/baru'),
                            icon: const Icon(Icons.add),
                            label: const Text('Tambah Pelanggan'),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                // Slider A-Z hanya berguna bila daftar cukup panjang & tidak
                // sedang difilter pencarian.
                final showIndex = customers.length > 12 && query.isEmpty;

                return Stack(
                  children: [
                    ListView.builder(
                      controller: _scrollCtrl,
                      itemExtent: _itemExtent,
                      padding: EdgeInsets.only(right: showIndex ? 20 : 0),
                      itemCount: customers.length,
                      itemBuilder: (_, i) => _CustomerTile(
                        customer: customers[i],
                        canEdit: canEdit,
                      ),
                    ),
                    if (showIndex)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        child: _AlphabetIndex(
                          onSelect: (letter) {
                            setState(() => _activeLetter = letter);
                            _jumpToLetter(letter, customers);
                          },
                          onEnd: () =>
                              setState(() => _activeLetter = null),
                        ),
                      ),
                    if (_activeLetter != null)
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: scheme.primary.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _activeLetter!,
                            style: TextStyle(
                                color: scheme.onPrimary,
                                fontSize: 34,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Index huruf A-Z di tepi kanan. Sentuh / seret untuk lompat ke huruf.
class _AlphabetIndex extends StatelessWidget {
  const _AlphabetIndex({required this.onSelect, required this.onEnd});

  final ValueChanged<String> onSelect;
  final VoidCallback onEnd;

  static const _letters = [
    'A','B','C','D','E','F','G','H','I','J','K','L','M',
    'N','O','P','Q','R','S','T','U','V','W','X','Y','Z','#',
  ];

  void _handle(Offset localPos, BoxConstraints c) {
    final h = c.maxHeight / _letters.length;
    final idx = (localPos.dy / h).floor().clamp(0, _letters.length - 1);
    onSelect(_letters[idx]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) =>
              _handle(d.localPosition, constraints),
          onVerticalDragUpdate: (d) =>
              _handle(d.localPosition, constraints),
          onVerticalDragEnd: (_) => onEnd(),
          onTapDown: (d) => _handle(d.localPosition, constraints),
          onTapUp: (_) => onEnd(),
          child: Container(
            width: 20,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final l in _letters)
                  Text(
                    l,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CustomerTile extends ConsumerWidget {
  const _CustomerTile({required this.customer, required this.canEdit});
  final Customer customer;
  final bool canEdit;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final hasDebt = customer.outstandingDebt > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Pelanggan'),
        content: Text(hasDebt
            ? '"${customer.name}" masih punya hutang '
                '${formatRupiah(customer.outstandingDebt)}. Tetap hapus dari daftar?'
            : 'Hapus "${customer.name}" dari daftar? Riwayat transaksi tetap tersimpan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(databaseProvider).deactivateCustomer(customer.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pelanggan "${customer.name}" dihapus')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final debtLabel = customer.outstandingDebt > 0
        ? 'Utang: ${formatRupiah(customer.outstandingDebt)}'
        : null;

    final tile = ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(
          customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
          style: TextStyle(
              color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(customer.name,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          if (customer.phone != null)
            Text(customer.phone!,
                style:
                    TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          if (customer.loyaltyPoints > 0) ...[
            const SizedBox(width: 8),
            Icon(Icons.star, size: 10, color: scheme.tertiary),
            Text(' ${customer.loyaltyPoints} poin',
                style: TextStyle(fontSize: 11, color: scheme.tertiary)),
          ],
          if (debtLabel != null) ...[
            const SizedBox(width: 8),
            Text(debtLabel,
                style: TextStyle(fontSize: 11, color: scheme.error)),
          ],
        ],
      ),
      trailing: canEdit
          ? IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => context.push('/pelanggan/${customer.id}'),
            )
          : null,
      onTap: () => context.push('/pelanggan/${customer.id}'),
    );

    if (!canEdit) return tile;

    // Geser ke kiri untuk hapus.
    return Dismissible(
      key: ValueKey(customer.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _confirmDelete(context, ref);
        return false; // stream akan memperbarui daftar sendiri
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      child: tile,
    );
  }
}
