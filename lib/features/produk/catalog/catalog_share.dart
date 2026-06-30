import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/providers/device_provider.dart';
import '../../kasir/cart_provider.dart';
import 'catalog_models.dart';
import 'catalog_paper.dart';

const _idMonths = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

String catalogDateText(DateTime d) => '${d.day} ${_idMonths[d.month - 1]} ${d.year}';

/// Bangun baris katalog dari item keranjang katalog (urut: induk lalu varian),
/// lengkap dengan kategori tiap produk.
Future<List<CatalogLine>> buildCatalogLines(
    WidgetRef ref, List<CartItem> items) async {
  final db = ref.read(databaseProvider);
  final ordered = orderCartItems(items);
  final ids = ordered.map((e) => e.productId).toSet().toList();
  final catByProduct = await db.getCategoryNamesForProducts(ids);
  final nameById = {for (final i in ordered) i.productId: i.productName};
  return ordered
      .map((i) => CatalogLine(
            productName: i.productName,
            unitName: i.unitName,
            qty: i.qty,
            price: i.price,
            isVariant: i.isVariant,
            parentName: i.parentProductId != null
                ? nameById[i.parentProductId!]
                : null,
            category: catByProduct[i.productId] ?? '',
          ))
      .toList();
}

/// Muat info toko untuk header & footer katalog.
Future<({String name, String address, String contact})> loadCatalogHeader(
    WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final device = ref.read(deviceProvider);
  final name = (await db.getSetting('store_name'))?.trim();
  final address = (await db.getSetting('store_address'))?.trim() ?? '';
  final wa = (await db.getSetting('store_whatsapp'))?.trim() ?? '';
  final phone = (await db.getSetting('store_phone'))?.trim() ?? '';
  final contact = wa.isNotEmpty
      ? 'WA: $wa'
      : (phone.isNotEmpty ? 'Telp: $phone' : '');
  return (
    name: (name == null || name.isEmpty) ? device.storeName : name,
    address: address,
    contact: contact,
  );
}

/// Tampilkan pratinjau katalog dalam sheet + tombol bagikan sebagai gambar.
Future<void> showCatalogPreviewSheet(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required List<CatalogLine> lines,
  DateTime? date,
}) async {
  final header = await loadCatalogHeader(ref);
  final dateText = catalogDateText(date ?? DateTime.now());
  if (!context.mounted) return;

  final boundaryKey = GlobalKey();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Pratinjau Katalog',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: CatalogPaper(
                    title: title,
                    storeName: header.name,
                    storeAddress: header.address,
                    dateText: dateText,
                    contactLine: header.contact,
                    lines: lines,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _captureAndShare(ctx, boundaryKey, title),
              icon: const Icon(Icons.share),
              label: const Text('Bagikan Gambar'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _captureAndShare(
    BuildContext sheetCtx, GlobalKey boundaryKey, String title) async {
  try {
    final boundary =
        boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/katalog_$stamp.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: title.trim().isEmpty ? 'Katalog Harga' : title.trim(),
    );
    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
  } catch (e) {
    if (sheetCtx.mounted) {
      ScaffoldMessenger.of(sheetCtx)
          .showSnackBar(SnackBar(content: Text('Gagal membagikan: $e')));
    }
  }
}
