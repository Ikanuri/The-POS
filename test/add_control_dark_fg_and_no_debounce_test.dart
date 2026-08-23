import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Revisi user:
/// - Item 6 (LAMA, kini SUPERSEDED — lihat revisi susulan di bawah): di
///   mode gelap, lingkaran hijau stepper (produk sudah di keranjang)
///   memakai hijau muda → angka/"+" harus GELAP, bukan putih.
/// - Revisi susulan (permintaan user, lebih baru): lingkaran solid
///   dihilangkan TOTAL — angka qty sekarang selalu warna `AppTheme.
///   changeFg(isDark)` (warna "sisi", bukan warna kontras thd fill yang
///   sudah tidak ada lagi), sama di kedua mode terang/gelap. Test lama di
///   atas (putih vs `0xFF0A3D28`) sudah tidak berlaku, diganti assersi
///   baru di bawah.
/// - Item 3: debounce anti-missclick stepper dimatikan — tap +/- cepat
///   berturut-turut semuanya diproses (tidak ada yang ditelan).
void main() {
  setUp(() => AddControl.clearActive());

  Widget wrap(Widget child, {required Brightness brightness}) => MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets(
      'mode GELAP: angka qty (di keranjang) pakai warna sisi hijau gelap '
      '(AppTheme.changeFg(true)), TANPA lingkaran/latar', (tester) async {
    await tester.pumpWidget(
        wrap(AddControl(qty: 3, onTap: () {}, onMinus: () {}),
            brightness: Brightness.dark));
    await tester.pumpAndSettle();

    final txt = tester.widget<Text>(find.text('3'));
    expect(txt.style?.color, AppTheme.changeFg(true));
  });

  testWidgets(
      'mode TERANG: angka qty (di keranjang) pakai warna sisi hijau terang '
      '(AppTheme.changeFg(false)), TANPA lingkaran/latar', (tester) async {
    await tester.pumpWidget(
        wrap(AddControl(qty: 3, onTap: () {}, onMinus: () {}),
            brightness: Brightness.light));
    await tester.pumpAndSettle();

    final txt = tester.widget<Text>(find.text('3'));
    expect(txt.style?.color, AppTheme.changeFg(false));
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
