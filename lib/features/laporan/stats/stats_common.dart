import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'trend_aggregation.dart';

/// Potongan UI yang dipakai BERSAMA oleh layar statistik produk & pelanggan.
///
/// Sengaja dibagi supaya angka & tampilan tidak pernah menyimpang antara
/// dua layar itu — dan antara layar detail vs tab ringkas di Laporan yang
/// jadi pintu masuknya.

/// Bar rentang tanggal — pola sama header Laporan (`_pickRange`), tapi
/// state-nya LOKAL per layar detail (bukan `dateRangeProvider` global):
/// mengubah rentang saat menelusuri satu produk/pelanggan TIDAK boleh
/// ikut mengubah rentang tab Laporan yang ditinggalkan di belakang.
class StatsRangeBar extends StatelessWidget {
  const StatsRangeBar({
    super.key,
    required this.range,
    required this.onChanged,
  });

  final DateTimeRange range;
  final ValueChanged<DateTimeRange> onChanged;

  static String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pick(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: range,
    );
    if (picked == null) return;
    onChanged(DateTimeRange(
      start: DateTime(picked.start.year, picked.start.month, picked.start.day),
      end: DateTime(
          picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => _pick(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.date_range_outlined,
                  size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${fmt(range.start)} – ${fmt(range.end)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text('Ubah',
                  style: TextStyle(fontSize: 12, color: scheme.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu angka ringkas (dipakai berjajar 2 kolom di atas layar statistik).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.caption,
  });

  final String label;
  final String value;
  final Color? color;

  /// Keterangan kecil di bawah [value] — dipakai layar produk utk
  /// merinci satuan non-dasar yang ikut terjual (mis. "dari itu: 3 dus").
  /// Null = tidak ada baris tambahan.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.numStyle(context,
                  size: 15, weight: FontWeight.w700, color: color),
            ),
            if (caption != null) ...[
              const SizedBox(height: 2),
              Text(
                caption!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Judul seksi di dalam layar statistik.
class StatsSectionTitle extends StatelessWidget {
  const StatsSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );
}

/// Grafik garis tren, interaktif ala chart trading (tap/drag di garis
/// memunculkan tooltip tanggal + nilai, dgn indikator titik yang mengikuti
/// jari) dan tahan rentang tanggal SEPANJANG APAPUN.
///
/// Riwayat: versi awal pakai bar-per-hari (pola sama `_ExpenseDailyChart`
/// di `pengeluaran_tab.dart`) — pecah kalau rentangnya lebar (mis. setahun
/// = ~365 kolom), lebar tiap kolom jadi lebih sempit dari satu karakter
/// sehingga label tanggalnya tumpuk vertikal per-huruf (bug nyata
/// dilaporkan user, screenshot). Diganti `LineChart` (fl_chart) krn titik
/// data cuma jadi vertex garis (tidak butuh lebar kolom minimum utk
/// terlihat) DAN label sumbu-X-nya dipasang lewat `interval` (fl_chart
/// yang menghitung posisi dari skala X sungguhan), bukan dibagi rata per
/// titik seperti versi lama — jumlah titik berapa pun, jumlah label tetap
/// terbatas. [aggregateTrend] mengelompokkan ke mingguan/bulanan dulu kalau
/// titik hariannya masih terlalu banyak, supaya garisnya juga tidak
/// terlalu "berisik" utk rentang panjang.
class StatsTrendChart extends StatelessWidget {
  const StatsTrendChart({
    super.key,
    required this.points,
    required this.color,
    required this.valueLabel,
  });

  /// Titik MENTAH (harian), sudah TERURUT menaik by tanggal — agregasi
  /// dilakukan DI SINI, pemanggil tidak perlu tahu soal itu.
  final List<TrendPoint> points;
  final Color color;

  /// Format nilai utk tooltip — beda layar beda satuan (qty produk vs
  /// rupiah), jadi diserahkan ke pemanggil.
  final String Function(num value) valueLabel;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final agg = aggregateTrend(points);
    final data = agg.points;
    final n = data.length;

    final maxY = data.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final spots = [
      for (var i = 0; i < n; i++)
        FlSpot(i.toDouble(), data[i].value.toDouble()),
    ];
    // Interval label: target ~5 label terlihat, minimal 1 (hindari
    // ArgumentError fl_chart kalau interval 0 pada n kecil).
    final labelInterval =
        n <= 1 ? 1.0 : ((n - 1) / 5).clamp(1, n - 1).toDouble();

    return SizedBox(
      height: 140,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (n - 1).toDouble().clamp(1, double.infinity),
            minY: 0,
            // Padding atas 15% supaya titik tertinggi tidak mepet ke tepi.
            maxY: maxY <= 0 ? 1 : maxY * 1.15,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY <= 0 ? 1 : maxY / 3,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: scheme.outlineVariant, strokeWidth: 0.5),
            ),
            borderData: FlBorderData(show: false),
            // Susulan (permintaan user): nominal PUNCAK selalu tampil di kiri
            // atas TANPA perlu tap/drag ("quick insight") — garis putus-putus
            // di level maxY (data mentah, BUKAN maxY chart yg sudah dikasih
            // headroom 15%) + label nilainya.
            extraLinesData: ExtraLinesData(horizontalLines: [
              HorizontalLine(
                y: maxY.toDouble(),
                color: color.withOpacity(0.4),
                strokeWidth: 1,
                dashArray: const [4, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.only(bottom: 4, left: 2),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  labelResolver: (_) => valueLabel(maxY),
                ),
              ),
            ]),
            titlesData: FlTitlesData(
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 20,
                  interval: labelInterval,
                  getTitlesWidget: (value, meta) {
                    final idx = value.round();
                    if (idx < 0 || idx >= n) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        formatTrendDate(data[idx].date, agg.granularity,
                            short: true),
                        style: TextStyle(
                            fontSize: 9, color: scheme.onSurfaceVariant),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                  final idx = s.x.round();
                  if (idx < 0 || idx >= n) return null;
                  final p = data[idx];
                  return LineTooltipItem(
                    '${formatTrendDate(p.date, agg.granularity)}\n'
                    '${valueLabel(p.value)}',
                    TextStyle(
                      color: scheme.onInverseSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  );
                }).toList(),
              ),
              getTouchedSpotIndicator: (barData, indicators) => indicators
                  .map((i) => TouchedSpotIndicatorData(
                        FlLine(
                            color: color.withOpacity(0.4),
                            strokeWidth: 1,
                            dashArray: [4, 4]),
                        FlDotData(
                          getDotPainter: (spot, percent, bar, index) =>
                              FlDotCirclePainter(
                                  radius: 4,
                                  color: color,
                                  strokeWidth: 2,
                                  strokeColor: scheme.surface),
                        ),
                      ))
                  .toList(),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: false,
                color: color,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: color.withOpacity(0.08),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pesan kosong seragam untuk seksi yang tidak punya data di rentang ini.
class StatsEmptyHint extends StatelessWidget {
  const StatsEmptyHint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

/// Format qty: buang ".0" untuk bilangan bulat (pola dipakai di seluruh app,
/// mis. daftar varian & riwayat opname).
String fmtQty(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();
