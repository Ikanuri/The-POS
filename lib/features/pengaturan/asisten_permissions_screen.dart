import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';

final _asistenPermissionsProvider =
    StreamProvider<List<KasirPermission>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.kasirPermissions).watch().map((rows) => rows
      .where((p) => kAsistenPermissionKeys.contains(p.permissionKey))
      .toList());
});

class AsistenPermissionsScreen extends ConsumerWidget {
  const AsistenPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permsAsync = ref.watch(_asistenPermissionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Izin Asisten')),
      body: permsAsync.when(
        data: (perms) => ListView(
          padding: const EdgeInsets.all(8),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Izin ini berlaku untuk device dengan role Asisten. Selain '
                  'yang diatur di sini, Asisten tetap punya akses penuh.',
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
            .write(KasirPermissionsCompanion(
          isEnabled: Value(v),
          updatedAt: Value(DateTime.now()),
        ));
      },
    );
  }

  String _label(String key) => switch (key) {
        'asisten_stok_minus' => 'Izinkan Stok Minus',
        _ => key,
      };

  String _desc(String key) => switch (key) {
        'asisten_stok_minus' =>
          'Asisten bisa menjual meski stok 0 (override stok minus)',
        _ => '',
      };
}
