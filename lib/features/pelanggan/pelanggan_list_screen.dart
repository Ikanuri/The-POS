import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';

final _pelangganQueryProvider = StateProvider<String>((ref) => '');

final _pelangganStreamProvider =
    StreamProvider.family<List<Customer>, String>((ref, query) {
  final db = ref.watch(databaseProvider);
  return db.watchCustomers(query: query);
});

class PelangganListScreen extends ConsumerWidget {
  const PelangganListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider);
    final query = ref.watch(_pelangganQueryProvider);
    final customersAsync = ref.watch(_pelangganStreamProvider(query));
    final canEdit = device.isOwner || device.deviceRole == 'asisten';
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pelanggan'),
        actions: [
          if (canEdit)
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
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        if (canEdit && query.isEmpty) ...[
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
                return ListView.separated(
                  itemCount: customers.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 60),
                  itemBuilder: (_, i) =>
                      _CustomerTile(customer: customers[i], canEdit: canEdit),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile(
      {required this.customer, required this.canEdit});
  final Customer customer;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final debtLabel = customer.outstandingDebt > 0
        ? 'Utang: ${formatRupiah(customer.outstandingDebt)}'
        : null;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(
          customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
          style: TextStyle(
              color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(customer.name),
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
                style:
                    TextStyle(fontSize: 11, color: scheme.error)),
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
  }
}
