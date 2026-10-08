import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/widgets/skeleton.dart';

void main() {
  Widget host(Widget child, {bool reduced = false}) => MaterialApp(
        builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
            child: w!),
        home: Scaffold(body: child),
      );

  Alignment beginOf(WidgetTester tester) {
    final box = tester.widget<Container>(find
        .descendant(
            of: find.byType(SkeletonBox), matching: find.byType(Container))
        .first);
    final g = (box.decoration! as BoxDecoration).gradient! as LinearGradient;
    return g.begin as Alignment;
  }

  testWidgets('kilau bergerak (berulang) dan ukuran tetap', (tester) async {
    await tester.pumpWidget(
        host(const Center(child: SkeletonBox(width: 80, height: 12))));
    expect(tester.getSize(find.byType(SkeletonBox)), const Size(80, 12));
    final a = beginOf(tester).x;
    await tester.pump(const Duration(milliseconds: 300));
    final b = beginOf(tester).x;
    expect(b, isNot(a));
    await tester.pump(SkeletonBox.period);
    // Masih beranimasi (berulang), ukuran tak berubah.
    expect(tester.getSize(find.byType(SkeletonBox)), const Size(80, 12));
    await tester.pumpWidget(const SizedBox()); // lepas ticker
  });

  testWidgets('animasi dimatikan: statis dan pumpAndSettle selesai',
      (tester) async {
    await tester.pumpWidget(host(const Center(child: SkeletonBox(width: 80)),
        reduced: true));
    final a = beginOf(tester).x;
    await tester.pump(const Duration(milliseconds: 300));
    expect(beginOf(tester).x, a);
    await tester.pumpAndSettle(); // tidak menggantung
  });

  testWidgets('SkeletonList: baris sebanyak count, tidak bisa disentuh/digulir',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(const SkeletonList(count: 5)));
    expect(find.byType(SkeletonRow), findsNWidgets(5));
    expect(find.bySemanticsLabel('Memuat'), findsOneWidget);
    expect(
        tester
            .widget<ListView>(find.byType(ListView))
            .physics,
        isA<NeverScrollableScrollPhysics>());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
