import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/device_provider.dart';

/// Item 41 A.6 — layar pemulihan saat identitas device PERNAH ada
/// (storeUuid tersimpan) tapi kunci toko tidak terbaca dari secure storage
/// (keystore error — kasus nyata sebagian Transsion/Infinix — atau storage
/// terhapus). Dulu kondisi ini jatuh diam-diam ke /setup: user yang panik
/// bisa "Setup Toko Baru" → storeKey baru dibuat → DB lama permanen tak
/// terbuka, terlihat sbg "data toko hilang semua".
///
/// Di sini user diberi 2 jalan yang sadar-konsekuensi:
///  1. "Coba Lagi" — muat ulang identitas (keystore error sering transien,
///     mis. setelah restart HP kunci terbaca lagi).
///  2. "Reset & Setup Ulang" — konfirmasi ganda, baru identitas dihapus dan
///     diarahkan ke /setup (data lama memang tak terselamatkan tanpa kunci,
///     tapi ini jadi keputusan EKSPLISIT user, bukan kecelakaan).
class StoreKeyLostScreen extends ConsumerStatefulWidget {
  const StoreKeyLostScreen({super.key});

  @override
  ConsumerState<StoreKeyLostScreen> createState() => _StoreKeyLostScreenState();
}

class _StoreKeyLostScreenState extends ConsumerState<StoreKeyLostScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    await ref.read(deviceProvider.notifier).load();
    if (!mounted) return;
    setState(() => _busy = false);
    // Redirect router yang memutuskan: kalau kunci sudah terbaca lagi,
    // /kasir lolos; kalau belum, balik ke layar ini.
    context.go('/kasir');
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Identitas Device?'),
        content: const Text(
            'Data toko di device ini TIDAK akan bisa dibuka lagi tanpa kunci '
            'yang hilang. Lanjutkan hanya bila Anda punya file backup '
            '(.berkahpos) atau siap mulai dari nol.\n\n'
            'Identitas device akan dihapus dan Anda diarahkan ke Setup.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await ref.read(deviceProvider.notifier).resetIdentity();
    if (!mounted) return;
    context.go('/setup');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final device = ref.watch(deviceProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.key_off_outlined, size: 72, color: scheme.error),
              const SizedBox(height: 24),
              Text(
                'Kunci Toko Tidak Terbaca',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Device ini sudah pernah di-setup'
                '${device.storeName.isNotEmpty ? ' untuk toko "${device.storeName}"' : ''}, '
                'tapi kunci penyimpanan amannya tidak bisa dibaca. Ini bisa '
                'terjadi karena gangguan sistem keamanan HP (biasanya '
                'sementara).\n\n'
                'Coba mulai ulang (restart) HP lalu tekan "Coba Lagi". '
                'JANGAN reset kecuali benar-benar terpaksa — data toko tidak '
                'bisa dibuka tanpa kunci ini.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 40),
              FilledButton.icon(
                onPressed: _busy ? null : _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba Lagi'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _reset,
                icon: Icon(Icons.restart_alt, color: scheme.error),
                label: Text('Reset & Setup Ulang',
                    style: TextStyle(color: scheme.error)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
