import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/widgets/app_slide_slot.dart';

void main() {
  Widget host(Widget? child, {bool reduced = false}) => MaterialApp(
        builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
            child: w!),
        home: Scaffold(
          body: Column(children: [
            const Expanded(child: SizedBox()),
            AppSlideSlot(child: child),
          ]),
        ),
      );

  const bar = SizedBox(key: Key('bar'), height: 100, width: 200);

  testWidgets(
      'muncul: tinggi membuka bertahap lalu penuh; hilang: menutup & dicabut',
      (tester) async {
    await tester.pumpWidget(host(null));
    expect(find.byKey(const Key('bar')), findsNothing);

    await tester.pumpWidget(host(bar));
    await tester.pump(const Duration(milliseconds: 60));
    final mid = tester.getSize(find.byKey(const Key('bar'))).height;
    expect(mid, 100, reason: 'child penuh; yang dianimasikan = ruang slot');
    final slotMid = tester.getSize(find.byType(AppSlideSlot)).height;
    expect(slotMid, inExclusiveRange(0, 100), reason: 'sedang membuka');
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppSlideSlot)).height, 100);

    await tester.pumpWidget(host(null));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('bar')), findsOneWidget,
        reason: 'konten terakhir dipertahankan selama animasi keluar');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bar')), findsNothing);
    expect(tester.getSize(find.byType(AppSlideSlot)).height, 0);
  });

  testWidgets('kurangi animasi: langsung tanpa animasi', (tester) async {
    await tester.pumpWidget(host(null, reduced: true));
    await tester.pumpWidget(host(bar, reduced: true));
    await tester.pump();
    expect(tester.getSize(find.byType(AppSlideSlot)).height, 100);
    await tester.pumpWidget(host(null, reduced: true));
    await tester.pump();
    expect(find.byKey(const Key('bar')), findsNothing);
  });

  testWidgets(
      'sudah ada saat pertama dipasang: langsung penuh (tanpa animasi masuk)',
      (tester) async {
    await tester.pumpWidget(host(bar));
    expect(tester.getSize(find.byType(AppSlideSlot)).height, 100);
  });
}
