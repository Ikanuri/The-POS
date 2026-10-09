import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/widgets/revolver_picker.dart';

void main() {
  Future<void> pump(WidgetTester t, ValueNotifier<int> idx) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder<int>(
            valueListenable: idx,
            builder: (_, v, __) => RevolverPicker(
              count: 5,
              index: v,
              labelOf: (i) => 'n$i',
              onChanged: (i) => idx.value = i,
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('geser kiri menaikkan, geser kanan menurunkan', (t) async {
    final idx = ValueNotifier(2);
    await pump(t, idx);
    Future<void> swipe(double dx) async {
      final g = await t
          .startGesture(t.getCenter(find.byKey(const Key('revolver-picker'))));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(Offset(dx / 10, 0));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await t.pumpAndSettle();
    }

    await swipe(-60);
    expect(idx.value, greaterThan(2));
    final up = idx.value;
    await swipe(60);
    expect(idx.value, lessThan(up));
  });

  testWidgets('tap panah menggeser satu langkah & batas tak terlampaui',
      (t) async {
    final idx = ValueNotifier(0);
    await pump(t, idx);
    await t.tap(find.byKey(const Key('revolver-prev')));
    await t.pumpAndSettle();
    expect(idx.value, 0);
    await t.tap(find.byKey(const Key('revolver-next')));
    await t.pumpAndSettle();
    expect(idx.value, 1);
    idx.value = 4;
    await t.pumpAndSettle();
    await t.drag(
        find.byKey(const Key('revolver-picker')), const Offset(-100, 0));
    await t.pumpAndSettle();
    expect(idx.value, 4);
  });
}
