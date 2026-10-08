import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/theme/app_motion.dart';
import 'package:the_pos/core/theme/app_overlays.dart';
import 'package:the_pos/core/theme/app_theme.dart';

/// Sheet & dialog memakai animasi baku app (easeOutQuint; dialog fade+skala).
void main() {
  Future<void> pumpHost(WidgetTester tester,
      {required Widget Function(BuildContext) button,
      bool reduced = false}) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: Scaffold(body: Builder(builder: (c) => Center(child: button(c)))),
    ));
  }

  Widget sheetButton(BuildContext c) => ElevatedButton(
        onPressed: () => showAppSheet<void>(
          context: c,
          builder: (_) => const SizedBox(
              height: 200, child: Center(child: Text('ISI-SHEET'))),
        ),
        child: const Text('buka'),
      );

  Widget dialogButton(BuildContext c) => ElevatedButton(
        onPressed: () => showAppDialog<void>(
          context: c,
          builder: (_) => const AlertDialog(content: Text('ISI-DIALOG')),
        ),
        child: const Text('buka'),
      );

  testWidgets('sheet: naik bertahap (tak langsung di posisi akhir) lalu '
      'mendarat; durasi mengikuti token', (tester) async {
    await pumpHost(tester, button: sheetButton);
    await tester.tap(find.text('buka'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final yEarly = tester.getTopLeft(find.text('ISI-SHEET')).dy;
    await tester.pumpAndSettle();
    final yFinal = tester.getTopLeft(find.text('ISI-SHEET')).dy;
    expect(yEarly, greaterThan(yFinal)); // masih di bawah posisi akhir
    // Tutup lewat barrier.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('ISI-SHEET'), findsOneWidget); // masih beranimasi turun
    await tester.pumpAndSettle();
    expect(find.text('ISI-SHEET'), findsNothing);
    expect(AppMotion.medium.inMilliseconds, 260);
  });

  testWidgets('sheet: animasi dimatikan di sistem -> langsung di posisi akhir',
      (tester) async {
    await pumpHost(tester, button: sheetButton, reduced: true);
    await tester.tap(find.text('buka'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final y = tester.getTopLeft(find.text('ISI-SHEET')).dy;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('ISI-SHEET')).dy, y);
  });

  testWidgets('dialog: memudar masuk + membesar dari 0,94, lalu penuh',
      (tester) async {
    await pumpHost(tester, button: dialogButton);
    await tester.tap(find.text('buka'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final scaleFinder = find.ancestor(
        of: find.text('ISI-DIALOG'), matching: find.byType(ScaleTransition));
    final fadeFinder = find.ancestor(
        of: find.text('ISI-DIALOG'), matching: find.byType(FadeTransition));
    final scale = tester.widget<ScaleTransition>(scaleFinder.first).scale.value;
    final op = tester.widget<FadeTransition>(fadeFinder.first).opacity.value;
    expect(scale, inInclusiveRange(0.94, 1.0));
    expect(scale, lessThan(1));
    expect(op, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<ScaleTransition>(scaleFinder.first).scale.value, 1);
    expect(tester.widget<FadeTransition>(fadeFinder.first).opacity.value, 1);

    // Tutup: keluar lebih singkat dari masuk.
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    await tester.pump(AppMotion.fast + const Duration(milliseconds: 20));
    expect(find.text('ISI-DIALOG'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog: animasi dimatikan -> tanpa fade/skala, tertutup seketika',
      (tester) async {
    await pumpHost(tester, button: dialogButton, reduced: true);
    await tester.tap(find.text('buka'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('ISI-DIALOG'), findsOneWidget);
    final scaleFinder = find.ancestor(
        of: find.text('ISI-DIALOG'), matching: find.byType(ScaleTransition));
    expect(scaleFinder, findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('ISI-DIALOG'), findsNothing);
  });
}
