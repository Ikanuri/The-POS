import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/widgets/scroll_edge_fade.dart';

void main() {
  testWidgets('pemudaran atas/bawah muncul sesuai tinggi & tak menelan sentuhan',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: ScrollEdgeFade(
            top: 20,
            bottom: 30,
            child: ListView(children: [
              for (var i = 0; i < 3; i++)
                GestureDetector(
                    onTap: () => taps++,
                    child: const SizedBox(height: 60, child: Text('item'))),
            ]),
          ),
        ),
      ),
    ));
    expect(tester.getSize(find.byKey(const Key('edge-fade-top')).first).height,
        20);
    expect(
        tester.getSize(find.byKey(const Key('edge-fade-bottom')).first).height,
        30);
    // Tap di area yang tertutup strip atas tetap sampai ke item.
    await tester.tapAt(const Offset(40, 10));
    expect(taps, 1);
  });

  testWidgets('tanpa tinggi = tanpa strip', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ScrollEdgeFade(child: SizedBox()))));
    expect(find.byKey(const Key('edge-fade-top')), findsNothing);
    expect(find.byKey(const Key('edge-fade-bottom')), findsNothing);
  });
}
