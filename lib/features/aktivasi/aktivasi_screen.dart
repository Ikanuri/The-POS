import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/license_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/services/license_service.dart';

/// Item 25c — layar gerbang aktivasi. Muncul (lewat redirect di
/// `app_router.dart`) untuk SEMUA kondisi terkunci (belum aktivasi/masa
/// berlaku habis/dicabut) dgn pesan yang SAMA — sengaja tidak membedakan
/// alasan (tidak membocorkan mekanisme pencabutan, tidak terkesan menuduh).
/// Visual tenang, konsisten dgn `WelcomeScreen` — BUKAN gaya DRM/ancaman.
class AktivasiScreen extends ConsumerStatefulWidget {
  const AktivasiScreen({super.key});

  @override
  ConsumerState<AktivasiScreen> createState() => _AktivasiScreenState();
}

class _AktivasiScreenState extends ConsumerState<AktivasiScreen> {
  final _codeCtrl = TextEditingController();
  bool _submitting = false;
  bool _showError = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _copyFingerprint(String formatted) async {
    await Clipboard.setData(ClipboardData(text: formatted));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Kode disalin')));
  }

  Future<void> _shareFingerprint(String formatted) async {
    await Share.share(
      'Kode aktivasi The POS saya: $formatted',
      subject: 'Kode aktivasi The POS',
    );
  }

  Future<void> _activate() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _submitting = true;
      _showError = false;
    });
    final result = await ref.read(licenseProvider.notifier).activate(code);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isOk) {
      context.go('/kasir');
    } else {
      setState(() => _showError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Brightness EFEKTIF (sudah benar juga untuk ThemeMode.system).
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ref.watch(themeModeProvider); // rebuild saat mode ditukar
    final fingerprint = ref.watch(licenseProvider).fingerprint;
    final formatted = LicenseService.formatFingerprint(fingerprint);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          // Kunci ikut brightness: berganti tema selagi layar ini terlihat
          // membuat sebagian widget dicat memakai ukuran layout LAMA →
          // assert framework 'debugSize == size' (text_painter.dart). Bug
          // ini SUDAH ada sebelum tombol mode gelap di bawah ditambahkan
          // (dibuktikan lewat probe yang mengganti tema langsung via
          // provider, tanpa menyentuh tombol) — cuma tidak pernah
          // terjangkau karena dari layar ini memang belum ada cara
          // mengubah tema. Mengganti key memaksa subtree baru sehingga
          // layout & paint selalu sepadan. AMAN thd isi field kode: teksnya
          // dipegang `_codeCtrl` milik State, bukan oleh widget tree.
          child: KeyedSubtree(
            key: ValueKey(isDark),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Layar ini muncul SEBELUM /setup & sebelum DB bisa dibuka
              // (gerbang lisensi Item 25c) — jadi belum ada akses ke layar
              // Pengaturan tempat mode gelap biasanya diatur. `themeMode`
              // sendiri disimpan di SharedPreferences (bukan tabel settings
              // DB), jadi aman dipakai di titik ini.
              //
              // Ikon & tooltip menyebut TUJUAN (mode yang dituju kalau
              // ditekan), bukan keadaan sekarang — pola yang sama dgn tombol
              // switch QR di sheet pelunasan.
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: isDark ? 'Mode Terang' : 'Mode Gelap',
                  icon: Icon(isDark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined),
                  onPressed: () =>
                      ref.read(themeModeProvider.notifier).toggle(),
                ),
              ),
              const SizedBox(height: 4),
              Icon(Icons.storefront_outlined, size: 56, color: scheme.primary),
              const SizedBox(height: 20),
              Text(
                'Aktivasi Diperlukan',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Kirim kode di bawah ini ke developer untuk mendapatkan '
                'kode aktivasi.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Item 25c susulan — QR berisi fingerprint mentah (bukan
                    // versi berkelompok/uppercase) supaya alat scanner
                    // developer bisa baca langsung, tanpa perlu transkrip
                    // manual yang rawan typo.
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        // Kunci ikut brightness — lihat dok `QrisQrBox`:
                        // `QrImageView` (qr_flutter 4.1.0) melempar assert
                        // 'debugSize == size' saat tema berganti selagi QR
                        // terlihat. Baru terjangkau sejak tombol mode gelap
                        // ditambahkan di layar ini.
                        key: ValueKey(isDark),
                        data: fingerprint,
                        version: QrVersions.auto,
                        size: 160,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      formatted,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            letterSpacing: 1.2,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _copyFingerprint(formatted),
                            icon: const Icon(Icons.copy_outlined),
                            label: const Text('Salin Kode'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _shareFingerprint(formatted),
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Kirim via WhatsApp'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 40),
              TextField(
                controller: _codeCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Tempel kode aktivasi',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_showError) setState(() => _showError = false);
                },
              ),
              if (_showError) ...[
                const SizedBox(height: 8),
                Text(
                  'Kode tidak dikenali. Cek kembali atau hubungi developer.',
                  style: TextStyle(color: scheme.error, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _activate,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Aktifkan'),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}
