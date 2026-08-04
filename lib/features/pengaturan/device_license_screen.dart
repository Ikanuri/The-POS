import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/providers/license_provider.dart';
import '../../core/services/license_service.dart';

/// Item 25c susulan — halaman detail lisensi/serial device, dipisah dari
/// "Tentang Aplikasi" (yang isinya cuma wordmark+versi+kredit) karena
/// informasi di sini lebih teknis & akan terus bertambah (upcoming: scan
/// perpanjang, generate QR serial baru dari alat scanner developer).
class DeviceLicenseScreen extends ConsumerWidget {
  const DeviceLicenseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final license = ref.watch(licenseProvider);
    final scheme = Theme.of(context).colorScheme;
    final formatted = LicenseService.formatFingerprint(license.fingerprint);
    final dateFmt = DateFormat('d MMM yyyy, HH:mm', 'id_ID');

    String expLabel() {
      if (license.exp == null) return 'Belum aktivasi';
      if (license.exp == 'selamanya') return 'Selamanya';
      final d = DateTime.tryParse(license.exp!);
      if (d == null) return license.exp!;
      return dateFmt.format(d);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Info Lisensi & Serial')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: license.fingerprint,
                      version: QrVersions.auto,
                      size: 170,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    formatted,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          letterSpacing: 1.1,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Nomor Serial Perangkat',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: formatted));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Nomor serial disalin')));
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Salin Nomor Serial'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('Tanggal Diaktifkan'),
                  subtitle: Text(license.activatedAt == null
                      ? 'Belum aktivasi'
                      : dateFmt.format(license.activatedAt!)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.event_busy_outlined),
                  title: const Text('Berlaku Sampai'),
                  subtitle: Text(expLabel()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
              'SEGERA HADIR',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
            ),
          ),
          Card(
            color: scheme.surfaceContainerHighest.withOpacity(0.5),
            child: const Column(
              children: [
                ListTile(
                  leading: Icon(Icons.qr_code_scanner_outlined),
                  title: Text('Perpanjang via Scan'),
                  subtitle: Text(
                      'Scan QR kode aktivasi baru langsung dari alat lisensi developer'),
                  enabled: false,
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.history_outlined),
                  title: Text('Riwayat Perpanjangan'),
                  subtitle: Text('Catatan tanggal & durasi tiap perpanjangan lisensi'),
                  enabled: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
