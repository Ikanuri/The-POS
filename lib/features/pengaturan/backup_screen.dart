import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/db_export_service.dart';
import '../../core/widgets/inline_banner.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen>
    with InlineBannerStateMixin<BackupScreen> {
  bool _busy = false;

  Future<void> _export() async {
    final pwCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Password Backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Masukkan password untuk mengenkripsi file backup.'),
            const SizedBox(height: 12),
            TextField(
              controller: pwCtrl,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              if (pwCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final password = pwCtrl.text.trim();
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      // exportPortable (BPOP2): key hanya dari password, TIDAK diikat
      // storeKey toko ini. Backup harus bisa direstore di device/toko lain
      // (mis. HP baru setelah HP lama hilang/rusak) — kalau diikat storeKey
      // toko asal (format BPOS1 lama), restore di toko/device manapun selain
      // toko asal PASTI gagal "password salah" walau password benar, karena
      // storeKey toko tujuan (acak, di-generate ulang tiap setup) tidak
      // mungkin sama dengan storeKey toko asal.
      final bytes = await DbExportService.exportPortable(
        db: db,
        password: password,
      );

      final now = DateTime.now();
      final fname =
          'backup_${now.year}${_p(now.month)}${_p(now.day)}.berkahpos';
      await FilePicker.platform.saveFile(
        fileName: fname,
        bytes: bytes,
        type: FileType.any,
      );

      if (!mounted) return;
      showSuccess('Backup berhasil disimpan');
    } catch (e) {
      if (!mounted) return;
      showError('Gagal backup: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final fileBytes = result.files.single.bytes!;

    final pwCtrl = TextEditingController();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Password Restore'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Masukkan password file backup.\n\nPeringatan: data saat ini akan ditimpa.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pwCtrl,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              if (pwCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final password = pwCtrl.text.trim();
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      final device = ref.read(deviceProvider);
      final db = ref.read(databaseProvider);
      final payload = await DbExportService.decrypt(
        fileBytes: fileBytes,
        storeKey: device.storeKey!,
        storeUuid: device.storeUuid!,
        password: password,
      );
      await DbExportService.restore(db: db, payload: payload);
      if (!mounted) return;
      // Sebagian layar (mis. Ringkasan, grup produk) memakai cache sekali-
      // ambil yang tidak auto-refresh dari perubahan DB mendadak sebesar ini
      // (beda dengan daftar produk/pelanggan yang live-update). Sarankan
      // restart agar semua layar pasti konsisten dengan data baru.
      showSuccess(
          'Data berhasil di-restore. Tutup & buka ulang aplikasi agar semua layar menampilkan data terbaru.');
    } on BackupException catch (e) {
      if (!mounted) return;
      showError(e.message);
    } catch (e) {
      if (!mounted) return;
      showError('Gagal restore: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Column(
        children: [
          inlineBanner(),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.upload_outlined, color: scheme.primary),
                          const SizedBox(width: 8),
                          Text('Export Backup',
                              style: Theme.of(context).textTheme.titleMedium),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          'Ekspor semua data ke file terenkripsi (.berkahpos). '
                          'File ini hanya bisa dibuka dengan password yang Anda tentukan.',
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _export,
                          icon: const Icon(Icons.save_alt_outlined),
                          label: const Text('Buat Backup'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.download_outlined, color: scheme.error),
                          const SizedBox(width: 8),
                          Text('Import / Restore',
                              style: Theme.of(context).textTheme.titleMedium),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          'Kembalikan data dari file backup .berkahpos. '
                          'Data saat ini akan ditimpa sepenuhnya.',
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 16, color: scheme.onErrorContainer),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Operasi ini tidak bisa dibatalkan.',
                                style: TextStyle(
                                    fontSize: 11, color: scheme.onErrorContainer),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _import,
                          icon: const Icon(Icons.restore_outlined),
                          label: const Text('Pilih File & Restore'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.error,
                            side: BorderSide(color: scheme.error),
                          ),
                        ),
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

  String _p(int n) => n.toString().padLeft(2, '0');
}
