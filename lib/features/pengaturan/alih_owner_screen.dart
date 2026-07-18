import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/db_export_service.dart';
import '../../core/widgets/inline_banner.dart';

/// Item 27 "Alihkan Owner" — pindahkan SELURUH data + identitas toko (bukan
/// cuma data) ke device lain lewat file terenkripsi (BPOT1), TERPISAH dari
/// "Backup & Restore" biasa (`.berkahpos`/BPOP2, sengaja lintas-toko & TIDAK
/// membawa identitas — lihat komentar `DbExportService`). Device penerima
/// boleh device MANAPUN (baru atau yang sudah aktif dipakai kasir/asisten/
/// owner toko lain) — data & identitas LAMA device penerima akan DITIMPA
/// TOTAL, makanya alur import di sini sengaja lebih "berat" (peringatan +
/// centang konfirmasi) dibanding restore biasa.
class AlihOwnerScreen extends ConsumerStatefulWidget {
  const AlihOwnerScreen({super.key});

  @override
  ConsumerState<AlihOwnerScreen> createState() => _AlihOwnerScreenState();
}

class _AlihOwnerScreenState extends ConsumerState<AlihOwnerScreen>
    with InlineBannerStateMixin<AlihOwnerScreen> {
  bool _busy = false;

  Future<void> _export() async {
    final device = ref.read(deviceProvider);
    final pwCtrl = TextEditingController();
    // Item 41 B.5 — file BPOT1 membawa storeKey; kekuatannya = kekuatan
    // password ini. Minimal 8 karakter utk ekspor baru (impor file lama
    // ber-password pendek tetap diterima).
    String? pwError;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Password File Alihan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Masukkan password untuk mengenkripsi file. File ini membawa '
                'SELURUH data DAN identitas toko ini — device yang membuka file '
                'ini akan "menjadi" toko ini.',
                style: TextStyle(fontSize: 13),
              ),
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
      final bytes = await DbExportService.exportOwnerTransfer(
        db: db,
        password: password,
        storeUuid: device.storeUuid!,
        storeKey: device.storeKey!,
        storeName: device.storeName,
      );

      final now = DateTime.now();
      final fname =
          'alihkan_owner_${now.year}${_p(now.month)}${_p(now.day)}.berkahpos';
      await FilePicker.platform.saveFile(
        fileName: fname,
        bytes: bytes,
        type: FileType.any,
      );
      if (!mounted) return;
      showSuccess('File alihan berhasil dibuat');
    } catch (e) {
      if (!mounted) return;
      showError('Gagal membuat file: $e');
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
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Password File Alihan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Masukkan password file alihan owner.',
                style: TextStyle(fontSize: 13)),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              final v = pwCtrl.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    Map<String, dynamic>? payload;
    String? storeUuid, storeKey, storeName;
    try {
      final device = ref.read(deviceProvider);
      final decrypted = await DbExportService.decrypt(
        fileBytes: fileBytes,
        storeKey: device.storeKey ?? '',
        storeUuid: device.storeUuid ?? '',
        password: password,
      );
      if (!decrypted.isOwnerTransfer) {
        throw BackupException(
            'File ini adalah backup biasa (.berkahpos), bukan file Alihan '
            'Owner. Gunakan Pengaturan → Backup & Restore.');
      }
      payload = decrypted.payload;
      storeUuid = payload['storeUuid'] as String;
      storeKey = payload['storeKey'] as String;
      storeName = payload['storeName'] as String;
    } on BackupException catch (e) {
      if (mounted) showError(e.message);
      setState(() => _busy = false);
      return;
    } catch (e) {
      if (mounted) showError('Gagal membaca file: $e');
      setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final confirmed = await _confirmDestructive(storeName);
    if (confirmed != true || !mounted) return;

    // Susulan (bug ditemukan user via testing device asli): device penerima
    // WAJIB diberi nama/kode BARU, bukan otomatis warisi punya lama —
    // `deviceCode` dipakai sbg prefix nomor transaksi yang harus UNIK per
    // device DALAM SATU toko. Kalau device eks-kasir toko lain (mis. kode
    // "K1") reuse kode lamanya sbg owner toko BARU, bisa tabrakan dgn device
    // lain yang sudah pairing ke toko tujuan pakai kode yang sama.
    final identity = await _promptDeviceIdentity();
    if (identity == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      await DbExportService.restore(db: db, payload: payload);
      await ref.read(deviceProvider.notifier).applyOwnerTransferInPlace(
            db: db,
            storeUuid: storeUuid,
            storeKey: storeKey,
            storeName: storeName,
            deviceName: identity.name,
            deviceCode: identity.code,
          );
      if (!mounted) return;
      showSuccess(
          'Berhasil menjadi "$storeName". Tutup & buka ulang aplikasi.');
    } catch (e) {
      if (!mounted) return;
      showError('Gagal menerapkan alihan: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<({String name, String code})?> _promptDeviceIdentity() {
    final nameCtrl = TextEditingController(text: 'Owner');
    final codeCtrl = TextEditingController(text: 'O1');
    final formKey = GlobalKey<FormState>();
    return showDialog<({String name, String code})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Identitas Perangkat'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Beri nama & kode BARU untuk device ini sebagai owner toko '
                'yang baru — jangan pakai kode lama, harus unik dari device '
                'lain di toko ini.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama Device', isDense: true),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nama device wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Kode Device',
                  hintText: 'mis. O1',
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 4,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Kode device wajib diisi' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx, (
                name: nameCtrl.text.trim(),
                code: codeCtrl.text.trim().toUpperCase(),
              ));
            },
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDestructive(String storeName) {
    final ackNotifier = ValueNotifier(false);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Konfirmasi Alihkan Owner'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Device ini akan menjadi "$storeName". SELURUH data & '
                'identitas toko device ini SAAT INI akan DIHAPUS TOTAL dan '
                'digantikan sepenuhnya — termasuk kalau device ini sedang '
                'aktif dipakai toko lain. Operasi ini tidak bisa dibatalkan.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: ackNotifier.value,
                title: const Text(
                  'Saya sudah memastikan data device ini sudah ter-sync '
                  '(kalau ada), dan siap ditimpa total.',
                  style: TextStyle(fontSize: 12),
                ),
                onChanged: (v) => setSt(() => ackNotifier.value = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed:
                  ackNotifier.value ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Ya, Alihkan'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final device = ref.watch(deviceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Alihkan Owner')),
      body: Column(
        children: [
          inlineBanner(),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (device.isOwner) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Icon(Icons.upload_outlined,
                                      color: scheme.primary),
                                  const SizedBox(width: 8),
                                  Text('Buat File Alihan',
                                      style:
                                          Theme.of(context).textTheme.titleMedium),
                                ]),
                                const SizedBox(height: 8),
                                Text(
                                  'Ekspor SELURUH data & identitas toko ini ke '
                                  'file. Device lain yang membuka file ini '
                                  '(dengan password yang benar) akan "menjadi" '
                                  'toko ini sepenuhnya.',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: scheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _export,
                                  icon: const Icon(Icons.save_alt_outlined),
                                  label: const Text('Buat File Alihan'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.download_outlined,
                                    color: scheme.error),
                                const SizedBox(width: 8),
                                Text('Terima Alihan',
                                    style: Theme.of(context).textTheme.titleMedium),
                              ]),
                              const SizedBox(height: 8),
                              Text(
                                'Device ini akan "menjadi" toko dari file yang '
                                'dipilih — data & identitas toko device ini '
                                'SAAT INI (kalau ada) akan ditimpa total.',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant),
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
                                          fontSize: 11,
                                          color: scheme.onErrorContainer),
                                    ),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _import,
                                icon: const Icon(Icons.restore_outlined),
                                label: const Text('Pilih File & Terima'),
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
