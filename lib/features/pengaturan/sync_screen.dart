import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/lan_sync_service.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  // Host state
  bool _hostRunning = false;
  String _hostIp = '';
  String _hostToken = '';

  // Client state
  final _ipCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _syncing = false;
  String? _syncResult;

  @override
  void dispose() {
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
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal start server: $e'),
            backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  Future<void> _sync() async {
    final ip = _ipCtrl.text.trim();
    final token = _tokenCtrl.text.trim().toUpperCase();
    if (ip.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan IP dan Token host')),
      );
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
        _syncResult =
            'Selesai! Diterima: ${result.received} baris, Dikirim: ${result.sent} baris';
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Host mode (owner/asisten)
          if (device.canSeeReports) ...[
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
                      _InfoRow(label: 'IP', value: '$_hostIp:8625'),
                      const SizedBox(height: 4),
                      _InfoRow(label: 'Token', value: _hostToken),
                      const SizedBox(height: 8),
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _hostToken));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Token disalin')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Salin Token'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _toggleHost,
                          child: const Text('Stop Server'),
                        ),
                      ]),
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
                    'Masukkan IP dan Token yang ditampilkan di perangkat host.',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
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
                      labelText: 'Token (6 karakter)',
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
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
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Text('$label: ',
              style: TextStyle(
                  fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          Text(value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
