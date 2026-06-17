import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/device_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/input_formatters.dart';

const _thousandsFmt = ThousandsSeparatorFormatter();

final _allowNegativeStockProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final v = await db.getSetting('allow_negative_stock');
  return v == '1';
});

/// Aturan poin loyalitas: setiap belanja [threshold] rupiah → dapat [pointsPer]
/// poin. threshold = 0 menonaktifkan poin otomatis.
final loyaltyRuleProvider =
    FutureProvider<({int threshold, int pointsPer})>((ref) async {
  final db = ref.watch(databaseProvider);
  final t = int.tryParse(await db.getSetting('loyalty_point_threshold') ?? '') ?? 0;
  final p = int.tryParse(await db.getSetting('loyalty_points_per') ?? '') ?? 1;
  return (threshold: t, pointsPer: p < 1 ? 1 : p);
});

class PengaturanScreen extends ConsumerWidget {
  const PengaturanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider);
    final themeMode = ref.watch(themeModeProvider);
    final allowNegStock = ref.watch(_allowNegativeStockProvider).valueOrNull ?? false;
    final scheme = Theme.of(context).colorScheme;

    String roleLabel(String role) => switch (role) {
          'owner' => 'Owner',
          'asisten' => 'Asisten',
          'kasir' => 'Kasir',
          _ => role,
        };

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader('Device Ini'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primary.withOpacity(0.14),
                    child: Text(
                      device.deviceCode.isEmpty ? '?' : device.deviceCode,
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  title: Text(device.deviceName),
                  subtitle: Text(
                      '${roleLabel(device.deviceRole)} · ${device.storeName}'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const _SectionHeader('Toko'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.store_outlined),
                  title: const Text('Informasi Toko'),
                  subtitle: const Text('Nama, alamat, telepon, catatan struk'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pengaturan/toko'),
                ),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Metode Pembayaran'),
                  subtitle: const Text('QRIS, transfer bank, e-wallet'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pengaturan/metode-bayar'),
                ),
                if (device.isOwner) ...[
                  ListTile(
                    leading: const Icon(Icons.tune_outlined),
                    title: const Text('Izin Kasir'),
                    subtitle: const Text('Override harga, input stok, dll'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pengaturan/izin-kasir'),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.remove_shopping_cart_outlined),
                    title: const Text('Izinkan Stok Minus'),
                    subtitle: const Text('Kasir bisa jual meski stok 0 (pre-order)'),
                    value: allowNegStock,
                    onChanged: (v) async {
                      final db = ref.read(databaseProvider);
                      await db.setSetting('allow_negative_stock', v ? '1' : '0');
                      ref.invalidate(_allowNegativeStockProvider);
                    },
                  ),
                  Builder(builder: (context) {
                    final rule =
                        ref.watch(loyaltyRuleProvider).valueOrNull;
                    final subtitle = rule == null || rule.threshold <= 0
                        ? 'Nonaktif — ketuk untuk mengatur'
                        : 'Setiap belanja ${formatRupiah(rule.threshold)} '
                            '→ ${rule.pointsPer} poin';
                    return ListTile(
                      leading: const Icon(Icons.stars_outlined),
                      title: const Text('Poin Loyalitas'),
                      subtitle: Text(subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showLoyaltyDialog(context, ref),
                    );
                  }),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          const _SectionHeader('Sinkronisasi'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.wifi_outlined),
                  title: const Text('Sync WiFi'),
                  subtitle: const Text('Sinkronisasi antar HP via jaringan lokal'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pengaturan/sync'),
                ),
                ListTile(
                  leading: const Icon(Icons.save_alt_outlined),
                  title: const Text('Backup & Restore'),
                  subtitle: const Text('File terenkripsi .berkahpos'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pengaturan/backup'),
                ),
                if (device.isOwner) ...[
                  ListTile(
                    leading: const Icon(Icons.upload_file_outlined),
                    title: const Text('Import Produk CSV'),
                    subtitle: const Text('Impor daftar produk dari file CSV'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pengaturan/import-csv'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.qr_code_2_outlined),
                    title: const Text('Pair Device Baru'),
                    subtitle: const Text('Tambah HP kasir / asisten via QR'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pengaturan/pair'),
                  ),
                ],
              ],
            ),
          ),
          if (device.isOwner) ...[
            const SizedBox(height: 8),
            const _SectionHeader('Manajemen Data'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: const Text('Tutup Buku'),
                    subtitle: const Text('Arsipkan transaksi tahun lalu'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pengaturan/tutup-buku'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_zip_outlined),
                    title: const Text('Buka Arsip'),
                    subtitle: const Text('Lihat laporan tahun yang sudah diarsipkan'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pengaturan/arsip'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          const _SectionHeader('Perangkat'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: const Text('Printer Bluetooth'),
                  subtitle: const Text('Pilih printer & test cetak'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pengaturan/printer'),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Mode Gelap'),
                  value: themeMode == ThemeMode.dark,
                  onChanged: (_) =>
                      ref.read(themeModeProvider.notifier).toggle(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLoyaltyDialog(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final curThreshold =
        int.tryParse(await db.getSetting('loyalty_point_threshold') ?? '') ?? 0;
    final curPer =
        int.tryParse(await db.getSetting('loyalty_points_per') ?? '') ?? 1;
    if (!context.mounted) return;

    final thresholdCtrl = TextEditingController(
        text: curThreshold > 0
            ? ThousandsSeparatorFormatter.format(curThreshold)
            : '');
    final perCtrl =
        TextEditingController(text: (curPer < 1 ? 1 : curPer).toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Poin Loyalitas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pelanggan terdaftar otomatis dapat poin tiap transaksi lunas. '
              'Kosongkan nominal untuk menonaktifkan.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: thresholdCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: const [_thousandsFmt],
              decoration: const InputDecoration(
                labelText: 'Setiap belanja (Rp)',
                prefixText: 'Rp ',
                hintText: 'mis. 10.000',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: perCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Dapat berapa poin',
                suffixText: 'poin',
                hintText: 'mis. 1',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final threshold =
          ThousandsSeparatorFormatter.parseValue(thresholdCtrl.text);
      final per = int.tryParse(perCtrl.text.trim()) ?? 1;
      await db.setSetting('loyalty_point_threshold', threshold.toString());
      await db.setSetting('loyalty_points_per', (per < 1 ? 1 : per).toString());
      ref.invalidate(loyaltyRuleProvider);
    }
    thresholdCtrl.dispose();
    perCtrl.dispose();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

