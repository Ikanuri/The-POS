import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/lan_sync_service.dart';
import '../../core/widgets/inline_banner.dart';
import '../../core/widgets/qr_sync_widgets.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen>
    with InlineBannerStateMixin<SyncScreen> {
  // Host state
  bool _hostRunning = false;
  String _hostIp = '';
  String _hostToken = '';
  List<PendingSyncItem> _queue = [];

  // Client state
  final _ipCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _syncing = false;
  String? _syncResult;

  @override
  void initState() {
    super.initState();
    // Listen for queue changes while screen is open.
    LanSyncService.onQueueChanged = () {
      if (mounted) setState(() => _queue = LanSyncService.pendingQueue.toList());
    };
  }

  @override
  void dispose() {
    LanSyncService.onQueueChanged = null;
    LanSyncService.stopHost();
    _ipCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleHost() async {
    if (_hostRunning) {
      await LanSyncService.stopHost();
      setState(() {
        _hostRunning = false;
        _hostIp = '';
        _hostToken = '';
        _queue = [];
      });
      return;
    }
    try {
      final device = ref.read(deviceProvider);
      final db = ref.read(databaseProvider);
      final (ip, token) = await LanSyncService.startHost(
        db: db,
        storeKey: device.storeKey!,
      );
      setState(() {
        _hostRunning = true;
        _hostIp = ip;
        _hostToken = token;
        _queue = LanSyncService.pendingQueue.toList();
      });
    } catch (e) {
      if (!mounted) return;
      showError('Gagal start server: $e');
    }
  }

  Future<void> _approve(PendingSyncItem item) async {
    // Kategori yang tersedia di payload ini (yang ada datanya), beserta jumlah.
    final available = <String, ({List<String> tables, int count})>{};
    LanSyncService.syncCategories.forEach((label, tables) {
      final count = item.tables[tables.first]?.length ?? 0;
      if (count > 0) available[label] = (tables: tables, count: count);
    });

    if (available.isEmpty) {
      // Tidak ada data append-only untuk diterima → buang dari antrian.
      LanSyncService.rejectSync(item.id);
      if (mounted) showSuccess('Tidak ada data baru untuk diterima');
      return;
    }

    final selected = {for (final k in available.keys) k: true};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Terima Data Sync'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pilih kategori data dari ${item.fromIp} yang ingin diterima.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 4),
              ...available.entries.map((e) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('${e.key} (${e.value.count})'),
                    value: selected[e.key],
                    onChanged: (v) =>
                        setSt(() => selected[e.key] = v ?? false),
                  )),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Terima')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final allowed = <String>{};
    available.forEach((label, v) {
      if (selected[label] == true) allowed.addAll(v.tables);
    });
    if (allowed.isEmpty) {
      LanSyncService.rejectSync(item.id);
      if (mounted) showSuccess('Tidak ada kategori dipilih — sync dilewati');
      return;
    }

    try {
      final received =
          await LanSyncService.approveSync(item.id, allowedTables: allowed);
      if (mounted) showSuccess('Sync disetujui · $received baris diterima');
    } catch (e) {
      if (mounted) showError('Gagal merge: $e');
    }
  }

  void _reject(PendingSyncItem item) {
    LanSyncService.rejectSync(item.id);
    if (mounted) showSuccess('Sync dari ${item.fromIp} ditolak');
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    showSuccess('$label disalin: $value');
  }

  Future<void> _sync() async {
    final ip = _ipCtrl.text.trim();
    final token = _tokenCtrl.text.trim().toUpperCase();
    if (ip.isEmpty || token.isEmpty) {
      showError('Masukkan IP dan Token host');
      return;
    }
    setState(() {
      _syncing = true;
      _syncResult = null;
    });
    try {
      final device = ref.read(deviceProvider);
      final db = ref.read(databaseProvider);
      final result = await LanSyncService.syncToHost(
        db: db,
        storeKey: device.storeKey!,
        hostIp: ip,
        syncToken: token,
      );
      if (!mounted) return;
      setState(() {
        _syncResult = result.pendingApproval
            ? 'Data terkirim, menunggu persetujuan owner di perangkat host.\n'
                'Diterima dari host: ${result.received} baris.'
            : 'Selesai! Diterima: ${result.received} baris, Dikirim: ${result.sent} baris';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncResult = 'Gagal: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final device = ref.watch(deviceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sync WiFi')),
      body: Column(
        children: [
          inlineBanner(),
          Expanded(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Host mode — HANYA owner. Master data (produk, harga, IZIN
          // kasir/asisten) sengaja mengalir SATU ARAH host→klien
          // (lan_sync_service.dart: klien cuma boleh upload append-only,
          // master data tidak pernah di-merge dari klien). Kalau asisten
          // ikut bisa "Jadi Host" (dulu pakai device.canSeeReports, owner
          // ATAU asisten), perubahan yang dibuat owner di device-nya sendiri
          // (jadi KLIEN dalam topologi itu) tidak akan pernah nyampe ke host
          // asisten — bug nyata: owner nyalakan izin asisten_stok_minus,
          // asisten tetap terblokir selamanya krn DB host-nya sendiri tidak
          // pernah menerima perubahan itu. Owner harus SELALU jadi host
          // supaya jadi satu-satunya sumber kebenaran master data.
          if (device.isOwner) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.wifi_tethering_outlined, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text('Jadi Host', style: Theme.of(context).textTheme.titleMedium),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      'Perangkat ini akan menjadi server sync. Device kasir '
                      'perlu terhubung ke jaringan WiFi yang sama.',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    if (_hostRunning) ...[
                      _InfoRow(
                        label: 'IP',
                        value: '$_hostIp:8625',
                        onCopy: () => _copy('$_hostIp:8625', 'IP'),
                      ),
                      const SizedBox(height: 6),
                      _InfoRow(
                        label: 'Token',
                        value: _hostToken,
                        onCopy: () => _copy(_hostToken, 'Token'),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: QrSyncDisplay(data: {
                          'ip': '$_hostIp:8625',
                          'key': _hostToken,
                        }),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: _toggleHost,
                        child: const Text('Stop Server'),
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: _toggleHost,
                        icon: const Icon(Icons.play_arrow_outlined),
                        label: const Text('Start Server'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // B-4: Antrian persetujuan sync dari perangkat kasir.
            if (_queue.isNotEmpty) ...[
              Row(children: [
                Icon(Icons.pending_actions_outlined,
                    color: scheme.tertiary, size: 18),
                const SizedBox(width: 6),
                Text('Menunggu Persetujuan (${_queue.length})',
                    style: Theme.of(context).textTheme.titleSmall),
              ]),
              const SizedBox(height: 6),
              ..._queue.map((item) {
                final mins = DateTime.now()
                    .difference(item.arrivedAt)
                    .inMinutes;
                return Card(
                  color: scheme.tertiaryContainer,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.devices_outlined, size: 16,
                                color: scheme.onTertiaryContainer),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(item.fromIp,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onTertiaryContainer)),
                            ),
                            Text(
                                mins == 0
                                    ? 'Baru saja'
                                    : '$mins menit lalu',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onTertiaryContainer
                                        .withOpacity(0.6))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(item.tablesSummary,
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onTertiaryContainer
                                    .withOpacity(0.8))),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _reject(item),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: scheme.error),
                                child: const Text('Tolak'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => _approve(item),
                                style: FilledButton.styleFrom(
                                    backgroundColor: scheme.primary,
                                    foregroundColor: scheme.onPrimary),
                                child: const Text('Setuju'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
            ],
          ],

          // Client mode (semua device bisa sync)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.sync_outlined, color: scheme.secondary),
                    const SizedBox(width: 8),
                    Text('Hubungkan ke Host',
                        style: Theme.of(context).textTheme.titleMedium),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Scan QR atau masukkan IP dan Token dari perangkat host.',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final data = await showQrSyncScanner(context);
                      if (data == null || !mounted) return;
                      var ip = data['ip'] as String? ?? '';
                      final key = data['key'] as String? ?? '';
                      if (ip.contains(':')) ip = ip.split(':').first;
                      if (ip.isNotEmpty) _ipCtrl.text = ip;
                      if (key.isNotEmpty) _tokenCtrl.text = key;
                    },
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text('Scan QR Host'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ipCtrl,
                    decoration: const InputDecoration(
                      labelText: 'IP Host (misal: 192.168.1.5)',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _tokenCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Token (12 karakter)',
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 12,
                  ),
                  const SizedBox(height: 4),
                  if (_syncing)
                    const Row(children: [
                      SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Sync berjalan…'),
                    ])
                  else
                    FilledButton.icon(
                      onPressed: _sync,
                      icon: const Icon(Icons.sync),
                      label: const Text('Sync Sekarang'),
                    ),
                  if (_syncResult != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _syncResult!.startsWith('Gagal')
                            ? scheme.errorContainer
                            : scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _syncResult!,
                        style: TextStyle(
                          fontSize: 13,
                          color: _syncResult!.startsWith('Gagal')
                              ? scheme.onErrorContainer
                              : scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      )),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.onCopy});
  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2, right: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ),
          if (onCopy != null)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: 'Salin',
              visualDensity: VisualDensity.compact,
              onPressed: onCopy,
            ),
        ],
      ),
    );
  }
}
