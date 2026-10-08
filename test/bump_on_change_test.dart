import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/widgets/bump_on_change.dart';

void main() {
  double scaleOf(WidgetTester tester) {
    final t = tester.widget<Transform>(find
        .descendant(
            of: find.byType(BumpOnChange), matching: find.byType(Transform))
        .first);
    return t.transform.getMaxScaleOnAxis();
  }

  Widget host(Object v, {bool reduced = false}) => MaterialApp(
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
            child: child!),
        home: Center(child: BumpOnChange(value: v, child: Text('$v'))),
      );

  testWidgets('nilai awal tidak berdenyut; berubah -> skala naik lalu kembali 1',
      (tester) async {
    await tester.pumpWidget(host(1));
    expect(scaleOf(tester), 1);

    await tester.pumpWidget(host(2));
    await tester.pump(const Duration(milliseconds: 50)); // naik
    expect(scaleOf(tester), greaterThan(1.02));
    expect(find.text('2'), findsOneWidget); // satu widget saja
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);

    // Nilai sama -> tidak berdenyut.
    await tester.pumpWidget(host(2));
    await tester.pump(const Duration(milliseconds: 50));
    expect(scaleOf(tester), 1);
  });

  testWidgets('animasi dimatikan di sistem -> tidak berdenyut', (tester) async {
    await tester.pumpWidget(host(1, reduced: true));
    await tester.pumpWidget(host(2, reduced: true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(scaleOf(tester), 1);
  });

  testWidgets('angka BERKURANG tidak membengkak; kenaikan membengkak ~430 ms; '
      'teks non-angka membengkak tiap berubah', (tester) async {
    await tester.pumpWidget(host(5));
    await tester.pumpWidget(host(4)); // turun
    await tester.pump(const Duration(milliseconds: 50));
    expect(scaleOf(tester), 1);
    await tester.pumpAndSettle();

    await tester.pumpWidget(host(6)); // naik
    await tester.pump(const Duration(milliseconds: 100));
    expect(scaleOf(tester), greaterThan(1.02));
    await tester.pump(const Duration(milliseconds: 250));
    expect(scaleOf(tester), greaterThan(1.0)); // masih menyusut kembali (430 ms)
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);

    await tester.pumpWidget(host('abc'));
    await tester.pumpWidget(host('abd')); // non-angka
    await tester.pump(const Duration(milliseconds: 100));
    expect(scaleOf(tester), greaterThan(1.02));
    await tester.pumpAndSettle();
  });
}
