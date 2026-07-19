import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Item 43 — selagi stepper aktif, angka qty berpindah ke sisi berlawanan
/// dari tombol yang BARU ditekan (tombol yg ditekan jadi ikon polos): tap
/// "+" → angka pindah ke kiri (sisi minus) & "+" jadi ikon; tap "-" → angka
/// kembali ke kanan (sisi plus) & "-" jadi ikon. Saat stepper tidak lagi
/// aktif (tap area lain/scroll), angka kembali normal di tombol "+".
void main() {
  setUp(() => AddControl.clearActive());

  // Dua GestureDetector di dalam AddControl saat inCart: [0]=minus (kiri),
  // [1]=main/plus (kanan).
  Finder buttons() => find.descendant(
      of: find.byType(AddControl), matching: find.byType(GestureDetector));

  testWidgets(
      'tap + memindah angka ke sisi minus (kiri), tap - mengembalikan ke '
      'sisi plus (kanan)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AddControl(qty: 3, onTap: () {}, onMinus: () {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Normal (belum aktif): angka '3' di kanan, ikon "-" di kiri, tanpa "+".
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);

    // Tap tombol + (kanan, index 1).
    await tester.tap(buttons().at(1));
    await tester.pumpAndSettle();

    // "+" jadi ikon polos, angka pindah ke KIRI (sisi minus), ikon "-" hilang.
    expect(find.byIcon(Icons.add_rounded), findsOneWidget,
        reason: 'tombol + yang baru ditekan jadi ikon polos');
    expect(find.byIcon(Icons.remove_rounded), findsNothing,
        reason: 'sisi minus sekarang menampilkan angka, bukan ikon -');
    expect(tester.getCenter(find.text('3')).dx,
        lessThan(tester.getCenter(find.byIcon(Icons.add_rounded)).dx),
        reason: 'angka harus di kiri (sisi minus), + di kanan');

    // Tap tombol - (kiri, index 0 — sekarang menampilkan angka).
    await tester.tap(buttons().at(0));
    await tester.pumpAndSettle();

    // "-" jadi ikon polos lagi, angka kembali ke KANAN (sisi plus).
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget,
        reason: 'tombol - yang baru ditekan jadi ikon polos');
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(tester.getCenter(find.text('3')).dx,
        greaterThan(tester.getCenter(find.byIcon(Icons.remove_rounded)).dx),
        reason: 'angka kembali ke kanan (sisi +), - di kiri');
  });

  testWidgets(
      'setelah tap + (angka di kiri), stepper dinonaktifkan → angka kembali '
      'NORMAL di tombol + (kanan)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AddControl(qty: 3, onTap: () {}, onMinus: () {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(buttons().at(1)); // tap +
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_rounded), findsOneWidget); // angka pindah kiri

    // Simulasikan tap area lain / scroll (StepperActiveScope memanggil ini).
    AddControl.clearActive();
    await tester.pumpAndSettle();

    // Kembali normal: angka di kanan, ikon "-" di kiri, tanpa "+".
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(tester.getCenter(find.text('3')).dx,
        greaterThan(tester.getCenter(find.byIcon(Icons.remove_rounded)).dx),
        reason: 'setelah nonaktif, angka kembali ke posisi normal (kanan/+)');
  });
}
