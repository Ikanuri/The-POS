import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/catalog_access_service.dart';
import '../../core/services/cloudflare_publish_service.dart';

/// Kode akses katalog per pelanggan (toko tutup) — dibuat/diganti/dicabut
/// dari form pelanggan (khusus owner). Kode TIDAK ikut ke HTML (hanya
/// hash-nya); perubahan baru berlaku di katalog setelah Publish/bagikan ulang.
class CatalogCodeCard extends ConsumerStatefulWidget {
  const CatalogCodeCard({super.key, required this.customerId});
  final String customerId;

  @override
  ConsumerState<CatalogCodeCard> createState() => _CatalogCodeCardState();
}

class _CatalogCodeCardState extends ConsumerState<CatalogCodeCard> {
  String? _code;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final code = await CatalogAccessService.codeFor(
        ref.read(databaseProvider), widget.customerId);
    if (mounted) {
      setState(() {
        _code = code;
        _loaded = true;
      });
    }
  }

  Future<void> _rotate() async {
    if (_code != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Buat kode baru?'),
          content: const Text('Kode lama tidak berlaku lagi setelah katalog '
              'di-Publish ulang.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Buat baru')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final code = await CatalogAccessService.rotateCode(
        ref.read(databaseProvider), widget.customerId);
    if (mounted) setState(() => _code = code);
  }

  Future<void> _revoke() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cabut kode?'),
        content: const Text('Pelanggan ini tidak bisa lagi memesan saat toko '
            'tutup, setelah katalog di-Publish ulang.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cabut')),
        ],
      ),
    );
    if (ok != true) return;
    await CatalogAccessService.revokeCode(
        ref.read(databaseProvider), widget.customerId);
    if (mounted) setState(() => _code = null);
  }

  Future<void> _share() async {
    final code = _code;
    if (code == null) return;
    final db = ref.read(databaseProvider);
    final storeName = (await db.getSetting('store_name'))?.trim();
    final name = (storeName == null || storeName.isEmpty)
        ? ref.read(deviceProvider).storeName
        : storeName;
    String? url;
    try {
      url = await CloudflarePublishService()
          .publishedUrl()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    final text = StringBuffer()
      ..writeln('Kode katalog $name: $code')
      ..write('Masukkan kode ini di katalog saat toko tutup agar tetap bisa '
          'memesan.');
    if (url != null) text.write('\n$url');
    await Share.share(text.toString());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Tombol-tombol kecil: minimumSize sempit WAJIB (default tema lebar penuh).
    final small = ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size(0, 40)),
        padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12)));
    return Card(
      key: const ValueKey('catalog-code-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.vpn_key_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                const Text('Kode katalog',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Dipakai pelanggan ini untuk memesan saat toko tutup. Berlaku '
              'di katalog setelah Publish ulang.',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            if (!_loaded)
              const SizedBox(height: 40)
            else if (_code == null)
              OutlinedButton.icon(
                key: const ValueKey('catalog-code-create'),
                style: small,
                onPressed: _rotate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Buat kode'),
              )
            else ...[
              SelectableText(
                _code!,
                key: const ValueKey('catalog-code-value'),
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('catalog-code-copy'),
                    style: small,
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: _code!));
                      messenger.showSnackBar(
                          const SnackBar(content: Text('Kode disalin')));
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Salin'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('catalog-code-share'),
                    style: small,
                    onPressed: _share,
                    icon: const Icon(Icons.share_outlined, size: 16),
                    label: const Text('Bagikan'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('catalog-code-rotate'),
                    style: small,
                    onPressed: _rotate,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Buat ulang'),
                  ),
                  TextButton(
                    key: const ValueKey('catalog-code-revoke'),
                    style: small.merge(
                        TextButton.styleFrom(foregroundColor: scheme.error)),
                    onPressed: _revoke,
                    child: const Text('Cabut'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
