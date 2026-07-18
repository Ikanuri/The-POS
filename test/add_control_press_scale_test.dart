import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Permintaan user: tombol stepper (`AddControl`) yang di-tap membesar dan
/// TETAP besar ("pijakan jempol" — target tap lebih besar utk tap
/// berikutnya, mengurangi missclick), BUKAN cuma sesaat selagi ditekan.
/// Mengecil lagi HANYA saat user tap AREA LAIN (di luar stepper mana pun,
/// lewat `StepperActiveScope`) atau mulai scroll.
void main() {
  // `AddControl.activeStepper` static (dibagi lintas seluruh app) — reset
  // supaya test lain di file ini/file lain tidak saling bocor.
  setUp(() => AddControl.clearActive());

  testWidgets(
      'tombol "+" membesar (AnimatedScale) setelah di-tap, TETAP besar '
      'setelah jari dilepas (bukan mengecil lagi)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AddControl(qty: 0, onTap: () {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    AnimatedScale scaleOf() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale));

    expect(scaleOf().scale, 1.0, reason: 'normal sebelum ditap');

    await tester.tap(find.byType(AddControl));
    await tester.pumpAndSettle();

    expect(scaleOf().scale, greaterThan(1.0),
        reason: 'TETAP membesar setelah tap selesai (jari sudah lepas)');
  });

  testWidgets(
      'StepperActiveScope: tap di AREA LAIN (di luar stepper) membuat '
      'stepper yang tadi membesar kembali normal', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepperActiveScope(
          child: Column(
            children: [
              AddControl(qty: 0, onTap: () {}),
              const SizedBox(height: 40, width: 40, child: ColoredBox(color: Colors.grey)),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    AnimatedScale scaleOf() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale));

    await tester.tap(find.byType(AddControl));
    await tester.pumpAndSettle();
    expect(scaleOf().scale, greaterThan(1.0));

    await tester.tap(find.byType(ColoredBox));
    await tester.pumpAndSettle();
    expect(scaleOf().scale, 1.0,
        reason: 'tap di area lain (di luar stepper) harus mengecilkan lagi');
  });

  testWidgets(
      'StepperActiveScope: scroll membuat stepper yang tadi membesar '
      'kembali normal', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepperActiveScope(
          child: ListView(
            children: [
              AddControl(qty: 0, onTap: () {}),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    AnimatedScale scaleOf() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale));

    await tester.tap(find.byType(AddControl));
    await tester.pumpAndSettle();
    expect(scaleOf().scale, greaterThan(1.0));

    await tester.drag(find.byType(ListView), const Offset(0, -5));
    await tester.pumpAndSettle();
    expect(scaleOf().scale, 1.0,
        reason: 'scroll harus mengecilkan lagi stepper yang tadi membesar');
  });

  testWidgets(
      'tap stepper KEDUA membuat stepper PERTAMA mengecil lagi (cuma satu '
      'yang aktif sekaligus)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepperActiveScope(
          child: Column(
            children: [
              AddControl(qty: 0, onTap: () {}, key: const Key('a')),
              AddControl(qty: 0, onTap: () {}, key: const Key('b')),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    AnimatedScale scaleOfA() => tester.widget<AnimatedScale>(
        find.descendant(of: find.byKey(const Key('a')), matching: find.byType(AnimatedScale)));
    AnimatedScale scaleOfB() => tester.widget<AnimatedScale>(
        find.descendant(of: find.byKey(const Key('b')), matching: find.byType(AnimatedScale)));

    await tester.tap(find.byKey(const Key('a')));
    await tester.pumpAndSettle();
    expect(scaleOfA().scale, greaterThan(1.0));
    expect(scaleOfB().scale, 1.0);

    await tester.tap(find.byKey(const Key('b')));
    await tester.pumpAndSettle();
    expect(scaleOfA().scale, 1.0,
        reason: 'stepper A harus mengecil lagi begitu stepper B di-tap');
    expect(scaleOfB().scale, greaterThan(1.0));
  });
}
