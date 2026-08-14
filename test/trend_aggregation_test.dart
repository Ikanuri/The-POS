import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/laporan/stats/trend_aggregation.dart';

/// Agregasi tren chart statistik produk — bug lama: rentang setahun (~365
/// titik harian) bikin label sumbu pecah krn kolom terlalu sempit. Fungsi
/// ini yang memutuskan kapan harus dikelompokkan mingguan/bulanan.
void main() {
  TrendPoint p(String ymd, num v) {
    final parts = ymd.split('-').map(int.parse).toList();
    return (date: DateTime(parts[0], parts[1], parts[2]), value: v);
  }

  test('di bawah ambang batas -> tetap harian, tidak diubah', () {
    final points = [p('2026-01-01', 5), p('2026-01-02', 3)];
    final r = aggregateTrend(points, targetMaxPoints: 60);
    expect(r.granularity, TrendGranularity.day);
    expect(r.points, points);
  });

  test('rentang setahun (365 titik) -> dikelompokkan, TIDAK 365 titik lagi',
      () {
    final points = [
      for (var i = 0; i < 365; i++)
        p(DateTime(2026, 1, 1).add(Duration(days: i)).toIso8601String().substring(0, 10), 1),
    ];
    final r = aggregateTrend(points, targetMaxPoints: 60);
    expect(r.points.length, lessThanOrEqualTo(60),
        reason: 'inilah yang mencegah label pecah — jumlah titik akhir '
            'harus di bawah ambang berapa pun panjang rentangnya');
    expect(r.granularity, isNot(TrendGranularity.day));
  });

  test('nilai per kelompok DIJUMLAH, bukan dirata-rata', () {
    // 14 hari @ nilai 10 -> kalau dikelompokkan mingguan (2 minggu), tiap
    // minggu harus 70 (7 hari x 10), bukan 10 (rata-rata).
    final points = [
      for (var i = 0; i < 14; i++)
        p(DateTime(2026, 1, 1).add(Duration(days: i)).toIso8601String().substring(0, 10), 10),
    ];
    final r = aggregateTrend(points, targetMaxPoints: 3);
    expect(r.granularity, TrendGranularity.week);
    expect(r.points, hasLength(2));
    expect(r.points.every((pt) => pt.value == 70), isTrue);
  });

  test('rentang SANGAT panjang (3 tahun) -> jatuh ke bulanan, bukan '
      'mingguan (mingguan pun masih akan terlalu banyak titik)', () {
    final points = [
      for (var i = 0; i < 1095; i++)
        p(DateTime(2023, 1, 1).add(Duration(days: i)).toIso8601String().substring(0, 10), 1),
    ];
    final r = aggregateTrend(points, targetMaxPoints: 60);
    expect(r.granularity, TrendGranularity.month);
    expect(r.points.length, lessThanOrEqualTo(60));
  });

  test('titik yang hilang (hari tanpa penjualan) tidak bikin bucket kosong '
      'ikut muncul sbg 0 palsu -> cukup tidak ada bucket utk periode itu',
      () {
    // Cuma 2 hari berjauhan dalam rentang panjang.
    final points = [p('2023-01-01', 5), p('2024-06-01', 3)];
    final r = aggregateTrend(points, targetMaxPoints: 60);
    // Span > setahun -> bulanan, tapi cuma 2 bulan yang PUNYA data.
    expect(r.points, hasLength(2));
  });

  group('format label', () {
    test('harian: tanggal presisi', () {
      final d = DateTime(2026, 8, 11);
      expect(formatTrendDate(d, TrendGranularity.day), '11 Agu');
      expect(formatTrendDate(d, TrendGranularity.day, short: true), '11/8');
    });

    test('mingguan: rentang tanggal', () {
      final d = DateTime(2026, 8, 3);
      expect(formatTrendDate(d, TrendGranularity.week), '3-9 Agu');
    });

    test('bulanan: bulan + tahun (Indonesia manual, TANPA locale DateFormat '
        '— gotcha CLAUDE.md)', () {
      final d = DateTime(2026, 3, 1);
      expect(formatTrendDate(d, TrendGranularity.month), 'Mar 2026');
    });
  });
}
