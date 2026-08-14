/// Parser teks Penerimaan Barang — mengubah daftar yang ditempel user
/// (hasil tools cek-stok eksternal) jadi baris terstruktur.
///
/// Format sumber (dikonfirmasi dari file tools yang dikirim user):
///   `qty satuan nama`   mis. `5 pcs Indomie Goreng`
/// Bisa disisipi header pemisah tanggal yang HARUS diabaikan:
///   `── Hari ini ──`, `── Kemarin ──`, `── 11 Agu ──`
/// qty di sumber sudah dinormalkan (titik ribuan dibuang, koma jadi titik),
/// tapi parser di sini tetap toleran terhadap keduanya karena teksnya bisa
/// juga diketik manual.
library;

/// Satu baris hasil parse.
typedef ParsedReceiveLine = ({
  /// Baris mentah apa adanya — ditampilkan lagi ke user kalau gagal cocok,
  /// supaya jelas baris MANA yang bermasalah (bukan dibuang diam-diam).
  String raw,
  double qty,

  /// Satuan dari teks. Bisa string kosong kalau barisnya cuma "qty nama"
  /// (lihat [ReceiveTextParser.parseLine] soal ambiguitas ini).
  String unit,
  String name,
});

class ReceiveTextParser {
  ReceiveTextParser._();

  /// Baris pemisah/hiasan yang bukan data: diawali & diakhiri karakter garis
  /// (`─`, `-`, `=`) atau tidak mengandung angka sama sekali di depan.
  static final _dividerLike = RegExp(r'^[\s\-=─_~*]+$');
  static final _headerLike = RegExp(r'^[\s\-=─_~*]*(.+?)[\s\-=─_~*]*$');

  /// `qty satuan nama` — qty wajib angka di AWAL baris.
  static final _line = RegExp(r'^\s*([0-9]+(?:[.,][0-9]+)?)\s+(.+)$');

  static bool _isHeader(String line) {
    final t = line.trim();
    if (t.isEmpty) return true;
    if (_dividerLike.hasMatch(t)) return true;
    // Header tanggal ala tools user: "── Hari ini ──" / "── 11 Agu ──".
    // Cirinya: dibungkus karakter garis DAN tidak diawali angka+spasi.
    final hasBorder = RegExp(r'^[\s\-=─_~*]{2,}').hasMatch(t) &&
        RegExp(r'[\s\-=─_~*]{2,}$').hasMatch(t);
    if (hasBorder) {
      final inner = _headerLike.firstMatch(t)?.group(1)?.trim() ?? '';
      // "── 5 pcs Beras ──" (kalau ada) tetap dianggap data, bukan header.
      return !_line.hasMatch(inner);
    }
    return false;
  }

  /// Parse SATU baris. null = baris ini bukan data (header/pemisah/kosong)
  /// ATAU tidak punya qty di depan sehingga tidak bisa dipakai.
  ///
  /// Pemisahan satuan vs nama: kata PERTAMA setelah qty dianggap satuan
  /// HANYA kalau masih ada kata lain sesudahnya. Untuk `5 Beras` (tanpa
  /// satuan) satuan dibiarkan kosong dan seluruh sisanya jadi nama —
  /// mencegah kata pertama nama produk salah terbaca sbg satuan, yang
  /// akan bikin pencocokan meleset diam-diam.
  static ParsedReceiveLine? parseLine(String raw) {
    if (_isHeader(raw)) return null;
    final m = _line.firstMatch(raw);
    if (m == null) return null;
    final qty = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    if (qty == null || qty <= 0) return null;

    final rest = m.group(2)!.trim();
    final parts = rest.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (
        raw: raw.trim(),
        qty: qty,
        unit: parts.first,
        name: parts.sublist(1).join(' '),
      );
    }
    return (raw: raw.trim(), qty: qty, unit: '', name: rest);
  }

  /// Parse seluruh teks. Baris yang bukan data dilewati diam-diam (memang
  /// bukan kesalahan user), baris yang PUNYA isi tapi tidak bisa diparse
  /// dikembalikan lewat [unparsed] supaya bisa ditampilkan sbg peringatan.
  static ({List<ParsedReceiveLine> lines, List<String> unparsed}) parse(
      String text) {
    final lines = <ParsedReceiveLine>[];
    final unparsed = <String>[];
    for (final raw in text.split('\n')) {
      if (raw.trim().isEmpty) continue;
      if (_isHeader(raw)) continue;
      final parsed = parseLine(raw);
      if (parsed == null) {
        unparsed.add(raw.trim());
      } else {
        lines.add(parsed);
      }
    }
    return (lines: lines, unparsed: unparsed);
  }
}

/// Normalisasi kunci kamus — dipakai BERSAMA saat menulis & membaca alias,
/// jadi keduanya wajib lewat sini (kalau tidak, kunci yang ditulis tidak
/// akan pernah ketemu saat dibaca).
class AliasKey {
  AliasKey._();

  /// Huruf kecil + spasi berlebih dirapikan + tanda baca umum dibuang.
  /// SENGAJA tidak melakukan stemming/fuzzy apa pun (keputusan user:
  /// pencocokan PERSIS; ambiguitas diselesaikan lewat pilihan manual).
  static String normalizeName(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String normalizeUnit(String s) => normalizeName(s);
}
