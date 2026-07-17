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
  List<ArchiveManifestEntry> _archives = [];

  /// Item 31 — awal periode berikutnya, otomatis dari tutup buku TERAKHIR
  /// (`last_archive_date`) atau transaksi paling lama (kalau belum pernah
  /// tutup buku). Null kalau database belum punya transaksi sama sekali.
  DateTime? _suggestedStart;
  int _pendingTxCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = ref.read(databaseProvider);
    final archives = await TutupBukuService.listArchiveEntries(db);
    final suggestedStart = await TutupBukuService.suggestPeriodStart(db);
    var pendingCount = 0;
    if (suggestedStart != null) {
      final row = await db.customSelect(
        'SELECT COUNT(*) AS cnt FROM transactions WHERE created_at >= '
        '${suggestedStart.millisecondsSinceEpoch ~/ 1000}',
      ).getSingle();
      pendingCount = (row.data['cnt'] as int?) ?? 0;
    }
    if (mounted) {
      setState(() {
        _archives = archives;
        _suggestedStart = suggestedStart;
        _pendingTxCount = pendingCount;
        _loading = false;
      });
    }
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _pickPeriodEndAndStart() async {
    final start = _suggestedStart;
    if (start == null) {
      showError('Belum ada transaksi sama sekali — tidak ada yang perlu '
          'ditutup buku.');
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: start,
      lastDate: DateTime.now(),
      helpText: 'Pilih tanggal akhir periode (mis. tanggal Hari Raya)',
    );
    if (picked == null || !mounted) return;
    await _startTutupBuku(periodStart: start, periodEnd: picked);
  }

  Future<void> _startTutupBuku({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);

    // Konfirmasi
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Tutup Buku ${periodEnd.year}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Semua transaksi dari ${_fmtDate(periodStart)} s/d '
              '${_fmtDate(periodEnd)} akan dipindahkan ke file arsip '
              'archive_${periodEnd.year}.db di perangkat ini.',
            ),
            const SizedBox(height: 12),
            const _WarningItem(
                icon: Icons.archive_outlined,
                text: 'File arsip menggunakan enkripsi yang sama dengan database utama.'),
            const _WarningItem(
                icon: Icons.inventory_2_outlined,
                text: 'Data produk, pelanggan, dan pengaturan tetap utuh.'),
            const _WarningItem(
                icon: Icons.sync_disabled_outlined,
                text: 'Transaksi periode ini tidak akan tersedia di laporan '
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
      final result = await TutupBukuService.execute(
        db: db,
        periodStart: periodStart,
        periodEnd: periodEnd,
      );
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tutup Buku Selesai'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Periode ${_fmtDate(result.periodStart)} – '
                  '${_fmtDate(result.periodEnd)} berhasil diarsipkan.'),
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
                              'Tutup buku memindahkan transaksi satu periode '
                              '(sekali per tahun, tanggal akhir bisa custom — '
                              'mis. ikut Hari Raya) ke file arsip terpisah. '
                              'Database utama menjadi lebih ramping dan tetap '
                              'responsif.\n\n'
                              'Data arsip dapat dibuka kembali di menu Buka '
                              'Arsip untuk melihat laporan periode lama.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'PERIODE BERJALAN',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: scheme.errorContainer,
                          child: Icon(Icons.archive_outlined,
                              color: scheme.onErrorContainer, size: 20),
                        ),
                        title: _suggestedStart == null
                            ? const Text('Belum ada transaksi')
                            : Text(
                                'Sejak ${_fmtDate(_suggestedStart!)}, '
                                '$_pendingTxCount transaksi belum diarsip'),
                        subtitle: const Text(
                            'Pilih tanggal akhir periode (mis. Hari Raya) '
                            'utk tutup buku'),
                        trailing: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: (_busy || _suggestedStart == null)
                              ? null
                              : _pickPeriodEndAndStart,
                          child: const Text('Pilih Tanggal'),
                        ),
                      ),
                    ),

                    if (_archives.isNotEmpty) ...[
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
                            for (final entry in _archives.reversed)
                              ListTile(
                                leading: const Icon(Icons.folder_zip_outlined),
                                title: Text('Arsip ${entry.year}'),
                                subtitle: Text(entry.isLegacyFallback
                                    ? '${_fmtDate(entry.periodStart)} – '
                                        '${_fmtDate(entry.periodEnd)} '
                                        '(estimasi, arsip lama)'
                                    : '${_fmtDate(entry.periodStart)} – '
                                        '${_fmtDate(entry.periodEnd)}, '
                                        '${entry.txCount} transaksi'),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                          ],
                        ),
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
