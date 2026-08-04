import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/providers/license_provider.dart';
import '../../core/services/license_service.dart';

/// Item 25c/28b — layar "Tentang Aplikasi". Wordmark + ikon besar, tombol
/// "?" ke tutorial (`TutorialListScreen`), dan pintu masuk ke "Info Lisensi
/// & Serial" (dipindah ke sini dari kartu "Device Ini" di Pengaturan —
/// permintaan user, supaya info teknis lisensi tidak numpuk di halaman
/// utama Pengaturan).
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final license = ref.watch(licenseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tentang Aplikasi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Panduan & tips',
            onPressed: () => context.push('/pengaturan/tentang/tutorial'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  children: [
                    Image.asset(
                      'assets/icon/app_icon.png',
                      width: 108,
                      height: 108,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'The POS',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Aplikasi kasir offline-first',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 32),
                    if (LicenseService.isConfigured && license.isActivated)
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.verified_user_outlined),
                          title: const Text('Info Lisensi & Serial'),
                          subtitle: Text(license.licenseStatusLabel ?? '—'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/pengaturan/lisensi'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final info = snapshot.data;
                      final label = info == null
                          ? ''
                          : 'v${info.version}+${info.buildNumber}';
                      return Text(
                        label,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'made with ♥️ by Dre',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
