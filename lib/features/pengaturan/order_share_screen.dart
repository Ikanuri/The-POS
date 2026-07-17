import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/cloudflare_publish_service.dart';
import '../../core/services/order_page_service.dart';

/// Generate & bagikan katalog pesanan HTML — file statis self-contained
/// (tanpa server/hosting) yang bisa dibuka pelanggan dari WhatsApp untuk
/// memilih barang sendiri, lalu kirim balik teks pesanan.
///
/// Item 37 — SELAIN alur share manual (bawaan awal), owner bisa isi
/// Account ID + API Token Cloudflare sekali di sini lalu tekan "Publish ke
/// Web": katalog otomatis ter-upload ke Cloudflare Pages & dapat URL tetap
/// (`<project>.pages.dev`) yang bisa dibagikan sekali ke pelanggan — publish
/// berikutnya (mis. setelah harga berubah) cukup tekan tombol yang sama
/// lagi, URL TIDAK berubah. Fitur ini OPSIONAL & fallback-nya tetap alur
/// share manual di bawah (offline-first: ekspor katalog tidak boleh
/// bergantung ke internet).
class OrderShareScreen extends ConsumerStatefulWidget {
  const OrderShareScreen({super.key});

  @override
  ConsumerState<OrderShareScreen> createState() => _OrderShareScreenState();
}

/// Item 12 — toggle direct WA (wa.me ke nomor toko) vs share generik.
/// Default ON (true) supaya perilaku lama tetap sama sebelum user mengatur.
final _waDirectProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final v = await db.getSetting('katalog_wa_direct');
  return v == null || v == '1';
});

class _OrderShareScreenState extends ConsumerState<OrderShareScreen> {
  bool _generating = false;
  int? _lastProductCount;
  DateTime? _lastGeneratedAt;

  final _cloudflare = CloudflarePublishService();
  bool _publishing = false;
  String? _publishedUrl;

  Future<String> _buildHtml() async {
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final storeName = (await db.getSetting('store_name'))?.trim();
    final storeWhatsapp =
        (await db.getSetting('store_whatsapp'))?.trim() ?? '';
    final name = (storeName == null || storeName.isEmpty)
        ? device.storeName
        : storeName;
    final waDirect = ref.read(_waDirectProvider).valueOrNull ?? true;
    final result = await OrderPageService.generateHtml(
      db: db,
      storeName: name,
      storeWhatsapp: storeWhatsapp,
      waDirect: waDirect,
    );
    if (mounted) {
      setState(() {
        _lastProductCount = result.productCount;
        _lastGeneratedAt = DateTime.now();
      });
    }
    return result.html;
  }

  Future<void> _openCloudflareSettings() async {
    final creds = await _cloudflare.loadCredentials();
    if (!mounted) return;
    final tokenCtrl = TextEditingController(text: creds?.apiToken ?? '');
    final accountCtrl = TextEditingController(text: creds?.accountId ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pengaturan Cloudflare Pages'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Buat akun Cloudflare gratis (kalau belum punya), lalu ambil '
              'Account ID (sidebar kanan dashboard) & buat API Token '
              '(My Profile > API Tokens, scope: Account > Cloudflare '
              'Pages > Edit).',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: accountCtrl,
              decoration: const InputDecoration(labelText: 'Account ID'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tokenCtrl,
              decoration: const InputDecoration(labelText: 'API Token'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final token = tokenCtrl.text.trim();
      final accountId = accountCtrl.text.trim();
      if (token.isEmpty || accountId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Account ID & API Token tidak boleh kosong')));
        }
        return;
      }
      await _cloudflare.saveCredentials(apiToken: token, accountId: accountId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kredensial Cloudflare disimpan')));
      }
    }
  }

  Future<void> _publishToWeb() async {
    if (_publishing) return;
    final messenger = ScaffoldMessenger.of(context);
    // Cek kredensial DULU (tanpa spinner) — spinner hanya utk kerja network
    // sungguhan. Kalau spinner dinyalakan sebelum dialog Pengaturan dibuka,
    // ikon animasinya berputar TAK TERBATAS selama dialog menunggu input
    // user, yang bikin `pumpAndSettle` widget test macet (ketahuan lewat
    // test — lihat order_share_publish_button_test.dart).
    var creds = await _cloudflare.loadCredentials();
    if (creds == null) {
      if (!mounted) return;
      await _openCloudflareSettings();
      if (!mounted) return;
      creds = await _cloudflare.loadCredentials();
      if (creds == null) return;
    }

    setState(() => _publishing = true);
    try {
      final html = await _buildHtml();
      final db = ref.read(databaseProvider);
      final device = ref.read(deviceProvider);
      final storeName = (await db.getSetting('store_name'))?.trim();
      final name = (storeName == null || storeName.isEmpty)
          ? device.storeName
          : storeName;
      final result = await _cloudflare.publish(
        html: html,
        storeName: name,
        storeUuid: device.storeUuid ?? name,
      );
      if (mounted) {
        setState(() => _publishedUrl = result.url);
        messenger.showSnackBar(
            SnackBar(content: Text('Berhasil publish ke ${result.url}')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Gagal publish ke web: $e — coba lagi atau pakai '
              '"Buat & Bagikan" manual di bawah')));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _generateAndShare() async {
    if (_generating) return;
    setState(() => _generating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final db = ref.read(databaseProvider);
      final device = ref.read(deviceProvider);
      final storeName = (await db.getSetting('store_name'))?.trim();
      final name = (storeName == null || storeName.isEmpty)
          ? device.storeName
          : storeName;
      final html = await _buildHtml();

      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/katalog_pesanan_$stamp.html');
      await file.writeAsString(html);

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/html')],
        text: 'Katalog pesanan $name — buka & pilih barang, lalu kirim '
            'balik pesanannya ke kami via WhatsApp.',
      );
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
      appBar: AppBar(
        title: const Text('Katalog Pesanan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_outlined),
            tooltip: 'Pengaturan Cloudflare Pages',
            onPressed: _openCloudflareSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
            child: Builder(builder: (context) {
              final waDirect =
                  ref.watch(_waDirectProvider).valueOrNull ?? true;
              return SwitchListTile(
                secondary: const Icon(Icons.chat_outlined),
                title: const Text('Kirim Langsung ke Nomor WA Toko'),
                subtitle: Text(waDirect
                    ? 'Tombol "Kirim via WhatsApp" di katalog langsung buka '
                        'chat ke nomor WA toko'
                    : 'Tombol "Kirim via WhatsApp" biarkan pelanggan pilih '
                        'sendiri kontak tujuan (share biasa)'),
                value: waDirect,
                onChanged: (v) async {
                  final db = ref.read(databaseProvider);
                  await db.setSetting('katalog_wa_direct', v ? '1' : '0');
                  ref.invalidate(_waDirectProvider);
                },
              );
            }),
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
          OutlinedButton.icon(
            onPressed: _publishing ? null : _publishToWeb,
            icon: _publishing
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(_publishing ? 'Mempublish…' : 'Publish ke Web'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
          ),
          if (_publishedUrl != null) ...[
            const SizedBox(height: 10),
            Center(
              child: SelectableText(
                _publishedUrl!,
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
            ),
          ],
          const SizedBox(height: 8),
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
