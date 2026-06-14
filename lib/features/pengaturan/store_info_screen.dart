import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/device_provider.dart';
import '../../core/widgets/inline_banner.dart';

class StoreInfoScreen extends ConsumerStatefulWidget {
  const StoreInfoScreen({super.key});

  @override
  ConsumerState<StoreInfoScreen> createState() => _StoreInfoScreenState();
}

class _StoreInfoScreenState extends ConsumerState<StoreInfoScreen>
    with InlineBannerStateMixin<StoreInfoScreen> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _strukturCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = ref.read(deviceProvider).storeName;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = ref.read(databaseProvider);
    final address = await db.getSetting('store_address') ?? '';
    final phone = await db.getSetting('store_phone') ?? '';
    final note = await db.getSetting('receipt_note') ?? '';
    if (mounted) {
      setState(() {
        _addressCtrl.text = address;
        _phoneCtrl.text = phone;
        _strukturCtrl.text = note;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _strukturCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      showError('Nama toko wajib diisi');
      return;
    }
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final name = _nameCtrl.text.trim();
      await db.setSetting('store_name', name);
      await db.setSetting('store_address', _addressCtrl.text.trim());
      await db.setSetting('store_phone', _phoneCtrl.text.trim());
      await db.setSetting('receipt_note', _strukturCtrl.text.trim());
      await ref.read(deviceProvider.notifier).updateStoreName(name);
      if (mounted) {
        showSuccess('Informasi toko disimpan');
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) context.pop();
        });
      }
    } catch (e) {
      if (mounted) showError('Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informasi Toko')),
      body: Column(
        children: [
          inlineBanner(),
          Expanded(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nama Toko *',
              hintText: 'Contoh: Berkah Grosir',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _addressCtrl,
            decoration: const InputDecoration(
              labelText: 'Alamat',
              hintText: 'Jl. Contoh No. 1',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(
              labelText: 'Telepon',
              hintText: '0xx-xxxx-xxxx',
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _strukturCtrl,
            decoration: const InputDecoration(
              labelText: 'Catatan di Struk',
              hintText: 'Terima kasih telah berbelanja…',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 80),
        ],
      )),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Simpan'),
        ),
      ),
    );
  }
}
