import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';

final _kasirPermissionsProvider = StreamProvider<List<KasirPermission>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.kasirPermissions).watch();
});

class KasirPermissionsScreen extends ConsumerWidget {
  const KasirPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permsAsync = ref.watch(_kasirPermissionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Izin Kasir')),
      body: permsAsync.when(
        data: (perms) => ListView(
          padding: const EdgeInsets.all(8),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Izin ini berlaku untuk device dengan role Kasir. '
                  'Owner dan Asisten selalu punya akses penuh.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...perms.map((p) => _PermissionTile(permission: p)),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _PermissionTile extends ConsumerWidget {
  const _PermissionTile({required this.permission});
  final KasirPermission permission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      title: Text(_label(permission.permissionKey)),
      subtitle: Text(_desc(permission.permissionKey),
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      value: permission.isEnabled,
      onChanged: (v) async {
        final db = ref.read(databaseProvider);
        await (db.update(db.kasirPermissions)
              ..where((t) => t.permissionKey.equals(permission.permissionKey)))
            .write(KasirPermissionsCompanion(isEnabled: Value(v)));
      },
    );
  }

  String _label(String key) => switch (key) {
        'input_stok' => 'Input Stok',
        'tambah_pelanggan' => 'Tambah Pelanggan',
        'input_pengeluaran' => 'Input Pengeluaran',
        'input_pembelian' => 'Input Pembelian',
        'override_harga' => 'Override Harga',
        _ => key,
      };

  String _desc(String key) => switch (key) {
        'input_stok' => 'Kasir bisa menambah stok produk',
        'tambah_pelanggan' => 'Kasir bisa mendaftarkan pelanggan baru',
        'input_pengeluaran' => 'Kasir bisa mencatat pengeluaran',
        'input_pembelian' => 'Kasir bisa mencatat pembelian dari supplier',
        'override_harga' => 'Kasir bisa mengubah harga di kasir',
        _ => '',
      };
}
