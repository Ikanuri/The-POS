import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../../core/providers/sync_state_provider.dart';
import '../../core/services/lan_sync_service.dart';
import '../../core/widgets/inline_banner.dart';
import '../../core/widgets/qr_sync_widgets.dart';
import 'product_proposal_review_screen.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

/// Item 21 (Fase 1) — layar ini TIDAK LAGI memiliki state sync (host
/// running/antrian/progres klien semua sekarang di `syncStateProvider`,
/// hidup sepanjang sesi app). Layar ini murni "viewer/controller": baca
/// state via `ref.watch(syncStateProvider)`, panggil method notifier utk
/// aksi. `dispose()` TIDAK LAGI mematikan host — beda dari perilaku lama
/// yang mematikan server total begitu owner pindah tab.
class _SyncScreenState extends ConsumerState<SyncScreen>
    with InlineBannerStateMixin<SyncScreen> {
  final _ipCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncStateProvider.notifier).loadTimeoutProfile();
    });
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshIp() async {
    final notifier = ref.read(syncStateProvider.notifier);
    final oldIp = ref.read(syncStateProvider).hostIp;
    try {
      await notifier.refreshIp();
      if (!mounted) return;
      final newIp = ref.read(syncStateProvider).hostIp;
      showSuccess(newIp != oldIp
          ? 'IP diperbarui: $newIp — bagikan ulang QR ke kasir'
          : 'IP masih sama: $newIp');
    } catch (e) {
      if (mounted) showError('Gagal refresh IP: $e');
    }
  }

  Future<void> _toggleHost() async {
    try {
      await ref.read(syncStateProvider.notifier).toggleHost();
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

    final notifier = ref.read(syncStateProvider.notifier);
    if (available.isEmpty) {
      // Tidak ada data append-only untuk diterima → buang dari antrian.
      notifier.rejectSync(item.id);
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
      notifier.rejectSync(item.id);
      if (mounted) showSuccess('Tidak ada kategori dipilih — sync dilewati');
      return;
    }

    try {
      final received =
          await notifier.approveSync(item.id, allowedTables: allowed);
      if (mounted) showSuccess('Sync disetujui · $received baris diterima');
    } catch (e) {
      if (mounted) showError('Gagal merge: $e');
    }
  }

  /// Item 17 Fase 2 — "Tolak" sekarang PERMANEN (data tidak lagi otomatis
  /// kirim ulang lewat full-dump seperti dulu — lihat dok `LanSyncService.
  /// rejectSync`), jadi WAJIB minta konfirmasi eksplisit sebelum dieksekusi.
  Future<void> _reject(PendingSyncItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tolak Data Sync?'),
        content: Text(
          'Data dari ${item.fromIp} (${item.tablesSummary}) tidak akan '
          'otomatis diminta lagi setelah ditolak. Kalau berubah pikiran, '
          'gunakan "Sync Ulang Penuh" di perangkat pengirim untuk '
          'mengirimkannya lagi.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal')),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Tolak'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(syncStateProvider.notifier).rejectSync(item.id);
    if (mounted) showSuccess('Sync dari ${item.fromIp} ditolak');
  }

  /// "Sync Ulang Penuh" — escape hatch manual: reset watermark upload
  /// perangkat INI (klien) supaya sync berikutnya kirim ulang semua data
  /// sejak awal, bukan cuma delta. Dipakai kalau owner salah tolak (lihat
  /// dialog konfirmasi di atas) atau curiga ada data yang belum sampai.
  Future<void> _syncUlangPenuh() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync Ulang Penuh?'),
        content: const Text(
          'Perangkat ini akan mengirim SEMUA riwayat transaksi/stok dari '
          'awal lagi di sync berikutnya (bukan cuma data baru). Gunakan '
          'kalau curiga ada data yang belum pernah sampai ke host, atau '
          'setelah salah menolak antrian sync.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ya, Reset')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(syncStateProvider.notifier).resetUploadWatermark();
    if (mounted) {
      showSuccess('Sync berikutnya akan mengirim semua data dari awal');
    }
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
    try {
      await ref.read(syncStateProvider.notifier).sync(ip: ip, token: token);
    } catch (_) {
      // Pesan error sudah ditulis notifier ke state.clientResultMessage —
      // di sini cukup tangkap supaya tidak jadi unhandled exception.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final device = ref.watch(deviceProvider);
    final sync = ref.watch(syncStateProvider);

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
                    // Item 21 — host sekarang BERTAHAN lintas tab (tidak lagi
                    // mati begitu layar ini ditinggalkan), jadi peringatan
                    // "layar harus tetap menyala" ini sudah tidak berlaku
                    // sepenuhnya — TETAP ditampilkan krn OS masih bisa
                    // mematikan koneksi latar belakang saat app di-minimize/
                    // layar dikunci (di luar kendali app), bukan lagi krn
                    // navigasi tab di DALAM app.
                    if (sync.hostRunning) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 14, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Boleh pindah tab lain sambil menunggu — server '
                              'tetap jalan. Hindari mengunci layar/menutup '
                              'app sepenuhnya, sebagian HP mematikan koneksi '
                              'latar belakang otomatis.',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (sync.hostRunning) ...[
                      _InfoRow(
                        label: 'IP',
                        value: '${sync.hostIp}:8625',
                        onCopy: () => _copy('${sync.hostIp}:8625', 'IP'),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: sync.refreshingIp ? null : _refreshIp,
                          icon: sync.refreshingIp
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.refresh, size: 16),
                          label: const Text('Refresh IP',
                              style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 32),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _InfoRow(
                        label: 'Token',
                        value: sync.hostToken,
                        onCopy: () => _copy(sync.hostToken, 'Token'),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: QrSyncDisplay(data: {
                          'ip': '${sync.hostIp}:8625',
                          'key': sync.hostToken,
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
            if (sync.queue.isNotEmpty) ...[
              Row(children: [
                Icon(Icons.pending_actions_outlined,
                    color: scheme.tertiary, size: 18),
                const SizedBox(width: 6),
                Text('Menunggu Persetujuan (${sync.queue.length})',
                    style: Theme.of(context).textTheme.titleSmall),
              ]),
              const SizedBox(height: 6),
              ...sync.queue.map((item) {
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

            // Item 40 — antrian usulan harga/produk, TERPISAH dari antrian
            // data transaksi/stok di atas (independen, bisa ditinjau kapan
            // saja tanpa perlu setuju/tolak data append-only dulu).
            if (sync.proposals.isNotEmpty) ...[
              Row(children: [
                Icon(Icons.storefront_outlined,
                    color: scheme.tertiary, size: 18),
                const SizedBox(width: 6),
                Text('Usulan Harga/Produk (${sync.proposals.length})',
                    style: Theme.of(context).textTheme.titleSmall),
              ]),
              const SizedBox(height: 6),
              ...sync.proposals.map((p) {
                final mins =
                    DateTime.now().difference(p.arrivedAt).inMinutes;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(Icons.storefront_outlined,
                        color: scheme.tertiary),
                    title: Text(p.fromIp,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${p.productCount} produk diusulkan · '
                        '${mins == 0 ? 'Baru saja' : '$mins menit lalu'}',
                        style: const TextStyle(fontSize: 12)),
                    trailing: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ProductProposalReviewScreen(proposal: p),
                        ),
                      ),
                      child: const Text('Tinjau'),
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
                  DropdownButtonFormField<SyncTimeoutProfile>(
                    value: sync.timeoutProfile,
                    decoration: const InputDecoration(
                      labelText: 'Batas Waktu Tunggu (Timeout)',
                      isDense: true,
                    ),
                    items: SyncTimeoutProfile.values
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.label,
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (p) {
                      if (p == null) return;
                      ref.read(syncStateProvider.notifier).setTimeoutProfile(p);
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Naikkan kalau sync sering gagal timeout padahal jaringan '
                    'sebenarnya OK (mis. toko dgn riwayat data besar, atau '
                    'WiFi yang cenderung lemot).',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  if (sync.clientSyncing)
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
                  if (sync.clientResultMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: sync.clientResultMessage!.startsWith('Gagal')
                            ? scheme.errorContainer
                            : scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        sync.clientResultMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          color: sync.clientResultMessage!.startsWith('Gagal')
                              ? scheme.onErrorContainer
                              : scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: sync.clientSyncing ? null : _syncUlangPenuh,
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: const Text('Sync Ulang Penuh',
                          style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    ),
                  ),
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
