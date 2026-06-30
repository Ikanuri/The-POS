// Model katalog harga yang bisa dibagikan sebagai gambar ke pelanggan, berguna
// untuk mengumumkan harga / kenaikan harga. Disimpan sebagai JSON di tabel
// settings (key `saved_catalogs`) sehingga tidak butuh migrasi DB.

/// Satu baris produk di dalam katalog. Sudah ter-resolve (nama, satuan, harga,
/// kategori) agar katalog tersimpan tidak perlu lookup ulang ke DB.
class CatalogLine {
  const CatalogLine({
    required this.productName,
    required this.unitName,
    required this.qty,
    required this.price,
    this.isVariant = false,
    this.parentName,
    this.category = '',
  });

  final String productName;
  final String unitName;
  final double qty;
  final int price;
  final bool isVariant;
  final String? parentName;
  final String category;

  Map<String, dynamic> toJson() => {
        'productName': productName,
        'unitName': unitName,
        'qty': qty,
        'price': price,
        'isVariant': isVariant,
        'parentName': parentName,
        'category': category,
      };

  factory CatalogLine.fromJson(Map<String, dynamic> json) => CatalogLine(
        productName: json['productName'] as String? ?? '',
        unitName: json['unitName'] as String? ?? '',
        qty: (json['qty'] as num?)?.toDouble() ?? 1,
        price: (json['price'] as num?)?.toInt() ?? 0,
        isVariant: json['isVariant'] as bool? ?? false,
        parentName: json['parentName'] as String?,
        category: json['category'] as String? ?? '',
      );
}

/// Katalog tersimpan: judul, waktu dibuat, dan daftar baris produknya.
class SavedCatalog {
  const SavedCatalog({
    required this.id,
    required this.title,
    required this.createdAtMs,
    required this.lines,
  });

  final String id;
  final String title;
  final int createdAtMs;
  final List<CatalogLine> lines;

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAtMs': createdAtMs,
        'lines': lines.map((e) => e.toJson()).toList(),
      };

  factory SavedCatalog.fromJson(Map<String, dynamic> json) => SavedCatalog(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Katalog',
        createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
        lines: ((json['lines'] as List?) ?? const [])
            .map((e) => CatalogLine.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
