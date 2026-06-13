import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/tutup_buku_service.dart';
import '../../core/widgets/inline_banner.dart';

class TutupBukuScreen extends ConsumerStatefulWidget {
  const TutupBukuScreen({super.key});

  @override
  ConsumerState<TutupBukuScreen> createState() => _TutupBukuScreenState();
}

class _TutupBukuScreenState extends ConsumerState<TutupBukuScreen>
    with InlineBannerStateMixin<TutupBukuScreen> {
  bool _loading = true;
  bool _busy = false;
  List<int> _archivedYears = [];
  int _currentYear = DateTime.now().year;
  String? _lastArchiveYear;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = ref.read(databaseProvider);
    final years = await TutupBukuService.listArchivedYears();
    final last = await db.getSetting('last_archive_year');
    if (mounted) {
      setState(() {
        _archivedYears = years;
        _lastArchiveYear = last;
        _currentYear = DateTime.now().year;
        _loading = false;
      });
    }
  }

  Future<void> _startTutupBuku(int year) async {
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);

    // Konfirmasi
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Tutup Buku $year'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Semua transaksi tahun $year akan dipindahkan ke file arsip '
              'archive_$year.db di perangkat ini.',
            ),
            const SizedBox(height: 12),
            const _WarningItem(
                icon: Icons.archive_outlined,
                text: 'File arsip menggunakan enkripsi yang sama dengan database utama.'),
            const _WarningItem(
                icon: Icons.inventory_2_outlined,
                text: 'Data produk, pelanggan, dan pengaturan tetap utuh.'),
            _WarningItem(
                icon: Icons.sync_disabled_outlined,
                text: 'Transaksi tahun $year tidak akan tersedia di laporan '
                    'utama setelah tutup buku.'),
            const _WarningItem(
                icon: Icons.warning_amber_rounded,
                text: 'Proses ini tidak dapat diurungkan. '
                    'Pastikan sudah backup sebelum melanjutkan.',
                isWarning: true),
            const SizedBox(height: 8),
            Text(
              'Device: ${device.deviceName} (${device.deviceCode})',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tutup Buku'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await TutupBukuService.execute(db: db, year: year);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tutup Buku Selesai'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tahun ${result.archivedYear} berhasil diarsipkan.'),
              const SizedBox(height: 8),
              Text(
                  '${result.txArchived} transaksi dipindahkan ke arsip.'),
              const SizedBox(height: 4),
              Text(
                'File: ${result.archivePath}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK')),
          ],
        ),
      );
      await _load();
    } on TutupBukuException catch (e) {
      if (!mounted) return;
      showError(e.message);
    } catch (e) {
      if (!mounted) return;
      showError('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prevYear = _currentYear - 1;
    final alreadyArchived = _archivedYears.contains(prevYear);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tutup Buku'),
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: Column(
        children: [
          inlineBanner(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Info card
                    Card(
                      color: scheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.info_outline,
                                  color: scheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Text('Tentang Tutup Buku',
                                  style: TextStyle(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w600)),
                            ]),
                            const SizedBox(height: 8),
                            const Text(
                              'Tutup buku memindahkan semua transaksi satu tahun '
                              'ke file arsip terpisah. Database utama menjadi lebih '
                              'ramping dan tetap responsif.\n\n'
                              'Data arsip dapat dibuka kembali di menu Buka Arsip '
                              'untuk melihat laporan tahun lama.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tutup buku tahun sebelumnya
                    Text(
                      'TAHUN BERJALAN',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          child: Text(
                            '$_currentYear',
                            style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                                fontSize: 13),
                          ),
                        ),
                        title: Text('Tahun $_currentYear'),
                        subtitle: const Text('Tahun berjalan — belum bisa ditutup'),
                        trailing: Icon(Icons.lock_clock_outlined,
                            color: scheme.outline),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: alreadyArchived
                              ? scheme.surfaceContainerHighest
                              : scheme.errorContainer,
                          child: Icon(
                            alreadyArchived
                                ? Icons.check_circle_outline
                                : Icons.archive_outlined,
                            color: alreadyArchived
                                ? scheme.onSurfaceVariant
                                : scheme.onErrorContainer,
                            size: 20,
                          ),
                        ),
                        title: Text('Tutup Buku $prevYear'),
                        subtitle: Text(alreadyArchived
                            ? 'Sudah diarsipkan'
                            : 'Pindahkan semua transaksi $prevYear ke arsip'),
                        trailing: alreadyArchived
                            ? null
                            : SizedBox(
                                width: 76,
                                child: FilledButton.tonal(
                                  onPressed: _busy
                                      ? null
                                      : () => _startTutupBuku(prevYear),
                                  child: const Text('Mulai'),
                                ),
                              ),
                      ),
                    ),

                    if (_archivedYears.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'ARSIP TERSEDIA',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Column(
                          children: [
                            for (final year in _archivedYears.reversed)
                              ListTile(
                                leading: const Icon(Icons.folder_zip_outlined),
                                title: Text('Arsip $year'),
                                subtitle: Text('archive_$year.db'),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                          ],
                        ),
                      ),
                    ],

                    if (_lastArchiveYear != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Tutup buku terakhir: tahun $_lastArchiveYear',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
                if (_busy)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Sedang mengarsipkan...',
                              style: TextStyle(color: Colors.white)),
                        ],
                      ),
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

class _WarningItem extends StatelessWidget {
  const _WarningItem(
      {required this.icon, required this.text, this.isWarning = false});

  final IconData icon;
  final String text;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isWarning ? scheme.error : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 13, color: color))),
        ],
      ),
    );
  }
}
