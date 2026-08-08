import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/order_parse_diagnostics.dart';

/// Item 55 — halaman debug SEMENTARA, murni untuk investigasi bug "Tempel
/// Pesanan pegawai tidak dapat produk dari QR/teks owner". Tampilkan isi
/// [OrderParseDiagnostics.entries] terbaru dulu + tombol salin semua ke
/// clipboard, supaya user bisa langsung kirim balik isinya lewat chat —
/// TANPA baca/tulis file apa pun.
///
/// WAJIB DIHAPUS TOTAL begitu root cause bug Item 55 ketemu & fix-nya sudah
/// dieksekusi (lihat dok panjang di `order_parse_diagnostics.dart`).
class ParseDiagnosticsScreen extends StatelessWidget {
  const ParseDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(builder: (context, setSt) {
      final entries = OrderParseDiagnostics.entries.reversed.toList();
      return Scaffold(
        appBar: AppBar(
          title: const Text('Debug: Log Tempel Pesanan'),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy_all),
              tooltip: 'Salin Semua',
              onPressed: entries.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(
                          ClipboardData(text: entries.reversed.join('\n')));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Log disalin')),
                        );
                      }
                    },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Kosongkan',
              onPressed: () => setSt(OrderParseDiagnostics.clear),
            ),
          ],
        ),
        body: entries.isEmpty
            ? const Center(child: Text('Belum ada log — coba Tempel Pesanan.'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (context, i) => SelectableText(
                  entries[i],
                  style:
                      const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
      );
    });
  }
}
