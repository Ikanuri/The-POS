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

class KasirPermissionsScreen extends ConsumerWidget {
  const KasirPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permsAsync = ref.watch(_kasirPermissionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Izin Pegawai')),
      body: permsAsync.when(
        data: (perms) => ListView(
          padding: const EdgeInsets.all(8),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Izin ini berlaku untuk device dengan role Pegawai. '
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
        'terima_pembayaran' => 'Terima Pembayaran',
        _ => key,
      };

  String _desc(String key) => switch (key) {
        'input_stok' => 'Pegawai bisa menambah stok produk',
        'tambah_pelanggan' => 'Pegawai bisa mendaftarkan pelanggan baru',
        'input_pengeluaran' => 'Pegawai bisa mencatat pengeluaran',
        'input_pembelian' => 'Pegawai bisa mencatat pembelian dari supplier',
        'override_harga' => 'Pegawai bisa mengubah harga di kasir',
        'batal_transaksi' => 'Pegawai bisa membatalkan / void transaksi',
        'terima_pembayaran' =>
          'Pegawai bisa terima uang & selesaikan pembayaran sendiri. '
              'Kalau OFF, tombol "Bayar" berubah jadi "Kirim ke Owner/Asisten".',
        _ => '',
      };
}
