import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/device_provider.dart';
import '../../../core/providers/sync_state_provider.dart';
import '../../../core/theme/app_overlays.dart';
import '../../../core/widgets/qr_sync_widgets.dart';

/// Pop-up kecil "Sync LAN cepat" dari layar Kasir (tombol pojok) — tanpa
/// pindah ke Pengaturan. Memakai mesin yang SAMA dengan layar Sync WiFi
/// (`syncStateProvider`): owner = jalan/hentikan host + IP & token;
/// kasir/asisten = IP & token host (diingat dari sync terakhir) lalu
/// "Sinkron sekarang". Pengaturan lanjutan (timeout, antrian persetujuan,
/// Sync Ulang Penuh) tetap di layar Sync WiFi.
Future<void> showQuickSyncDialog(BuildContext context) => showAppDialog<void>(
      context: context,
      builder: (_) => const QuickSyncDialog(),
    );

class QuickSyncDialog extends ConsumerStatefulWidget {
  const QuickSyncDialog({super.key});

  @override
  ConsumerState<QuickSyncDialog> createState() => _QuickSyncDialogState();
}

class _QuickSyncDialogState extends ConsumerState<QuickSyncDialog> {
  static const _prefIp = 'quick_sync_last_ip';
  static const _prefToken = 'quick_sync_last_token';

  final _ipCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _ipCtrl.text = prefs.getString(_prefIp) ?? '';
    _tokenCtrl.text = prefs.getString(_prefToken) ?? '';
    setState(() {});
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final data = await showQrSyncScanner(context);
    if (data == null || !mounted) return;
    var ip = data['ip'] as String? ?? '';
    final key = data['key'] as String? ?? '';
    if (ip.contains(':')) ip = ip.split(':').first;
    if (ip.isNotEmpty) _ipCtrl.text = ip;
    if (key.isNotEmpty) _tokenCtrl.text = key;
    setState(() {});
  }

  Future<void> _sync() async {
    final ip = _ipCtrl.text.trim();
    final token = _tokenCtrl.text.trim().toUpperCase();
    if (ip.isEmpty || token.isEmpty) {
      setState(() => _error = 'Isi IP dan Token host dulu');
      return;
    }
    setState(() => _error = null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefIp, ip);
    await prefs.setString(_prefToken, token);
    try {
      await ref.read(syncStateProvider.notifier).sync(ip: ip, token: token);
    } catch (_) {
      // Pesan galat sudah ditulis notifier ke clientResultMessage.
    }
  }

  Future<void> _toggleHost() async {
    try {
      await ref.read(syncStateProvider.notifier).toggleHost();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal menyalakan host: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final device = ref.watch(deviceProvider);
    final sync = ref.watch(syncStateProvider);
    final waiting = sync.queue.length +
        sync.proposals.length +
        sync.laciMejaProposals.length;

    return AlertDialog(
      key: const Key('quick-sync-dialog'),
      title: const Text('Sync LAN'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (device.isOwner) ...[
              Row(
                children: [
                  Icon(
                    sync.hostRunning
                        ? Icons.wifi_tethering_rounded
                        : Icons.portable_wifi_off_rounded,
                    color: sync.hostRunning ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sync.hostRunning
                          ? 'Host aktif · $waiting menunggu persetujuan'
                          : 'Host belum aktif',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              if (sync.hostRunning) ...[
                const SizedBox(height: 10),
                _CopyRow(label: 'IP', value: sync.hostIp),
                _CopyRow(label: 'Token', value: sync.hostToken),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('quick-sync-host'),
                  onPressed: _toggleHost,
                  child: Text(sync.hostRunning ? 'Hentikan host' : 'Jadi host'),
                ),
              ),
            ] else ...[
              Text('Masukkan IP dan Token dari perangkat host, atau scan QR-nya.',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              const SizedBox(height: 10),
              TextField(
                key: const Key('quick-sync-ip'),
                controller: _ipCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'IP Host', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('quick-sync-token'),
                controller: _tokenCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 12,
                decoration: const InputDecoration(
                    labelText: 'Token (12 karakter)', isDense: true),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('quick-sync-scan'),
                  onPressed: _scanQr,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: const Text('Scan QR host'),
                ),
              ),
              if (sync.clientSyncing)
                const Row(children: [
                  SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Menyinkronkan…'),
                ])
              else if (sync.clientResultMessage != null)
                Text(sync.clientResultMessage!,
                    key: const Key('quick-sync-result'),
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: cs.error, fontSize: 12.5)),
            ],
          ],
        ),
      ),
      // Dua tombol sebaris sempit (aturan dialog: jangan 3 tombol).
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tutup'),
        ),
        if (!device.isOwner)
          FilledButton(
            key: const Key('quick-sync-go'),
            onPressed: sync.clientSyncing ? null : _sync,
            child: const Text('Sinkron sekarang'),
          ),
      ],
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
              width: 48,
              child: Text(label,
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
          Expanded(
            child: SelectableText(value.isEmpty ? '-' : value,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontFeatures: [])),
          ),
          IconButton(
            tooltip: 'Salin $label',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showAppSnackBar(
                  SnackBar(content: Text('$label disalin')));
            },
          ),
        ],
      ),
    );
  }
}
