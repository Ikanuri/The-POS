import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/widgets/chart_kit.dart';

/// Perangkat grafik gaya Telegram: singkatan angka, skala angka-bulat,
/// batang terpilih + tooltip, donat sentuh.
void main() {
  test('abbrevNumber: rb / jt / M gaya Indonesia', () {
    expect(abbrevNumber(0), '0');
    expect(abbrevNumber(950), '950');
    expect(abbrevNumber(1000), '1 rb');
    expect(abbrevNumber(1500), '1,5 rb');
    expect(abbrevNumber(250000), '250 rb');
    expect(abbrevNumber(1200000), '1,2 jt');
    expect(abbrevNumber(3000000000), '3 M');
    expect(abbrevNumber(-1500), '-1,5 rb');
    expect(abbrevNumber(1999), '1,9 rb', reason: 'dipotong, bukan dibulatkan');
  });

  test('niceAxis: 5 interval angka-bulat, batas atas >= data', () {
    for (final m in [1, 3, 7, 42, 99, 100, 1234, 85000, 999999, 2500000]) {
      final a = niceAxis(m);
      expect(a.max, greaterThanOrEqualTo(m), reason: 'max untuk $m');
      expect(a.max, closeTo(a.step * 5, 1e-6));
      // langkah = {1,2,2.5,5} x 10^k
      var s = a.step;
      while (s >= 10) {
        s /= 10;
      }
      while (s < 1) {
        s *= 10;
      }
      expect([1.0, 2.0, 2.5, 5.0].any((x) => (x - s).abs() < 1e-6) || s == 10,
          isTrue,
          reason: 'langkah ${a.step} untuk $m');
    }
    expect(niceAxis(0).max, 5);
    expect(niceAxis(-4).max, 5);
    expect(niceAxis(100).step, 20);
    expect(niceAxis(85000).max, 100000);
  });

  Future<void> pumpBars(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: AppBarChart(
            series: const [
              BarSeries('Masuk', Colors.green),
              BarSeries('Keluar', Colors.red),
            ],
            valueLabel: (v) => 'Rp ${v.toInt()}',
            groups: [
              for (var i = 0; i < 10; i++)
                BarGroup(
                    xLabel: '${i + 1}/10',
                    title: 'Hari ${i + 1}',
                    values: [100.0 * (i + 1), 50.0 * i]),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('AppBarChart: tap memilih -> tooltip; tap lagi menutup; geser pindah',
      (tester) async {
    await pumpBars(tester);
    expect(find.byKey(const Key('chart-tooltip')), findsNothing);
    final rect = tester.getRect(find.byType(AppBarChart));
    // Tap kelompok ke-3 (dari 10).
    await tester.tapAt(Offset(rect.left + rect.width * 0.25, rect.center.dy));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-tooltip')), findsOneWidget);
    expect(find.text('Hari 3'), findsOneWidget);
    expect(find.text('Rp 300'), findsOneWidget);
    expect(find.text('Masuk  '), findsOneWidget, reason: 'dua seri -> label seri');

    // Geser ke kelompok ke-8.
    final g = await tester.startGesture(
        Offset(rect.left + rect.width * 0.25, rect.center.dy));
    for (var i = 1; i <= 5; i++) {
      await g.moveTo(Offset(rect.left + rect.width * (0.25 + 0.1 * i),
          rect.center.dy));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('Hari 8'), findsOneWidget);

    // Tap kelompok yang sama menutup.
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-tooltip')), findsNothing);
  });

  testWidgets('AppBarChart: data kosong/nol tidak error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppBarChart(
          series: const [BarSeries('x', Colors.red)],
          valueLabel: (v) => '$v',
          groups: const [
            BarGroup(xLabel: 'a', title: 'a', values: [0]),
            BarGroup(xLabel: 'b', title: 'b', values: [0]),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppDonut: legenda tampil; showLegend=false menyembunyikannya',
      (tester) async {
    Widget app(bool legend) => MaterialApp(
          home: Scaffold(
            body: AppDonut(
              showLegend: legend,
              slices: const [
                DonutSlice('Tunai', 70, Colors.orange, Colors.white),
                DonutSlice('QRIS', 30, Colors.blue, Colors.white),
              ],
            ),
          ),
        );
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(find.text('Tunai'), findsOneWidget);
    expect(find.text('QRIS'), findsOneWidget);
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(find.text('Tunai'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
