import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/device_provider.dart';

class SetupTokoScreen extends ConsumerStatefulWidget {
  const SetupTokoScreen({super.key});

  @override
  ConsumerState<SetupTokoScreen> createState() => _SetupTokoScreenState();
}

class _SetupTokoScreenState extends ConsumerState<SetupTokoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storeName = TextEditingController();
  final _deviceName = TextEditingController(text: 'Owner');
  final _deviceCode = TextEditingController(text: 'O1');
  bool _saving = false;

  @override
  void dispose() {
    _storeName.dispose();
    _deviceName.dispose();
    _deviceCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref.read(deviceProvider.notifier).setupNewStore(
          storeName: _storeName.text.trim(),
          deviceName: _deviceName.text.trim(),
          deviceCode: _deviceCode.text.trim().toUpperCase(),
        );
    if (mounted) context.go('/kasir');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Toko Baru'),
        leading: BackButton(onPressed: () => context.go('/setup')),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Device ini akan menjadi HP Owner. Kunci toko (store key) '
                'dibuat otomatis dan database terenkripsi penuh.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _storeName,
                decoration: const InputDecoration(
                  labelText: 'Nama Toko',
                  hintText: 'mis. Berkah Grosir',
                ),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nama toko wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _deviceName,
                decoration: const InputDecoration(labelText: 'Nama Device'),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nama device wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _deviceCode,
                decoration: const InputDecoration(
                  labelText: 'Kode Device',
                  hintText: 'mis. O1',
                  helperText: 'Dipakai sebagai prefix nomor transaksi (O1-20260611-0001)',
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 4,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Kode device wajib diisi' : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Buat Toko & Mulai'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
