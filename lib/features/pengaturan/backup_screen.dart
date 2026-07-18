import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/backup_reminder.dart';
import '../../core/services/db_export_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/export_destination.dart';
import '../../core/widgets/inline_banner.dart';

/// Status backup (waktu terakhir + setting otomatis) untuk kartu pengingat.
final _backupStatusProvider = FutureProvider.autoDispose<BackupStatus>((ref) {
  return BackupReminder.load(ref.watch(databaseProvider));
});

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
    // Item 41 B.5 — password ekspor minimal 8 karakter: kekuatan enkripsi
    // file backup = kekuatan password ini (BPOP2 murni dari password).
    // HANYA berlaku utk ekspor baru — impor file lama ber-password pendek
    // tetap diterima (lihat _import, tanpa batasan).
    String? pwError;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'Minimal 8 karakter',
                  errorText: pwError,
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                if (pwCtrl.text.trim().length < 8) {
                  setDialogState(
                      () => pwError = 'Password minimal 8 karakter');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Lanjutkan'),
            ),
          ],
        ),
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
      if (!mounted) return;
      final done = await saveOrShareExport(
        context: context,
        bytes: bytes,
        fileName: fname,
        shareText: 'Backup data toko',
      );
      if (!done) return;

      await BackupReminder.recordBackupNow(db); // Item 13: catat waktu backup
      ref.invalidate(_backupStatusProvider);
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
      final decrypted = await DbExportService.decrypt(
        fileBytes: fileBytes,
        storeKey: device.storeKey!,
        storeUuid: device.storeUuid!,
        password: password,
      );
      if (decrypted.isOwnerTransfer) {
        // File "Alihkan Owner" (BPOT1) butuh alur berbeda (rekey + ganti
        // identitas device) — arahkan ke layar khusus, bukan restore biasa.
        throw BackupException(
            'File ini berformat "Alihkan Owner". Gunakan Pengaturan → '
            'Alihkan Owner untuk memulihkannya, bukan Backup & Restore biasa.');
      }
      await DbExportService.restore(db: db, payload: decrypted.payload);
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
                _BackupStatusCard(
                  onToggleAuto: (v) async {
                    final db = ref.read(databaseProvider);
                    await BackupReminder.setAutoEnabled(db, v);
                    ref.invalidate(_backupStatusProvider);
                  },
                  onIntervalChanged: (d) async {
                    final db = ref.read(databaseProvider);
                    await BackupReminder.setIntervalDays(db, d);
                    ref.invalidate(_backupStatusProvider);
                  },
                ),
                const SizedBox(height: 12),
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

/// Item 13 — kartu status backup: kapan terakhir backup (warna sesuai usia) +
/// toggle pengingat otomatis + interval.
class _BackupStatusCard extends ConsumerWidget {
  const _BackupStatusCard(
      {required this.onToggleAuto, required this.onIntervalChanged});

  final ValueChanged<bool> onToggleAuto;
  final ValueChanged<int> onIntervalChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusAsync = ref.watch(_backupStatusProvider);

    return statusAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (s) {
        final days = s.daysSince;
        final Color ageColor;
        final String lastLabel;
        if (days == null) {
          ageColor = AppTheme.debtFg(isDark);
          lastLabel = 'Belum pernah backup';
        } else if (days == 0) {
          ageColor = AppTheme.changeFg(isDark);
          lastLabel = 'Backup terakhir: hari ini';
        } else {
          ageColor = days >= (s.autoEnabled ? s.intervalDays : 7)
              ? AppTheme.debtFg(isDark)
              : (days >= 3
                  ? (isDark ? const Color(0xFFF0B54A) : const Color(0xFFB8791A))
                  : scheme.onSurfaceVariant);
          lastLabel = 'Backup terakhir: $days hari lalu';
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.history_outlined, size: 18, color: ageColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(lastLabel,
                          style: TextStyle(
                              fontWeight: FontWeight.w600, color: ageColor)),
                    ),
                  ],
                ),
                const Divider(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pengingat Backup Otomatis'),
                  subtitle: const Text(
                      'Ingatkan saat aplikasi dibuka bila sudah lama tak backup',
                      style: TextStyle(fontSize: 11)),
                  value: s.autoEnabled,
                  onChanged: onToggleAuto,
                ),
                if (s.autoEnabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Text('Ingatkan tiap'),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: s.intervalDays,
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('Harian')),
                            DropdownMenuItem(value: 7, child: Text('Mingguan')),
                          ],
                          onChanged: (v) {
                            if (v != null) onIntervalChanged(v);
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
