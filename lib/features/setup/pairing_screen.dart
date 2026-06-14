import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/pairing_service.dart';

/// "Gabung Toko": scan QR pairing dari HP owner, atau tempel kode manual.
/// Setelah QR valid, perangkat ini mengisi nama & kode-nya sendiri — kode
/// dipakai sebagai prefix nomor nota, jadi harus unik per perangkat.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _manualController = TextEditingController();
  final _deviceName = TextEditingController();
  final _deviceCode = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _processing = false;
  String? _error;

  /// QR yang sudah tervalidasi; null = masih di tahap scan.
  PairingPayload? _payload;

  @override
  void dispose() {
    _manualController.dispose();
    _deviceName.dispose();
    _deviceCode.dispose();
    super.dispose();
  }

  Future<void> _handlePayload(String raw) async {
    if (_processing || _payload != null) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final payload = PairingService.validate(raw.trim());
      if (payload == null) {
        setState(() =>
            _error = 'QR tidak valid. Pastikan scan QR pairing dari HP owner.');
        return;
      }
      // Saran nama default berdasar role; perangkat bebas menggantinya.
      _deviceName.text = payload.role == 'asisten' ? 'Asisten' : 'Kasir';
      setState(() => _payload = payload);
    } on PairingExpiredException catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _join() async {
    final payload = _payload;
    if (payload == null) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _processing = true);
    try {
      await ref.read(deviceProvider.notifier).joinStore(
            storeUuid: payload.storeUuid,
            storeKey: payload.storeKey,
            storeName: payload.storeName,
            role: payload.role,
            deviceName: _deviceName.text.trim(),
            deviceCode: _deviceCode.text.trim().toUpperCase(),
          );
      if (mounted) context.go('/kasir');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Kembali dari form identitas ke tahap scan.
  void _backToScan() {
    setState(() {
      _payload = null;
      _error = null;
      _manualController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_payload != null) return _buildIdentityForm(context);
    return _buildScanner(context);
  }

  Widget _buildScanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gabung Toko'),
        leading: BackButton(onPressed: () => context.go('/setup')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: MobileScanner(
                    onDetect: (capture) {
                      final value = capture.barcodes.firstOrNull?.rawValue;
                      if (value != null) _handlePayload(value);
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.error, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    'Arahkan kamera ke QR di HP owner\n(Pengaturan → Pair Device Baru)',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _manualController,
                    decoration: const InputDecoration(
                      labelText: 'Atau tempel kode pairing manual',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _processing
                        ? null
                        : () => _handlePayload(_manualController.text),
                    child: const Text('Lanjut'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityForm(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final payload = _payload!;
    final roleLabel = payload.role == 'asisten' ? 'Asisten' : 'Kasir';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identitas Perangkat'),
        leading: BackButton(onPressed: _processing ? null : _backToScan),
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
                    Icon(Icons.store_outlined,
                        color: scheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bergabung ke "${payload.storeName}" sebagai $roleLabel.',
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Beri nama & kode unik untuk perangkat ini. Kode dipakai sebagai '
                'awalan nomor nota, jadi harus berbeda dari perangkat lain.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
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
                  hintText: 'mis. K1',
                  helperText:
                      'Prefix nomor transaksi (K1-20260611-0001). Buat berbeda '
                      'dari perangkat lain.',
                  helperMaxLines: 2,
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 4,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Kode device wajib diisi'
                    : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _processing ? null : _join,
                child: _processing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Gabung Toko'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
