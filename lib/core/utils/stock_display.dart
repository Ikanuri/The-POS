// Usulan user (sesi 83) — tampilan stok SEMUA satuan produk di kartu item
// kasir + level peringatan stok. Murni fungsi (tanpa DB/Flutter) supaya
// mudah dites. Stok tetap SATU angka di satuan dasar; per-satuan hanya
// pembagian dgn `ratioToBase` (lihat `AppDatabase.currentStock`).

/// Satuan yang ikut ditampilkan: [name] & [ratioToBase] (isi dalam satuan
/// dasar; satuan dasar = 1).
typedef StockUnit = ({String name, double ratioToBase});

/// Level peringatan stok.
enum StockLevel { ok, low, out }

/// Angka gaya Indonesia (pemisah ribuan titik, desimal koma), maksimal 2
/// desimal & nol di belakang koma dibuang — mis. 1250 -> "1.250",
/// 12.5 -> "12,5", 0.083333 -> "0,08".
String formatStockQty(double q) {
  final neg = q < 0;
  var v = q.abs();
  // Buang derau floating point (mis. 12.499999999 -> 12.5).
  v = double.parse(v.toStringAsFixed(2));
  final whole = v.truncate();
  final frac = ((v - whole) * 100).round();
  final wholeStr = whole
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  var out = wholeStr;
  if (frac > 0) {
    final f = frac.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '');
    out = '$out,$f';
  }
  return neg && v != 0 ? '-$out' : out;
}

/// Satu baris stok semua satuan, mis. "1.250 biji / 125 slop / 12,5 dus".
/// Urut dari satuan terkecil (rasio) ke terbesar; satuan dgn rasio <= 0
/// dilewati. [baseStock] = stok di satuan dasar.
String formatMultiUnitStock(double baseStock, List<StockUnit> units) {
  final sorted = units.where((u) => u.ratioToBase > 0).toList()
    ..sort((a, b) => a.ratioToBase.compareTo(b.ratioToBase));
  return [
    for (final u in sorted)
      '${formatStockQty(baseStock / u.ratioToBase)} ${u.name}',
  ].join(' / ');
}

/// Level stok: merah (habis) kalau stok <= 0 ATAU produk ditandai "Stok
/// Habis" manual; kuning (menipis) kalau <= [minStock] (satuan dasar, null =
/// tidak dipantau); selain itu ok. Produk non-stok tidak diberi indikator
/// (pemanggil tidak memanggil fungsi ini).
StockLevel stockLevel({
  required double baseStock,
  int? minStock,
  bool markedOutOfStock = false,
}) {
  if (markedOutOfStock || baseStock <= 0) return StockLevel.out;
  if (minStock != null && baseStock <= minStock) return StockLevel.low;
  return StockLevel.ok;
}
