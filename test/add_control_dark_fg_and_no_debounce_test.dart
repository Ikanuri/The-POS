import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Revisi user:
/// - Item 6: di mode gelap, lingkaran hijau stepper (produk sudah di
///   keranjang) memakai hijau muda → angka/"+" harus GELAP, bukan putih.
/// - Item 3: debounce anti-missclick stepper dimatikan — tap +/- cepat
///   berturut-turut semuanya diproses (tidak ada yang ditelan).
void main() {
  setUp(() => AddControl.clearActive());

  Widget wrap(Widget child, {required Brightness brightness}) => MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets(
      'Item 6 — mode GELAP: angka di lingkaran hijau (di keranjang) berwarna '
      'gelap, bukan putih', (tester) async {
    await tester.pumpWidget(
        wrap(AddControl(qty: 3, onTap: () {}, onMinus: () {}),
            brightness: Brightness.dark));
    await tester.pumpAndSettle();

    final txt = tester.widget<Text>(find.text('3'));
    expect(txt.style?.color, const Color(0xFF0A3D28),
        reason: 'angka di lingkaran hijau harus gelap di mode gelap');
  });

  testWidgets('Item 6 — mode TERANG: angka di lingkaran hijau tetap putih',
      (tester) async {
    await tester.pumpWidget(
        wrap(AddControl(qty: 3, onTap: () {}, onMinus: () {}),
            brightness: Brightness.light));
    await tester.pumpAndSettle();

    final txt = tester.widget<Text>(find.text('3'));
    expect(txt.style?.color, Colors.white,
        reason: 'mode terang tidak berubah (tetap putih)');
  });

  testWidgets(
      'Item 3 — tap "+" cepat berturut TIDAK di-debounce (semua diproses)',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(AddControl(qty: 0, onTap: () => taps++),
        brightness: Brightness.light));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AddControl));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byType(AddControl));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byType(AddControl));
    await tester.pump(const Duration(milliseconds: 20));

    expect(taps, 3,
        reason: 'tanpa debounce, semua tap cepat harus diproses (dulu tap '
            'kedua/ketiga <150ms ditelan)');
  });
}
