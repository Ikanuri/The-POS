/// Agregasi titik tren harian jadi mingguan/bulanan kalau jumlahnya terlalu
/// banyak untuk ditampilkan layak — dipakai [StatsTrendChart] agar chart
/// tetap terbaca berapa pun panjang rentang tanggal yang dipilih user
/// (bug lama: bar-per-hari di rentang setahun = ~365 kolom sempit, label
/// tanggalnya pecah jadi tumpukan karakter vertikal krn tidak ada ruang).
///
/// Murni fungsi Dart (tanpa Flutter) supaya bisa diuji tanpa widget test.
library;

typedef TrendPoint = ({DateTime date, num value});

enum TrendGranularity { day, week, month }

class AggregatedTrend {
  const AggregatedTrend({required this.points, required this.granularity});
  final List<TrendPoint> points;
  final TrendGranularity granularity;
}

/// [points] HARUS sudah terurut menaik by tanggal (semua query sumbernya —
/// `getProductDailySales` dkk — sudah `ORDER BY`).
///
/// Aturan: kalau jumlah titik masih <= [targetMaxPoints], tampilkan apa
/// adanya per-hari. Kalau tidak, coba kelompokkan per-minggu dulu (7 hari
/// dari titik pertama) — kalau jumlah minggu MASIH melebihi target, baru
/// kelompokkan per-bulan kalender. Nilai per kelompok dijumlah (bukan
/// dirata-rata) — konsisten dgn makna "qty terjual"/"omzet" yang aditif.
AggregatedTrend aggregateTrend(List<TrendPoint> points,
    {int targetMaxPoints = 60}) {
  if (points.length <= targetMaxPoints) {
    return AggregatedTrend(points: points, granularity: TrendGranularity.day);
  }

  final first = points.first.date;
  final spanDays = points.last.date.difference(first).inDays + 1;
  if ((spanDays / 7).ceil() <= targetMaxPoints) {
    return AggregatedTrend(
      points: _bucket(points, (d) => first.add(Duration(
          days: (d.difference(first).inDays ~/ 7) * 7))),
      granularity: TrendGranularity.week,
    );
  }
  return AggregatedTrend(
    points: _bucket(points, (d) => DateTime(d.year, d.month, 1)),
    granularity: TrendGranularity.month,
  );
}

List<TrendPoint> _bucket(
    List<TrendPoint> points, DateTime Function(DateTime) bucketStart) {
  final sums = <DateTime, num>{};
  for (final p in points) {
    final key = bucketStart(p.date);
    sums[key] = (sums[key] ?? 0) + p.value;
  }
  final keys = sums.keys.toList()..sort();
  return [for (final k in keys) (date: k, value: sums[k]!)];
}

const bulanIndoPendek = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// Label tanggal SATU titik, disesuaikan granularitasnya — dipakai tooltip
/// (butuh presisi) maupun label sumbu (butuh ringkas).
String formatTrendDate(DateTime d, TrendGranularity g, {bool short = false}) {
  switch (g) {
    case TrendGranularity.day:
      return short ? '${d.day}/${d.month}' : '${d.day} ${bulanIndoPendek[d.month - 1]}';
    case TrendGranularity.week:
      final end = d.add(const Duration(days: 6));
      return short
          ? '${d.day}/${d.month}'
          : '${d.day}-${end.day} ${bulanIndoPendek[end.month - 1]}';
    case TrendGranularity.month:
      return '${bulanIndoPendek[d.month - 1]} ${d.year}';
  }
}
