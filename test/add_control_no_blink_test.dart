import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Revisi user — angka qty di stepper minus TIDAK boleh "berkedip" (sekejap
/// pindah balik ke sisi +) saat tombol + ditekan LAGI. Penyebab lama:
/// StepperActiveScope menonaktifkan stepper di event pointer-DOWN (termasuk
/// saat pointer jatuh tepat di stepper yang sedang aktif), lalu stepper
/// mengaktifkan diri lagi di event UP — jeda down→up itu yang tampak berkedip.
/// Fix: scope tidak menonaktifkan bila pointer-down mengenai sebuah stepper.
void main() {
  setUp(() => AddControl.clearActive());

  // [0]=minus (kiri), [1]=main/plus (kanan) saat inCart.
  Finder buttons() => find.descendant(
      of: find.byType(AddControl), matching: find.byType(GestureDetector));

  testWidgets(
      'menekan lagi tombol + (pointer-down) TIDAK memindah balik angka — '
      'stepper tetap aktif, tidak berkedip', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StepperActiveScope(
            child: AddControl(qty: 3, onTap: () {}, onMinus: () {}),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Tap + → aktif; angka pindah ke sisi minus (kiri), + jadi ikon polos.
    await tester.tap(buttons().at(1));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsNothing);

    // Tekan lagi tombol + TANPA melepas (pointer-down) — dulu memicu
    // scope.clearActive → angka berkedip balik ke kanan & ikon "-" muncul.
    final gesture =
        await tester.startGesture(tester.getCenter(buttons().at(1)));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.add_rounded), findsOneWidget,
        reason: 'angka tidak boleh berkedip balik: + tetap ikon polos');
    expect(find.byIcon(Icons.remove_rounded), findsNothing,
        reason: 'sisi minus tetap menampilkan angka selama ditekan');
    expect(AddControl.activeStepper.value, isNotNull,
        reason: 'stepper tetap aktif saat ditekan lagi (scope tidak '
            'menonaktifkannya di pointer-down)');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'pointer-down di LUAR stepper tetap menonaktifkannya (perilaku pijakan '
      'jempol tidak rusak)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepperActiveScope(
          child: Column(
            children: [
              const SizedBox(height: 300, key: Key('luar')),
              Center(
                child: AddControl(qty: 3, onTap: () {}, onMinus: () {}),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(buttons().at(1)); // aktifkan
    await tester.pumpAndSettle();
    expect(AddControl.activeStepper.value, isNotNull);

    // Pointer-down di area kosong (bukan stepper) → nonaktif.
    await tester.tapAt(tester.getCenter(find.byKey(const Key('luar'))));
    await tester.pumpAndSettle();
    expect(AddControl.activeStepper.value, isNull,
        reason: 'tap di luar stepper harus tetap menonaktifkannya');
  });
}
