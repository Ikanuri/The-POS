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
                  _SerialField(formatted: formatted),
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

/// Nomor serial disamarkan (spoiler pola titik-titik, ala mockup awal)
/// sampai diketuk — mencegah orang lewat/mengintip layar membaca sidik
/// jari device begitu saja. QR di atasnya SENGAJA TIDAK ikut disamarkan:
/// sudah kelihatan seperti kebisingan visual bagi mata telanjang, beda
/// dari teks yang gamblang terbaca.
class _SerialField extends StatefulWidget {
  const _SerialField({required this.formatted});

  final String formatted;

  @override
  State<_SerialField> createState() => _SerialFieldState();
}

class _SerialFieldState extends State<_SerialField> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        GestureDetector(
          key: const Key('serial-spoiler-tap'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _revealed = !_revealed),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    widget.formatted,
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
                ),
                if (!_revealed)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _DotPatternPainter(
                        background: scheme.surfaceContainerHighest,
                        dot: scheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _revealed ? 'Ketuk untuk sembunyikan lagi' : 'Ketuk untuk lihat nomor serial',
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: scheme.outline,
          ),
        ),
      ],
    );
  }
}

class _DotPatternPainter extends CustomPainter {
  const _DotPatternPainter({required this.background, required this.dot});

  final Color background;
  final Color dot;

  static const _spacing = 6.0;
  static const _radius = 1.3;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()..color = dot;
    for (double y = _spacing / 2; y < size.height; y += _spacing) {
      for (double x = _spacing / 2; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotPatternPainter oldDelegate) =>
      oldDelegate.background != background || oldDelegate.dot != dot;
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
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
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
                    color: scheme.onSurface,
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
