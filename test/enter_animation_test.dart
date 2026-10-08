import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/widgets/enter_animation.dart';

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  static int created = 0;
  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 40, child: Text('ROW'));
}

void main() {
  Widget host({bool enabled = true, bool reduced = false}) => MaterialApp(
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
            child: child!),
        home: Scaffold(
          body: Column(children: [
            EnterAnimation(enabled: enabled, child: const _Probe()),
            const Text('BAWAH'),
          ]),
        ),
      );

  testWidgets('baris baru: tinggi membuka + fade; state anak TIDAK dibuat ulang '
      'saat animasi selesai', (tester) async {
    _ProbeState.created = 0;
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 50));
    final h = tester.getSize(find.byType(EnterAnimation)).height;
    expect(h, inExclusiveRange(0, 40));
    final op = tester
        .widget<FadeTransition>(find.descendant(
            of: find.byType(EnterAnimation),
            matching: find.byType(FadeTransition)))
        .opacity
        .value;
    expect(op, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(EnterAnimation)).height, 40);
    expect(_ProbeState.created, 1);
  });

  testWidgets('enabled=false / animasi dimatikan: langsung penuh, tanpa pembungkus',
      (tester) async {
    await tester.pumpWidget(host(enabled: false));
    expect(tester.getSize(find.byType(EnterAnimation)).height, 40);
    expect(find.descendant(of: find.byType(EnterAnimation), matching: find.byType(SizeTransition)), findsNothing);
    await tester.pumpWidget(host(reduced: true));
    await tester.pump();
    expect(tester.getSize(find.byType(EnterAnimation)).height, 40);
  });
}
