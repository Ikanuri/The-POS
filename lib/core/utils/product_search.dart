/// Pencocokan pencarian produk yang TOLERAN (tanpa perubahan skema):
///  * urutan kata bebas — "goreng indomie" cocok "Indomie Goreng";
///  * huruf besar/kecil, aksen, tanda baca & spasi diabaikan — "cone snack"
///    cocok "Cone-Snack", "conesnack" juga cocok;
///  * satuan dinormalkan — "500 gr", "500gram", "500g" sama;
///  * ikut mencari di KODE produk dan NAMA KATEGORI.
/// Aturan dasar tetap "potongan teks": tiap kata cukup menjadi POTONGAN dari
/// teks (bukan harus awal kata) — jadi SEMUA yang dulu cocok (potongan
/// berurutan dari nama/kode) tetap cocok; ini hanya melonggarkan.
///
/// Logika yang SAMA diterapkan di katalog HTML (`normSearch`/`matchesQuery`
/// di `order_page_service.dart`) — ubah keduanya bersamaan.
class ProductSearch {
  ProductSearch(String query)
      : tokens =
            normalize(query).split(' ').where((t) => t.isNotEmpty).toList() {
    compact = tokens.join();
  }

  /// Kata-kata kueri yang sudah dinormalkan.
  final List<String> tokens;

  /// Kueri tanpa spasi (untuk cocok lintas-spasi: "conesnack").
  late final String compact;

  bool get isEmpty => tokens.isEmpty;

  static const _accents = {
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };
  static final _nonAlnum = RegExp(r'[^a-z0-9]+');
  static final _gram = RegExp(r'(\d+)\s*(?:gram|gr|g)\b');
  static final _liter = RegExp(r'(\d+)\s*(?:liter|ltr|l)\b');
  static final _kgMl = RegExp(r'(\d+)\s*(kg|ml)\b');

  /// Huruf kecil, tanpa aksen, tanda baca -> spasi, spasi dirapatkan, satuan
  /// dinormalkan ("500 gr" -> "500g", "1 liter" -> "1l").
  static String normalize(String s) {
    var t = s.toLowerCase();
    if (t.runes.any((r) => r > 127)) {
      final b = StringBuffer();
      for (final ch in t.split('')) {
        b.write(_accents[ch] ?? ch);
      }
      t = b.toString();
    }
    t = t.replaceAll(_nonAlnum, ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
    t = t.replaceAllMapped(_kgMl, (m) => '${m[1]}${m[2]}');
    t = t.replaceAllMapped(_gram, (m) => '${m[1]}g');
    t = t.replaceAllMapped(_liter, (m) => '${m[1]}l');
    return t;
  }

  /// Apakah produk cocok? Semua kata kueri harus ada (sebagai potongan) di
  /// gabungan [name] + [kode] + [group] (nama kategori). Kueri kosong = cocok.
  bool matches(String? name, {String? kode, String? group}) {
    if (tokens.isEmpty) return true;
    final hay = normalize('${name ?? ''} ${kode ?? ''} ${group ?? ''}');
    var all = true;
    for (final t in tokens) {
      if (!hay.contains(t)) {
        all = false;
        break;
      }
    }
    if (all) return true;
    // Lintas spasi: "conesnack" / "cone snack" vs "cone-snack".
    return compact.length >= 2 && hay.replaceAll(' ', '').contains(compact);
  }
}
