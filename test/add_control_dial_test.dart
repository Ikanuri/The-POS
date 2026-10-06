import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Revolver qty: geser "+" ke KIRI = qty naik, balik ke kanan = turun
/// (minimum 1). Pita muncul di kiri selama digeser, hilang saat dilepas.
void main() {
  setUp(() => AddControl.clearActive());

  Future<List<double>> pumpStepper(WidgetTester tester, double qty,
      {bool dial = true}) async {
    final calls = <double>[];
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: StatefulBuilder(builder: (context, setState) {
            return AddControl(
              qty: qty,
              size: 46,
              onTap: () {},
              onMinus: () {},
              onSetQty: dial
                  ? (q) {
                      calls.add(q);
                      setState(() => qty = q);
                    }
                  : null,
            );
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return calls;
  }

  Finder plus() => find
      .descendant(
          of: find.byType(AddControl), matching: find.byType(GestureDetector))
      .last;

  testWidgets('geser pelan ke kiri menaikkan qty & pita muncul lalu hilang',
      (tester) async {
    final calls = await pumpStepper(tester, 3);
    final g = await tester.startGesture(tester.getCenter(plus()));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(-11, 0),
          timeStamp: Duration(milliseconds: 40 * (i + 1)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(calls, isNotEmpty);
    expect(calls.last, greaterThan(3));
    expect(calls.last, lessThanOrEqualTo(14));
    expect(calls, orderedEquals([...calls]..sort()),
        reason: 'tidak boleh turun saat terus digeser ke kiri');
    expect(find.byType(CustomPaint), findsWidgets);
    final during = find.text('${calls.last.toInt()}');
    expect(during, findsWidgets, reason: 'angka besar tampil di pita');
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('geser balik ke kanan menurunkan qty, tidak di bawah 1',
      (tester) async {
    final calls = await pumpStepper(tester, 2);
    final g = await tester.startGesture(tester.getCenter(plus()));
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(40, 0),
          timeStamp: Duration(milliseconds: 40 * (i + 1)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(calls, isNotEmpty);
    expect(calls.every((q) => q >= 1), isTrue);
    expect(calls.last, 1);
  });

  testWidgets('geser cepat meloncat lebih jauh daripada geser pelan',
      (tester) async {
    final slow = await pumpStepper(tester, 1);
    var g = await tester.startGesture(tester.getCenter(plus()));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(-20, 0),
          timeStamp: Duration(milliseconds: 100 * (i + 1)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await g.up();
    await tester.pumpAndSettle();
    final slowQty = slow.last;

    AddControl.clearActive();
    final fast = await pumpStepper(tester, 1);
    g = await tester.startGesture(tester.getCenter(plus()));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(-20, 0),
          timeStamp: Duration(milliseconds: 5 * (i + 1)));
      await tester.pump(const Duration(milliseconds: 5));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(fast.last, greaterThan(slowQty),
        reason: 'jarak sama tapi lebih cepat = loncatan lebih besar');
  });

  testWidgets('qty desimal & onSetQty null: tidak ada revolver',
      (tester) async {
    final calls = await pumpStepper(tester, 2.5);
    final g = await tester.startGesture(tester.getCenter(plus()));
    await g.moveBy(const Offset(-120, 0));
    await g.up();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    final calls2 = await pumpStepper(tester, 3, dial: false);
    final g2 = await tester.startGesture(tester.getCenter(plus()));
    await g2.moveBy(const Offset(-120, 0));
    await g2.up();
    await tester.pumpAndSettle();
    expect(calls2, isEmpty);
  });

  testWidgets('tap biasa tetap memanggil onTap (tidak jadi revolver)',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AddControl(
              qty: 3, onTap: () => taps++, onMinus: () {}, onSetQty: (_) {}),
        ),
      ),
    ));
    await tester.tap(plus());
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
