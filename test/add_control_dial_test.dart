import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Revolver qty (bulat = horizontal, pecahan = vertikal): geser "+" ke KIRI = qty naik, balik ke kanan = turun
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

  testWidgets('onSetQty null: tidak ada revolver', (tester) async {
    final calls = await pumpStepper(tester, 3, dial: false);
    final g = await tester.startGesture(tester.getCenter(plus()));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(-30, 0),
          timeStamp: Duration(milliseconds: 100 * (i + 1)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  // Geser pelan (100 ms/langkah) supaya pengali kecepatan = 1x.
  Future<void> drag(WidgetTester tester, TestGesture g, Offset step, int n,
      {int startMs = 0}) async {
    for (var i = 0; i < n; i++) {
      await g.moveBy(step,
          timeStamp: Duration(milliseconds: startMs + 100 * (i + 1)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('revolver vertikal (pecahan)', () {
    testWidgets('geser ATAS: 0.25 -> 0.5 -> 0.75 (qty bulat 3 dipertahankan)',
        (tester) async {
      final calls = await pumpStepper(tester, 3);
      final g = await tester.startGesture(tester.getCenter(plus()));
      // 8px slop pertama ditelan; lalu 25px -> 0.25
      await drag(tester, g, const Offset(0, -9), 1);
      await drag(tester, g, const Offset(0, -21), 1, startMs: 100);
      expect(calls.last, 3.25);
      await drag(tester, g, const Offset(0, -20), 1, startMs: 200);
      expect(calls.last, 3.5);
      await drag(tester, g, const Offset(0, -20), 1, startMs: 300);
      expect(calls.last, 3.75);
      await drag(tester, g, const Offset(0, -60), 1, startMs: 400);
      expect(calls.last, 3.75, reason: 'maksimum 0.75');
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('geser BAWAH: 0.10 lalu naik 0.01 per langkah', (tester) async {
      final calls = await pumpStepper(tester, 3);
      final g = await tester.startGesture(tester.getCenter(plus()));
      await drag(tester, g, const Offset(0, 9), 1);
      await drag(tester, g, const Offset(0, 10), 1, startMs: 100);
      expect(calls.last, 3.1);
      await drag(tester, g, const Offset(0, 6), 1, startMs: 200);
      expect(calls.last, 3.11);
      await drag(tester, g, const Offset(0, 6), 1, startMs: 300);
      expect(calls.last, 3.12);
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('vertikal lalu horizontal: atas 0.25 lalu kiri ke 5 -> 5.25',
        (tester) async {
      final calls = await pumpStepper(tester, 3);
      final g = await tester.startGesture(tester.getCenter(plus()));
      await drag(tester, g, const Offset(0, -9), 1);
      await drag(tester, g, const Offset(0, -21), 1, startMs: 100);
      expect(calls.last, 3.25);
      await drag(tester, g, const Offset(-11, 0), 2, startMs: 200);
      expect(calls.last, 5.25, reason: 'titik berhenti = 5 + 0.25');
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('horizontal lalu vertikal: kiri ke 5 lalu atas 0.25 -> 5.25',
        (tester) async {
      final calls = await pumpStepper(tester, 3);
      final g = await tester.startGesture(tester.getCenter(plus()));
      await drag(tester, g, const Offset(-9, 0), 1);
      await drag(tester, g, const Offset(-11, 0), 2, startMs: 100);
      expect(calls.last, 5);
      await drag(tester, g, const Offset(0, -21), 1, startMs: 300);
      expect(calls.last, 5.25);
      // Kembali ke tengah (zona mati) = pecahan hilang.
      await drag(tester, g, const Offset(0, 21), 1, startMs: 400);
      expect(calls.last, 5);
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('qty desimal awal: pecahan dipertahankan saat geser horizontal',
        (tester) async {
      final calls = await pumpStepper(tester, 2.5);
      final g = await tester.startGesture(tester.getCenter(plus()));
      await drag(tester, g, const Offset(-9, 0), 1);
      await drag(tester, g, const Offset(-11, 0), 2, startMs: 100);
      expect(calls.last, 4.5);
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('pita menampilkan angka desimal selama digeser',
        (tester) async {
      await pumpStepper(tester, 3);
      final g = await tester.startGesture(tester.getCenter(plus()));
      await drag(tester, g, const Offset(0, -9), 1);
      await drag(tester, g, const Offset(0, -21), 1, startMs: 100);
      expect(find.text('3.25'), findsWidgets);
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('"+" idle: geser VERTIKAL tidak jadi revolver (daftar tetap '
        'bisa digulir)', (tester) async {
      final calls = <double>[];
      final controller = ScrollController();
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: [
              for (var i = 0; i < 30; i++)
                SizedBox(
                  height: 60,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AddControl(
                        qty: 0,
                        size: 46,
                        onTap: () {},
                        onSetQty: calls.add),
                  ),
                ),
            ],
          ),
        ),
      ));
      final g = await tester.startGesture(
          tester.getCenter(find.byType(AddControl).first));
      await drag(tester, g, const Offset(0, -20), 4);
      await g.up();
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(controller.offset, greaterThan(0), reason: 'daftar tergulir');
    });

    test('fractionForOffset: zona mati & batas', () {
      expect(fractionForOffsetForTest(0), 0);
      expect(fractionForOffsetForTest(-19), 0);
      expect(fractionForOffsetForTest(-20), 0.25);
      expect(fractionForOffsetForTest(-45), 0.5);
      expect(fractionForOffsetForTest(-200), 0.75);
      expect(fractionForOffsetForTest(9), 0);
      expect(fractionForOffsetForTest(10), 0.1);
      expect(fractionForOffsetForTest(16), 0.11);
      expect(fractionForOffsetForTest(9999), 0.99);
    });
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
