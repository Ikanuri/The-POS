import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/pairing_service.dart';

/// "Gabung Toko": scan QR pairing dari HP owner, atau tempel kode manual.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _manualController = TextEditingController();
  bool _processing = false;
  String? _error;

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _handlePayload(String raw) async {
    if (_processing) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final payload = PairingService.validate(raw.trim());
      if (payload == null) {
        setState(() => _error = 'QR tidak valid. Pastikan scan QR pairing dari HP owner.');
        return;
      }
      await ref.read(deviceProvider.notifier).joinStore(
            storeUuid: payload.storeUuid,
            storeKey: payload.storeKey,
            storeName: payload.storeName,
            role: payload.role,
            deviceName: payload.deviceName,
            deviceCode: payload.deviceCode,
          );
      if (mounted) context.go('/kasir');
    } on PairingExpiredException catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    child: const Text('Gabung dengan Kode'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
