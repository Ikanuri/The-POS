import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/providers/license_provider.dart';
import '../../core/services/license_service.dart';

// Locale 'id' TIDAK pernah di-initializeDateFormatting di app ini —
// `DateFormat(..., 'id_ID')` akan throw LocaleDataException dan membuat
// seluruh layar ini gagal render. Format nama bulan MANUAL, pola sama
// dengan `expenses_screen.dart`.
const _idMonths = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
];

String _fmtTanggal(DateTime d) =>
    '${d.day} ${_idMonths[d.month - 1]} ${d.year}';

/// Item 28b — halaman detail lisensi & nomor serial, dibuka dari chip
/// kanan-atas "Tentang Aplikasi". Dipisah dari About (yang sengaja cuma
/// wordmark + ikon + versi) karena isinya lebih dari satu baris ID:
/// nomor serial + QR-nya, tanggal aktivasi, masa berlaku, dan beberapa
/// fitur yang menyusul (terkait alat lisensi developer).
class DeviceLicenseScreen extends ConsumerWidget {
  const DeviceLicenseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final license = ref.watch(licenseProvider);
    final scheme = Theme.of(context).colorScheme;
    final formatted = LicenseService.formatFingerprint(license.fingerprint);

    String expLabel() {
      if (license.exp == null) return 'Belum aktivasi';
      if (license.exp == 'selamanya') return 'Selamanya';
      final d = DateTime.tryParse(license.exp!);
      if (d == null) return license.exp!;
      return _fmtTanggal(d);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Lisensi & Serial')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          const _SectionLabel('Nomor Serial Perangkat'),
          _Panel(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                children: [
                  // QR selalu di atas kertas putih — pembaca QR jauh lebih
                  // andal pada kontras hitam-putih penuh, tidak ikut warna
                  // panel tema (apalagi mode gelap).
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: QrImageView(
                      data: license.fingerprint,
                      version: QrVersions.auto,
                      size: 168,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    formatted,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      height: 1.6,
                      color: scheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: formatted));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nomor serial disalin')),
                      );
                    },
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Salin Nomor Serial'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tunjukkan QR ini ke developer saat aktivasi atau '
                    'perpanjangan — tidak perlu diketik manual.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: scheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const _SectionLabel('Masa Berlaku'),
          _Panel(
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.event_available_outlined,
                  label: 'Tanggal diaktifkan',
                  value: license.activatedAt == null
                      ? 'Belum aktivasi'
                      : _fmtTanggal(license.activatedAt!),
                ),
                _InfoRow(
                  icon: Icons.event_busy_outlined,
                  label: 'Berlaku sampai',
                  value: expLabel(),
                  // Lisensi "selamanya" tidak punya hitung mundur — baris
                  // "Sisa waktu" di bawah disembunyikan supaya tidak
                  // mengulang kata yang sama dua kali.
                  isLast: license.exp == 'selamanya',
                ),
                if (license.exp != 'selamanya')
                  _InfoRow(
                    icon: Icons.schedule_outlined,
                    label: 'Sisa waktu',
                    value: license.licenseStatusLabel ?? '—',
                    isLast: true,
                  ),
              ],
            ),
          ),
          const _SectionLabel('Segera Hadir'),
          const _Panel(
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.qr_code_scanner_outlined,
                  label: 'Perpanjang via scan',
                  value: 'Scan QR kode aktivasi baru langsung dari kamera',
                  dimmed: true,
                ),
                _InfoRow(
                  icon: Icons.history_outlined,
                  label: 'Riwayat perpanjangan',
                  value: 'Catatan tanggal & durasi tiap perpanjangan',
                  dimmed: true,
                  isLast: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.dimmed = false,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool dimmed;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = dimmed ? scheme.outline : scheme.onSurface;
    return Container(
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant),
              ),
            ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: dimmed ? scheme.outline : scheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
