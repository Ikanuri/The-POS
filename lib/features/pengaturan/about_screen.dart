import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/providers/license_provider.dart';
import '../../core/services/license_service.dart';

/// Item 28b — layar "Tentang Aplikasi". Komposisi mengikuti mockup yang
/// sudah dikonfirmasi user: AppBar polos (TANPA judul) + tombol "?" bulat
/// di kanan, chip lisensi kecil rata-kanan di bawahnya, hero di TENGAH
/// (wordmark dulu, BARU ikon besar, lalu tagline), dan footer versi +
/// kredit menempel di bawah.
///
/// Chip kanan-atas menggantikan chip "ID device" di mockup awal — nomor
/// serial dipindah ke halaman tersendiri (`DeviceLicenseScreen`) atas
/// permintaan user krn informasinya lebih dari sekadar satu baris ID
/// (tanggal aktivasi, masa berlaku, fitur menyusul).
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final license = ref.watch(licenseProvider);
    final showLicense = LicenseService.isConfigured && license.isActivated;

    return Scaffold(
      appBar: AppBar(
        // Sengaja tanpa judul — mockup memberi seluruh panggung ke
        // wordmark di hero, bukan mengulanginya lagi di AppBar.
        title: const SizedBox.shrink(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _HelpButton(
              onTap: () => context.push('/pengaturan/tentang/tutorial'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (showLicense) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _LicenseChip(
                    status: license.licenseStatusLabel ?? '—',
                    onTap: () => context.push('/pengaturan/lisensi'),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'tap untuk nomor serial & detail',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: scheme.outline,
                    ),
                  ),
                ),
              ),
            ],
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'The POS',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 26),
                      Container(
                        decoration: BoxDecoration(
                          // Sumber (emoji resmi, transparan) tidak mengisi
                          // penuh kotak persegi — backdrop peachy ini
                          // mengembalikan tampilan "squircle" spt launcher
                          // Android asli (yang emoji-nya di-flatten di atas
                          // warna solid ini saat build APK).
                          color: const Color(0xFFFFC896),
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 32,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(40),
                          child: Image.asset(
                            'assets/icon/app_icon.png',
                            width: 178,
                            height: 178,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                            isAntiAlias: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(
                          'Aplikasi kasir offline-first\n'
                          'untuk toko grosir & retail',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: Column(
                children: [
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final info = snapshot.data;
                      return Text(
                        info == null
                            ? ''
                            : 'Versi ${info.version} (build ${info.buildNumber})',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'made with ♥️ by Dre',
                    style: TextStyle(fontSize: 11, color: scheme.outline),
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

/// Tombol "?" bulat ber-outline (mockup) — bukan `IconButton` bawaan,
/// supaya bentuk & warnanya persis: lingkaran 34px, garis tipis abu, tanda
/// tanya tebal berwarna aksen.
class _HelpButton extends StatelessWidget {
  const _HelpButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Panduan & tips',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: scheme.outline, width: 1.6),
          ),
          child: Text(
            '?',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip lisensi rata-kanan — posisi & bentuknya mewarisi chip "ID device"
/// di mockup (panel, garis tipis, radius penuh), isinya status masa
/// berlaku + panah ke halaman detail.
class _LicenseChip extends StatelessWidget {
  const _LicenseChip({required this.status, required this.onTap});

  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user_outlined,
                size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Lisensi',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              status,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}
