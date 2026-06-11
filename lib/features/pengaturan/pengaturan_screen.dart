import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/device_provider.dart';
import '../../core/providers/theme_provider.dart';

class PengaturanScreen extends ConsumerWidget {
  const PengaturanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider);
    final themeMode = ref.watch(themeModeProvider);
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
                if (device.isOwner)
                  ListTile(
                    leading: const Icon(Icons.tune_outlined),
                    title: const Text('Izin Kasir'),
                    subtitle: const Text('Override harga, input stok, dll'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pengaturan/izin-kasir'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const _SectionHeader('Sinkronisasi'),
          Card(
            child: Column(
              children: [
                const _PendingTile(
                  icon: Icons.wifi_outlined,
                  title: 'Sync WiFi',
                  subtitle: 'Sinkronisasi antar HP via jaringan lokal',
                  phase: 'Phase 4',
                ),
                const _PendingTile(
                  icon: Icons.save_alt_outlined,
                  title: 'Export / Import File',
                  subtitle: 'Backup terenkripsi (.berkahpos)',
                  phase: 'Phase 4',
                ),
                if (device.isOwner)
                  ListTile(
                    leading: const Icon(Icons.qr_code_2_outlined),
                    title: const Text('Pair Device Baru'),
                    subtitle: const Text('Tambah HP kasir / asisten via QR'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pengaturan/pair'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const _SectionHeader('Perangkat'),
          Card(
            child: Column(
              children: [
                const _PendingTile(
                  icon: Icons.print_outlined,
                  title: 'Printer Bluetooth',
                  subtitle: 'Pilih printer & test cetak',
                  phase: 'Phase 4',
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

class _PendingTile extends StatelessWidget {
  const _PendingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.phase,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String phase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Chip(
        label: Text(phase, style: const TextStyle(fontSize: 10)),
        visualDensity: VisualDensity.compact,
        backgroundColor: scheme.surfaceContainerHighest,
        side: BorderSide.none,
      ),
      enabled: false,
    );
  }
}
