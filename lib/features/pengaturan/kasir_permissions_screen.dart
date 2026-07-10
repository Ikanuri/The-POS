import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';

/// Izin yang fiturnya BELUM ada di aplikasi (input pengeluaran & pembelian
/// supplier) — disembunyikan dari UI agar owner tidak menyalakan toggle yang
/// tidak berefek apa pun. Key-nya tetap di DB & tetap tersinkron, sehingga
/// begitu fiturnya dibangun tinggal dihapus dari daftar ini.
/// `input_pengeluaran` sudah punya UI (Item 9) → tidak lagi disembunyikan.
/// `input_pembelian` masih belum ada fiturnya.
const _kHiddenPermissionKeys = {'input_pembelian'};

final _kasirPermissionsProvider = StreamProvider<List<KasirPermission>>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .select(db.kasirPermissions)
      .watch()
      // Hanya izin role Kasir — izin asisten punya layar sendiri.
      .map((rows) => rows
          .where((p) =>
              kKasirPermissionKeys.contains(p.permissionKey) &&
              !_kHiddenPermissionKeys.contains(p.permissionKey))
          .toList());
});

/// Izinkan stok minus — setting global (bukan per-permission), tapi sekarang
/// dikelola di layar Izin Kasir agar tidak berserakan di halaman pengaturan.
final _allowNegativeStockProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final v = await db.getSetting('allow_negative_stock');
  return v == '1';
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
            const _AllowNegativeStockTile(),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

/// Toggle stok minus (setting global). Dipindah ke sini agar menyatu dengan
/// izin kasir lain — kasir bisa jual meski stok 0 (pre-order).
class _AllowNegativeStockTile extends ConsumerWidget {
  const _AllowNegativeStockTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allow = ref.watch(_allowNegativeStockProvider).valueOrNull ?? false;
    return SwitchListTile(
      title: const Text('Izinkan Stok Minus'),
      subtitle: Text('Kasir bisa jual meski stok 0 (pre-order)',
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      value: allow,
      onChanged: (v) async {
        final db = ref.read(databaseProvider);
        await db.setSetting('allow_negative_stock', v ? '1' : '0');
        ref.invalidate(_allowNegativeStockProvider);
      },
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
        'input_stok' => 'Input Stok',
        'tambah_pelanggan' => 'Tambah Pelanggan',
        'input_pengeluaran' => 'Input Pengeluaran',
        'input_pembelian' => 'Input Pembelian',
        'override_harga' => 'Override Harga',
        'batal_transaksi' => 'Batalkan Transaksi',
        _ => key,
      };

  String _desc(String key) => switch (key) {
        'input_stok' => 'Kasir bisa menambah stok produk',
        'tambah_pelanggan' => 'Kasir bisa mendaftarkan pelanggan baru',
        'input_pengeluaran' => 'Kasir bisa mencatat pengeluaran',
        'input_pembelian' => 'Kasir bisa mencatat pembelian dari supplier',
        'override_harga' => 'Kasir bisa mengubah harga di kasir',
        'batal_transaksi' => 'Kasir bisa membatalkan / void transaksi',
        _ => '',
      };
}
