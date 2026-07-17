import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/db_export_service.dart';

/// Item 27/28 — "Pulihkan dari File" di welcome screen: restore langsung
/// tanpa perlu bikin toko dummy dulu (`Setup Toko Baru`) sebelum bisa
/// restore. Menerima 2 jenis file:
///  - BPOT1 ("Alihkan Owner"): storeUuid/storeKey/storeName DARI FILE
///    langsung dipakai (device "menjadi" toko itu) — TIDAK perlu rekey DB
///    krn device ini belum pernah punya file DB (fresh), jadi key derivasi
///    baru otomatis jadi key pertama file itu ditulis.
///  - BPOP2 (`.berkahpos` biasa): TIDAK bawa identitas, jadi device ini bikin
///    identitas toko BARU (storeUuid/storeKey acak, spt "Setup Toko Baru")
///    lalu data dari file di-restore di atasnya.
class RestoreFileScreen extends ConsumerStatefulWidget {
  const RestoreFileScreen({super.key});

  @override
  ConsumerState<RestoreFileScreen> createState() => _RestoreFileScreenState();
}

class _RestoreFileScreenState extends ConsumerState<RestoreFileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storeName = TextEditingController();
  final _deviceName = TextEditingController(text: 'Owner');
  final _deviceCode = TextEditingController(text: 'O1');
  bool _busy = false;
  String? _error;

  /// Hasil decrypt file; null = masih di tahap pilih file.
  Map<String, dynamic>? _payload;
  bool _isOwnerTransfer = false;

  @override
  void dispose() {
    _storeName.dispose();
    _deviceName.dispose();
    _deviceCode.dispose();
    super.dispose();
  }

  Future<void> _pickAndDecrypt() async {
    final result =
        await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (result == null || result.files.single.bytes == null) return;
    final fileBytes = result.files.single.bytes!;

    final pwCtrl = TextEditingController();
    if (!mounted) return;
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Password File'),
        content: TextField(
          controller: pwCtrl,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password', isDense: true),
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

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final decrypted = await DbExportService.decrypt(
        fileBytes: fileBytes,
        storeKey: '',
        storeUuid: '',
        password: password,
      );
      if (decrypted.isOwnerTransfer) {
        _deviceName.text = 'Owner';
        _storeName.text = decrypted.payload['storeName'] as String? ?? '';
      }
      setState(() {
        _payload = decrypted.payload;
        _isOwnerTransfer = decrypted.isOwnerTransfer;
      });
    } on BackupException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Gagal membaca file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final payload = _payload;
    if (payload == null) return;

    setState(() => _busy = true);
    try {
      final notifier = ref.read(deviceProvider.notifier);
      if (_isOwnerTransfer) {
        await notifier.joinStore(
          storeUuid: payload['storeUuid'] as String,
          storeKey: payload['storeKey'] as String,
          storeName: payload['storeName'] as String,
          role: 'owner',
          deviceName: _deviceName.text.trim(),
          deviceCode: _deviceCode.text.trim().toUpperCase(),
        );
      } else {
        await notifier.setupNewStore(
          storeName: _storeName.text.trim(),
          deviceName: _deviceName.text.trim(),
          deviceCode: _deviceCode.text.trim().toUpperCase(),
        );
      }
      final db = ref.read(databaseProvider);
      await DbExportService.restore(db: db, payload: payload);
      if (mounted) context.go('/kasir');
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal restore: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Kembali dari form identitas ke tahap pilih file.
  void _backToPick() {
    setState(() {
      _payload = null;
      _isOwnerTransfer = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_payload != null) return _buildIdentityForm(context);
    return _buildPickFile(context);
  }

  Widget _buildPickFile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pulihkan dari File'),
        leading: BackButton(onPressed: () => context.go('/setup')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pilih file backup (.berkahpos) atau file Alihan Owner untuk '
                'langsung memulihkan data ke device ini, tanpa perlu setup '
                'toko baru dulu.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(_error!,
                    style: TextStyle(color: scheme.error, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: _busy ? null : _pickAndDecrypt,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.folder_open_outlined),
                label: const Text('Pilih File'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentityForm(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Identitas Perangkat'),
        leading: BackButton(onPressed: _busy ? null : _backToPick),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.storefront_outlined,
                        color: scheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isOwnerTransfer
                            ? 'File Alihan Owner terdeteksi — device ini akan '
                                'menjadi "${_payload!['storeName']}" (Owner).'
                            : 'File backup biasa terdeteksi — device ini akan '
                                'jadi toko BARU berisi data dari file ini.',
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(_error!,
                    style: TextStyle(color: scheme.error, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              if (!_isOwnerTransfer) ...[
                TextFormField(
                  controller: _storeName,
                  decoration: const InputDecoration(labelText: 'Nama Toko'),
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Nama toko wajib diisi'
                      : null,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _deviceName,
                decoration: const InputDecoration(labelText: 'Nama Device'),
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Nama device wajib diisi'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _deviceCode,
                decoration: const InputDecoration(
                  labelText: 'Kode Device',
                  hintText: 'mis. O1',
                  helperText: 'Dipakai sebagai prefix nomor transaksi',
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 4,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Kode device wajib diisi'
                    : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Pulihkan & Mulai'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
