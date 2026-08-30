import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/laporan/stats/stats_common.dart';
import 'package:the_pos/features/laporan/stats/trend_aggregation.dart';

/// Bug asli (dilaporkan user via screenshot): rentang tanggal panjang
/// (~365 titik harian) bikin chart LAMA (bar-per-hari) label-nya pecah jadi
/// tumpukan karakter vertikal — kolom terlalu sempit utk satu digit pun.
/// `StatsTrendChart` (LineChart) tidak boleh mengulang kelas bug yang sama.
List<TrendPoint> _dailyRange(DateTime start, int days) => [
      for (var i = 0; i < days; i++)
        (date: start.add(Duration(days: i)), value: (i % 7) + 1),
    ];

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 400, child: child)),
    );

void main() {
  testWidgets('rentang setahun (365 titik) render TANPA error/overflow',
      (tester) async {
    final points = _dailyRange(DateTime(2025, 8, 13), 365);

    await tester.pumpWidget(_wrap(StatsTrendChart(
      points: points,
      color: Colors.blue,
      valueLabel: (v) => '$v terjual',
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'chart lama pecah/overflow di rentang panjang; yang baru '
            'harus tahan berapa pun jumlah titiknya');
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets(
      'rentang pendek (7 titik) tetap render sebagai harian, '
      'jumlah label wajar', (tester) async {
    final points = _dailyRange(DateTime(2026, 3, 1), 7);

    await tester.pumpWidget(_wrap(StatsTrendChart(
      points: points,
      color: Colors.blue,
      valueLabel: (v) => '$v terjual',
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('satu titik saja TIDAK error (kasus tepi)', (tester) async {
    await tester.pumpWidget(_wrap(StatsTrendChart(
      points: [(date: DateTime(2026, 3, 1), value: 5)],
      color: Colors.blue,
      valueLabel: (v) => '$v terjual',
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('titik kosong -> tidak render chart sama sekali (bukan error)',
      (tester) async {
    await tester.pumpWidget(_wrap(StatsTrendChart(
      points: const [],
      color: Colors.blue,
      valueLabel: (v) => '$v',
    )));
    await tester.pumpAndSettle();

    expect(find.byType(LineChart), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interaksi tap di garis memicu tooltip (LineTouchData aktif)',
      (tester) async {
    final points = _dailyRange(DateTime(2026, 3, 1), 14);
    await tester.pumpWidget(_wrap(StatsTrendChart(
      points: points,
      color: Colors.blue,
      valueLabel: (v) => '$v terjual',
    )));
    await tester.pumpAndSettle();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineTouchData.enabled, isTrue,
        reason: 'permintaan user: interaktif ala trading — sentuh/drag di '
            'garis harus memunculkan tooltip');

    // Sentuh di tengah area chart — tidak boleh melempar exception.
    await tester.tapAt(tester.getCenter(find.byType(LineChart)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'nominal puncak tampil PERMANEN (garis + label) tanpa perlu tap/drag',
      (tester) async {
    final points = [
      (date: DateTime(2026, 3, 1), value: 5),
      (date: DateTime(2026, 3, 2), value: 42),
      (date: DateTime(2026, 3, 3), value: 10),
    ];
    await tester.pumpWidget(_wrap(StatsTrendChart(
      points: points,
      color: Colors.blue,
      valueLabel: (v) => 'Rp $v',
    )));
    await tester.pumpAndSettle();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final lines = chart.data.extraLinesData.horizontalLines;
    expect(lines, hasLength(1),
        reason: 'garis puncak harus selalu ada, tanpa perlu tap/drag dulu '
            '("quick insight")');
    expect(lines.single.y, 42,
        reason: 'garis harus di level nilai PUNCAK data mentah (42), bukan '
            'maxY chart yang sudah dikasih headroom 15%');
    expect(lines.single.label.show, isTrue);
    expect(lines.single.label.labelResolver(lines.single), 'Rp 42');
  });

  testWidgets('nilai negatif/nol semua tidak bikin maxY 0 (pembagi nol)',
      (tester) async {
    await tester.pumpWidget(_wrap(StatsTrendChart(
      points: [
        (date: DateTime(2026, 3, 1), value: 0),
        (date: DateTime(2026, 3, 2), value: 0),
      ],
      color: Colors.blue,
      valueLabel: (v) => '$v',
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
