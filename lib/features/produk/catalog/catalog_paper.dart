import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'catalog_models.dart';

/// Poster katalog harga yang dirender menjadi gambar (JPG) untuk dibagikan ke
/// pelanggan. Sengaja memakai palet terang tetap (tidak ikut tema gelap) agar
/// gambar konsisten & enak dibaca di galeri / WhatsApp pelanggan.
class CatalogPaper extends StatelessWidget {
  const CatalogPaper({
    super.key,
    required this.title,
    required this.storeName,
    required this.storeAddress,
    required this.dateText,
    required this.contactLine,
    required this.lines,
  });

  final String title;
  final String storeName;
  final String storeAddress;
  final String dateText;

  /// Baris kontak di footer (mis. "WA: 0812-xxxx"). Kosong → footer disembunyikan.
  final String contactLine;
  final List<CatalogLine> lines;

  // Palet terang tetap.
  static const _accent = Color(0xFFC96442);
  static const _ink = Color(0xFF2A2824);
  static const _ink2 = Color(0xFF6C685F);
  static const _line = Color(0xFFE7E2D7);
  static const _paper = Color(0xFFFFFFFF);

  /// Kelompokkan baris per kategori, mempertahankan urutan kemunculan.
  /// Map literal Dart sudah menjaga urutan penyisipan (LinkedHashMap).
  Map<String, List<CatalogLine>> _grouped() {
    final map = <String, List<CatalogLine>>{};
    for (final l in lines) {
      final key = l.category.trim().isEmpty ? 'Lainnya' : l.category.trim();
      map.putIfAbsent(key, () => []).add(l);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped();
    // Sembunyikan judul kategori bila semua produk tak berkategori (1 grup
    // "Lainnya") — supaya katalog kecil tidak terlihat aneh.
    final hideCategory = grouped.length == 1 && grouped.keys.first == 'Lainnya';

    return Container(
      // Lebar mengikuti parent (sheet pratinjau) agar tidak overflow di layar
      // sempit; gambar hasil capture tetap tajam karena pixelRatio 3.
      color: _paper,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header toko
          Container(
            color: _accent,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  storeName.isEmpty ? 'Toko' : storeName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                if (storeAddress.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    storeAddress.trim(),
                    style: const TextStyle(
                      color: Color(0xFFFFE6DC),
                      fontSize: 11.5,
                      height: 1.2,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title.trim().isEmpty ? 'Daftar Harga' : title.trim(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      dateText,
                      style: const TextStyle(
                        color: Color(0xFFFFE6DC),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Isi katalog
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in grouped.entries) ...[
                  if (!hideCategory) _categoryHeader(entry.key),
                  for (final l in entry.value) _itemRow(l),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),

          // Footer kontak
          if (contactLine.trim().isNotEmpty)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFFBF6F3),
                border: Border(top: BorderSide(color: _line)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.chat_rounded, size: 14, color: _accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      contactLine.trim(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
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

  Widget _categoryHeader(String name) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Row(
        children: [
          Container(width: 3, height: 14, color: _accent),
          const SizedBox(width: 7),
          Text(
            name.toUpperCase(),
            style: const TextStyle(
              color: _accent,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(CatalogLine l) {
    final qtyPrefix = l.qty != 1
        ? '${l.qty % 1 == 0 ? l.qty.toInt() : l.qty} '
        : '';
    final unitLabel = l.unitName.isEmpty ? '' : '$qtyPrefix${l.unitName}';

    return Padding(
      padding: EdgeInsets.only(left: l.isVariant ? 14 : 0, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (l.isVariant)
            const Padding(
              padding: EdgeInsets.only(right: 4, top: 1),
              child: Icon(Icons.subdirectory_arrow_right,
                  size: 13, color: _ink2),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.productName,
                  style: TextStyle(
                    color: _ink,
                    fontSize: l.isVariant ? 13 : 13.5,
                    fontWeight:
                        l.isVariant ? FontWeight.w500 : FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                if (unitLabel.isNotEmpty)
                  Text(
                    unitLabel,
                    style: const TextStyle(color: _ink2, fontSize: 10.5),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatRupiah(l.price),
            style: const TextStyle(
              color: _accent,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
