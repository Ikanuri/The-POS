import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/order_page_service.dart';

/// **EKSPERIMENTAL.** Generate & bagikan katalog pesanan HTML — file statis
/// self-contained (tanpa server/hosting) yang bisa dibuka pelanggan dari
/// WhatsApp untuk memilih barang sendiri, lalu kirim balik teks pesanan.
///
/// Sengaja TANPA hosting (keputusan user): tiap kali harga berubah, owner
/// perlu tekan "Buat & Bagikan" lagi dan kirim ulang file ke pelanggan
/// langganan secara manual — bukan link yang otomatis ter-update.
class OrderShareScreen extends ConsumerStatefulWidget {
  const OrderShareScreen({super.key});

  @override
  ConsumerState<OrderShareScreen> createState() => _OrderShareScreenState();
}

class _OrderShareScreenState extends ConsumerState<OrderShareScreen> {
  bool _generating = false;
  int? _lastProductCount;
  DateTime? _lastGeneratedAt;

  Future<void> _generateAndShare() async {
    if (_generating) return;
    setState(() => _generating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final db = ref.read(databaseProvider);
      final device = ref.read(deviceProvider);
      final storeName = (await db.getSetting('store_name'))?.trim();
      final storeWhatsapp =
          (await db.getSetting('store_whatsapp'))?.trim() ?? '';
      final name = (storeName == null || storeName.isEmpty)
          ? device.storeName
          : storeName;

      final result = await OrderPageService.generateHtml(
        db: db,
        storeName: name,
        storeWhatsapp: storeWhatsapp,
      );

      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/katalog_pesanan_$stamp.html');
      await file.writeAsString(result.html);

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/html')],
        text: 'Katalog pesanan $name — buka & pilih barang, lalu kirim '
            'balik pesanannya ke kami via WhatsApp.',
      );
      if (mounted) {
        setState(() {
          _lastProductCount = result.productCount;
          _lastGeneratedAt = DateTime.now();
        });
      }
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('Gagal membuat katalog: $e')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Katalog Pesanan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.science_outlined,
                    size: 14, color: scheme.onTertiaryContainer),
                const SizedBox(width: 5),
                Text('Eksperimental',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onTertiaryContainer)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cara kerja',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  const _StepLine(
                      no: 1,
                      text: 'Tekan "Buat & Bagikan" — satu file HTML berisi '
                          'seluruh katalog aktif (harga & varian) dibuat.'),
                  const _StepLine(
                      no: 2,
                      text: 'Kirim file itu ke pelanggan lewat WhatsApp '
                          '(atau simpan, kirim belakangan).'),
                  const _StepLine(
                      no: 3,
                      text: 'Pelanggan buka file itu di HP-nya (tanpa perlu '
                          'internet), pilih barang, lalu tekan "Kirim via '
                          'WhatsApp" — teks pesanan otomatis terformat rapi.'),
                  const _StepLine(
                      no: 4,
                      text: 'Kasir baca teks itu dan input manual seperti '
                          'biasa. (Tempel-otomatis ke keranjang menyusul di '
                          'tahap berikutnya.)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: scheme.errorContainer.withOpacity(0.4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'File TIDAK otomatis ter-update. Setiap harga berubah, '
                      'buat & kirim ulang file ke pelanggan langganan.',
                      style: TextStyle(fontSize: 12, color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _generating ? null : _generateAndShare,
            icon: _generating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.ios_share),
            label: Text(_generating ? 'Membuat…' : 'Buat & Bagikan Katalog'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          if (_lastGeneratedAt != null) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                '${_lastProductCount ?? 0} produk · dibagikan '
                '${_lastGeneratedAt!.hour.toString().padLeft(2, '0')}:'
                '${_lastGeneratedAt!.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.no, required this.text});
  final int no;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$no',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }
}
