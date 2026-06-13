import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/archive_service.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/inline_banner.dart';

final _archiveListProvider = FutureProvider.autoDispose
    .family<List<ArchiveInfo>, String>((ref, encryptionKey) {
  return ArchiveService.listArchives(encryptionKey);
});

class ArsipScreen extends ConsumerWidget {
  const ArsipScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider);
    if (!device.isConfigured) {
      return const Scaffold(
        body: Center(child: Text('Perangkat belum terkonfigurasi.')),
      );
    }
    final encryptionKey = deriveDatabaseKey(device.storeKey!);
    final archivesAsync = ref.watch(_archiveListProvider(encryptionKey));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arsip Tahunan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_archiveListProvider),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: archivesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (archives) {
          if (archives.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_off_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  const Text('Belum ada arsip tahunan.'),
                  const SizedBox(height: 4),
                  const Text(
                    'Gunakan menu Tutup Buku untuk mengarsipkan data tahun lalu.',
                    style: TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: archives.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final info = archives[i];
              return _ArchiveCard(
                info: info,
                encryptionKey: encryptionKey,
              );
            },
          );
        },
      ),
    );
  }
}

class _ArchiveCard extends ConsumerStatefulWidget {
  const _ArchiveCard({required this.info, required this.encryptionKey});

  final ArchiveInfo info;
  final String encryptionKey;

  @override
  ConsumerState<_ArchiveCard> createState() => _ArchiveCardState();
}

class _ArchiveCardState extends ConsumerState<_ArchiveCard>
    with InlineBannerStateMixin<_ArchiveCard> {
  bool _expanded = false;
  AppDatabase? _archiveDb;
  bool _opening = false;

  Future<void> _open() async {
    if (_archiveDb != null) {
      setState(() => _expanded = true);
      return;
    }
    setState(() => _opening = true);
    try {
      final db = await ArchiveService.open(widget.info.year, widget.encryptionKey);
      if (mounted) setState(() { _archiveDb = db; _expanded = true; });
    } catch (e) {
      if (!mounted) return;
      showError('Gagal membuka arsip: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _close() {
    setState(() { _expanded = false; _archiveDb = null; });
    ArchiveService.close();
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = widget.info;

    return Card(
      child: Column(
        children: [
          inlineBanner(),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              child: Text(
                '${info.year}',
                style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ),
            title: Text('Arsip ${info.year}'),
            subtitle: Text(
              '${info.txCount} transaksi · '
              '${info.summaryCount} hari · '
              '${_sizeLabel(info.sizeBytes)}',
            ),
            trailing: _opening
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: Icon(_expanded
                        ? Icons.expand_less
                        : Icons.bar_chart_outlined),
                    onPressed: _expanded ? _close : _open,
                    tooltip: _expanded ? 'Tutup' : 'Lihat Ringkasan',
                  ),
          ),
          if (_expanded && _archiveDb != null)
            _ArchiveSummary(db: _archiveDb!, year: info.year),
        ],
      ),
    );
  }
}

class _ArchiveSummary extends StatefulWidget {
  const _ArchiveSummary({required this.db, required this.year});

  final AppDatabase db;
  final int year;

  @override
  State<_ArchiveSummary> createState() => _ArchiveSummaryState();
}

class _ArchiveSummaryState extends State<_ArchiveSummary> {
  ({int omzet, int hpp, int labaKotor, int txCount})? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final from = DateTime(widget.year);
      final to = DateTime(widget.year + 1);
      final summaries = await widget.db.getDailySummaries(from, to);
      final omzet = summaries.fold<int>(0, (s, r) => s + r.omzet);
      final hpp = summaries.fold<int>(0, (s, r) => s + r.hpp);
      final labaKotor = summaries.fold<int>(0, (s, r) => s + r.labaKotor);
      final txCount = summaries.fold<int>(0, (s, r) => s + r.jumlahTransaksi);
      if (mounted) setState(() => _data = (omzet: omzet, hpp: hpp, labaKotor: labaKotor, txCount: txCount));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_data == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final d = _data!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _SummaryRow('Omzet', formatRupiah(d.omzet)),
          _SummaryRow('HPP', formatRupiah(d.hpp)),
          _SummaryRow('Laba Kotor', formatRupiah(d.labaKotor),
              valueColor: scheme.primary),
          _SummaryRow('Jumlah Transaksi', '${d.txCount}'),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value, {this.valueColor});
  final String label, value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13))),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor)),
      ]),
    );
  }
}
