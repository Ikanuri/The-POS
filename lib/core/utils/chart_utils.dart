/// Tinggi batang chart yang aman dari [value] negatif (mis. omzet/qty pada
/// hari yang didominasi retur, di mana total netto bisa < 0). Tanpa ini,
/// `Container(height: ...)` bisa menerima nilai negatif dan crash saat
/// render.
///
/// [value] di-clamp ke rentang `[0, max]` sebelum diskalakan proporsional
/// ke [maxHeight]. Bila [max] <= 0 (tidak ada data positif sama sekali),
/// kembalikan [emptyHeight] — bar nyaris rata alih-alih hilang total atau
/// (yang lebih parah) bernilai negatif.
double clampedBarHeight(num value, num max,
    {double maxHeight = 70, double emptyHeight = 2}) {
  if (max <= 0) return emptyHeight;
  return value.clamp(0, max) / max * maxHeight;
}
