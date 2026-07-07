import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/pairing_service.dart';
import '../../core/widgets/inline_banner.dart';

class PairDeviceScreen extends ConsumerStatefulWidget {
  const PairDeviceScreen({super.key});

  @override
  ConsumerState<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends ConsumerState<PairDeviceScreen>
    with InlineBannerStateMixin<PairDeviceScreen> {
  String? _qrData;
  DateTime? _expiresAt;
  bool _generating = false;
  String _selectedRole = 'kasir';

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final device = ref.read(deviceProvider);
      final payload = PairingService.generate(
        storeUuid: device.storeUuid!,
        storeKey: device.storeKey!,
        storeName: device.storeName,
        role: _selectedRole,
      );
      setState(() {
        _qrData = payload.encode();
        _expiresAt = payload.expiresAt;
      });
    } catch (e) {
      if (mounted) showError('Error: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final device = ref.watch(deviceProvider);

    if (!device.isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pair Device')),
        body: const Center(
          child: Text('Hanya Owner yang bisa generate QR pairing'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pair Device Baru')),
      body: Column(
        children: [
          inlineBanner(),
          Expanded(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Pilih role untuk device yang akan di-pair:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Kasir'),
                  selected: _selectedRole == 'kasir',
                  onSelected: (_) =>
                      setState(() => _selectedRole = 'kasir'),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('Asisten'),
                  selected: _selectedRole == 'asisten',
                  onSelected: (_) =>
                      setState(() => _selectedRole = 'asisten'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (_qrData != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: _qrData!,
                  size: 240,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              if (_expiresAt != null)
                _CountdownTimer(expiresAt: _expiresAt!),
              const SizedBox(height: 12),
              Text(
                'QR berlaku 5 menit. Scan dari device kasir via Pengaturan → Gabung Toko.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _qrData!));
                  showSuccess('Kode disalin ke clipboard');
                },
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Salin Kode'),
              ),
            ] else ...[
              Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.qr_code_2_outlined,
                    size: 80, color: scheme.outlineVariant),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _generating ? null : _generate,
              icon: _generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                          CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_qrData == null ? 'Generate QR' : 'Buat Ulang QR'),
            ),
          ],
        ),
      )),
        ],
      ),
    );
  }
}

class _CountdownTimer extends StatefulWidget {
  const _CountdownTimer({required this.expiresAt});
  final DateTime expiresAt;

  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    final remaining = widget.expiresAt.difference(DateTime.now());
    if (mounted) {
      setState(() => _remaining = remaining.isNegative ? Duration.zero : remaining);
      if (remaining.isNegative) return;
      Future.delayed(const Duration(seconds: 1), _tick);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mins = _remaining.inMinutes.toString().padLeft(2, '0');
    final secs = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    final expired = _remaining == Duration.zero;

    return Text(
      expired ? 'QR sudah kadaluarsa' : 'Berlaku: $mins:$secs',
      style: TextStyle(
          color: expired ? scheme.error : scheme.primary,
          fontWeight: FontWeight.w600),
    );
  }
}
