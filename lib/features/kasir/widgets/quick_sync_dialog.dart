import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../core/widgets/app_scanner.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/device_provider.dart';
import '../../../core/providers/sync_state_provider.dart';
import '../../../core/theme/app_overlays.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/qr_sync_widgets.dart';

/// Pop-up "Sync LAN cepat" dari layar Kasir - tanpa pindah ke Pengaturan.
/// Memakai mesin yang SAMA dengan layar Sync WiFi (`syncStateProvider`):
///  - **Host** (khusus owner): jalan/hentikan host, menampilkan QR koneksi
///    (+ IP & token) untuk dipindai perangkat lain.
///  - **Klien**: memindai QR host dengan kamera langsung di pop-up (atau isi
///    IP & token manual; diingat dari sync terakhir) lalu "Sinkron sekarang".
/// Pengaturan lanjutan (timeout, antrian persetujuan, Sync Ulang Penuh) tetap
/// di layar Sync WiFi.
Future<void> showQuickSyncDialog(BuildContext context) => showAppDialog<void>(
      context: context,
      builder: (_) => const QuickSyncDialog(),
    );

enum QuickSyncMode { host, client }

/// Pembangun pemindai QR (bisa diganti di test): menerima callback yang
/// dipanggil dengan teks mentah hasil pindai.
typedef QuickSyncScannerBuilder = Widget Function(
    BuildContext context, void Function(String raw) onRaw);

class QuickSyncDialog extends ConsumerStatefulWidget {
  const QuickSyncDialog({super.key, this.scannerBuilder});

  /// Hanya untuk test: pengganti kamera sungguhan.
  final QuickSyncScannerBuilder? scannerBuilder;

  @override
  ConsumerState<QuickSyncDialog> createState() => _QuickSyncDialogState();
}

class _QuickSyncDialogState extends ConsumerState<QuickSyncDialog> {
  static const _prefIp = 'quick_sync_last_ip';
  static const _prefToken = 'quick_sync_last_token';

  final _ipCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  late QuickSyncMode _mode;
  String? _error;
  bool _scanned = false;
  bool _cameraError = false;
  MobileScannerController? _cam;

  @override
  void initState() {
    super.initState();
    _mode = ref.read(deviceProvider).isOwner
        ? QuickSyncMode.host
        : QuickSyncMode.client;
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
    _cam?.dispose();
    _ipCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _setMode(QuickSyncMode m) {
    if (m == _mode) return;
    // Kamera hanya hidup di tampilan Klien.
    if (m == QuickSyncMode.host) {
      _cam?.dispose();
      _cam = null;
    }
    setState(() {
      _mode = m;
      _error = null;
    });
  }

  /// Hasil pindai QR host: JSON `{"ip":"192.168.1.5:8625","key":"TOKEN"}`.
  void _handleRaw(String raw) {
    if (_scanned) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return;
      var ip = data['ip'] as String? ?? '';
      final key = data['key'] as String? ?? '';
      if (ip.contains(':')) ip = ip.split(':').first;
      if (ip.isEmpty || key.isEmpty) return;
      _ipCtrl.text = ip;
      _tokenCtrl.text = key.toUpperCase();
      // Kamera dimatikan begitu host terdeteksi.
      _cam?.dispose();
      _cam = null;
      setState(() {
        _scanned = true;
        _error = null;
      });
      HapticFeedback.selectionClick();
    } catch (_) {
      // Bukan QR host - abaikan, tunggu pindai berikutnya.
    }
  }

  void _rescan() => setState(() {
        _scanned = false;
        _cameraError = false;
      });

  Future<void> _sync() async {
    final ip = _ipCtrl.text.trim();
    final token = _tokenCtrl.text.trim().toUpperCase();
    if (ip.isEmpty || token.isEmpty) {
      setState(() => _error = 'Pindai QR host atau isi IP dan Token dulu');
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

  // ── Tampilan ──────────────────────────────────────────────────────────

  Widget _camera(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final builder = widget.scannerBuilder;
    Widget view;
    if (builder != null) {
      view = builder(context, _handleRaw);
    } else if (_cameraError) {
      view = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Kamera tidak bisa dipakai. Isi IP dan Token secara manual.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ),
      );
    } else {
      _cam ??= MobileScannerController();
      view = AppScanner(
        controller: _cam!,
        lockDelay: const Duration(milliseconds: 1000),
        accept: (b) {
          try {
            final d = jsonDecode(b.rawValue ?? '');
            return d is Map && d['ip'] != null;
          } catch (_) {
            return false;
          }
        },
        // Bingkai persegi lama; dimatikan bila mode Telegram aktif.
        legacyOverlay: IgnorePointer(
          child: Center(
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        onDetect: (capture) {
          final raw = capture.barcodes.firstOrNull?.rawValue;
          if (raw != null && raw.isNotEmpty) _handleRaw(raw);
        },
        errorBuilder: (context, error, child) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_cameraError) setState(() => _cameraError = true);
          });
          return const SizedBox.shrink();
        },
      );
    }
    return Container(
      key: const Key('quick-sync-camera'),
      height: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          view,
          const Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Text(
              'Arahkan ke QR di perangkat host',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scannedTile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const Key('quick-sync-scanned'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.changeBg(dark),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: AppTheme.changeFg(dark)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Host terdeteksi',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                Text(_ipCtrl.text,
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          TextButton(
            key: const Key('quick-sync-rescan'),
            onPressed: _rescan,
            child: const Text('Pindai ulang'),
          ),
        ],
      ),
    );
  }

  Widget _hostView(BuildContext context, SyncState sync) {
    final cs = Theme.of(context).colorScheme;
    final waiting = sync.queue.length +
        sync.proposals.length +
        sync.laciMejaProposals.length;
    return Column(
      key: const Key('quick-sync-host-view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          const SizedBox(height: 12),
          Center(
            child: QrSyncDisplay(
              key: const Key('quick-sync-qr'),
              data: {'ip': '${sync.hostIp}:8625', 'key': sync.hostToken},
              size: 168,
            ),
          ),
          const SizedBox(height: 8),
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
      ],
    );
  }

  Widget _clientView(BuildContext context, SyncState sync) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const Key('quick-sync-client-view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_scanned) _scannedTile(context) else _camera(context),
        const SizedBox(height: 4),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('quick-sync-manual'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            initiallyExpanded: _cameraError,
            title: const Text('Isi manual (IP & Token)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            children: [
              TextField(
                key: const Key('quick-sync-ip'),
                controller: _ipCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'IP Host', isDense: true),
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
            ],
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final device = ref.watch(deviceProvider);
    final sync = ref.watch(syncStateProvider);
    final isHost = _mode == QuickSyncMode.host;

    return AlertDialog(
      key: const Key('quick-sync-dialog'),
      title: const Text('Sync LAN'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<QuickSyncMode>(
                  key: const Key('quick-sync-mode'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: QuickSyncMode.host,
                      label: const Text('Host'),
                      icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                      // Host hanya owner (sumber kebenaran master data).
                      enabled: device.isOwner,
                    ),
                    const ButtonSegment(
                      value: QuickSyncMode.client,
                      label: Text('Klien'),
                      icon: Icon(Icons.qr_code_scanner_rounded, size: 18),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) => _setMode(v.first),
                ),
              ),
              if (!device.isOwner)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Hanya owner yang dapat menjadi host.',
                      style: TextStyle(
                          fontSize: 11.5, color: cs.onSurfaceVariant)),
                ),
              const SizedBox(height: 14),
              if (isHost) _hostView(context, sync) else _clientView(context, sync),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(color: cs.error, fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ),
      // Dua tombol sebaris sempit (aturan dialog: jangan 3 tombol).
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tutup'),
        ),
        if (!isHost)
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
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: 'Salin $label',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context)
                  .showAppSnackBar(SnackBar(content: Text('$label disalin')));
            },
          ),
        ],
      ),
    );
  }
}
