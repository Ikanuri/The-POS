import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/widgets/press_scale.dart';

void main() {
  double scaleOf(WidgetTester tester) {
    final t = tester.widgetList<Transform>(find.descendant(
        of: find.byType(PressScale), matching: find.byType(Transform)));
    if (t.isEmpty) return 1;
    return t.first.transform.entry(0, 0);
  }

  Widget host({VoidCallback? onTap, bool reduced = false, double depth = 0.1}) =>
      MaterialApp(
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
            child: child!),
        home: Center(
          child: PressScale(
            depth: depth,
            child: GestureDetector(
              onTap: onTap,
              child: const SizedBox(width: 100, height: 100, child: Text('TOMBOL')),
            ),
          ),
        ),
      );

  testWidgets('tekan: mengecil ke 1-depth dalam ~80 ms; lepas: memantul '
      '(sempat >1) lalu mendarat di 1', (tester) async {
    await tester.pumpWidget(host());
    expect(scaleOf(tester), 1);

    final g = await tester.startGesture(tester.getCenter(find.text('TOMBOL')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final mid = scaleOf(tester);
    expect(mid, lessThan(1));
    expect(mid, greaterThan(0.9));
    await tester.pump(const Duration(milliseconds: 60));
    expect(scaleOf(tester), closeTo(0.9, 0.005)); // tertekan penuh

    await g.up();
    var maxS = 0.0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      final s = scaleOf(tester);
      if (s > maxS) maxS = s;
    }
    expect(maxS, greaterThan(1.0)); // overshoot
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);
  });

  testWidgets('tidak mengganggu tap anak', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(onTap: () => taps++));
    await tester.tap(find.text('TOMBOL'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('animasi dimatikan di sistem: tidak ada skala', (tester) async {
    await tester.pumpWidget(host(reduced: true));
    final g = await tester.startGesture(tester.getCenter(find.text('TOMBOL')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(scaleOf(tester), 1);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('cancel (geser keluar) juga mengembalikan skala', (tester) async {
    await tester.pumpWidget(host());
    final g = await tester.startGesture(tester.getCenter(find.text('TOMBOL')));
    await tester.pump(const Duration(milliseconds: 120));
    await g.cancel();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);
  });
}
