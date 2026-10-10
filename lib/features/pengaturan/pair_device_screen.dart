import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/pairing_service.dart';
import '../../core/widgets/app_filter_chip.dart';
import '../../core/widgets/app_form_section.dart';
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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: [
                AppFormSection(
                  title: 'Role device yang akan di-pair',
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppFilterChip(
                          label: 'Pegawai',
                          selected: _selectedRole == 'kasir',
                          onTap: () => setState(() => _selectedRole = 'kasir'),
                        ),
                        AppFilterChip(
                          label: 'Asisten',
                          selected: _selectedRole == 'asisten',
                          onTap: () =>
                              setState(() => _selectedRole = 'asisten'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (_qrData != null) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                  color: scheme.outlineVariant, width: 1),
                            ),
                            child: QrImageView(
                              data: _qrData!,
                              size: 232,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_expiresAt != null)
                            _CountdownTimer(expiresAt: _expiresAt!),
                          const SizedBox(height: 10),
                          Text(
                            'QR berlaku 5 menit. Scan dari device kasir via '
                            'Pengaturan → Gabung Toko.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _qrData!));
                              showSuccess('Kode disalin ke clipboard');
                            },
                            icon: const Icon(Icons.copy_outlined, size: 16),
                            label: const Text('Salin Kode'),
                          ),
                        ] else
                          Container(
                            width: 232,
                            height: 232,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(Icons.qr_code_2_outlined,
                                size: 80, color: scheme.outlineVariant),
                          ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _generating ? null : _generate,
                          icon: _generating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(_qrData == null
                              ? 'Generate QR'
                              : 'Buat Ulang QR'),
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
}

class _CountdownTimer extends StatefulWidget {
  const _CountdownTimer({required this.expiresAt});
  final DateTime expiresAt;

  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  late Duration _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    final remaining = widget.expiresAt.difference(DateTime.now());
    if (mounted) {
      setState(
          () => _remaining = remaining.isNegative ? Duration.zero : remaining);
      if (remaining.isNegative) return;
      _timer = Timer(const Duration(seconds: 1), _tick);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mins = _remaining.inMinutes.toString().padLeft(2, '0');
    final secs = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    final expired = _remaining == Duration.zero;

    final fg = expired ? scheme.error : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: fg.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        expired ? 'QR sudah kadaluarsa' : 'Berlaku: $mins:$secs',
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
