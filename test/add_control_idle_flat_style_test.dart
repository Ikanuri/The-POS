import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Susulan diskusi desain (mockup: Alt.7 netral->berwarna + Alt.4 dashed
/// ring + Alt.9 flat) — keluhan "terlalu ramai" saat idle (banyak lingkaran
/// solid berwarna sekaligus di grid produk). SEBELUM di keranjang:
/// lingkaran TIDAK diisi (transparan) & TANPA shadow, cuma ring
/// putus-putus (`CustomPaint`) warna netral (`onSurfaceVariant`) + ikon
/// "+" senada. Begitu masuk keranjang (qty>0): kembali solid seperti
/// sebelumnya (fill + warna brand), TETAP tanpa shadow (flat).
void main() {
  setUp(() => AddControl.clearActive());

  Widget wrap(Widget child) => MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets(
      'idle (qty=0): TIDAK ada isi solid, TIDAK ada shadow, ikon "+" warna '
      'netral (bukan putih)', (tester) async {
    await tester.pumpWidget(wrap(AddControl(qty: 0, onTap: () {})));
    await tester.pumpAndSettle();

    // Lingkaran utama transparan (tidak diisi warna brand) saat idle.
    final decoratedBoxes =
        tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
    final mainDecoration = decoratedBoxes.first.decoration as BoxDecoration;
    expect(mainDecoration.color, Colors.transparent,
        reason: 'idle: lingkaran tidak boleh diisi warna solid lagi');
    expect(mainDecoration.boxShadow, anyOf(isNull, isEmpty),
        reason: 'idle: flat, tanpa shadow');

    // Ring putus-putus (`_DashedCirclePainter`, dicari via nama runtime krn
    // private) tampil; ikon "+" netral (bukan putih).
    final hasDashedRing = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((w) => w.painter.runtimeType.toString() == '_DashedCirclePainter');
    expect(hasDashedRing, isTrue,
        reason: 'idle: ring putus-putus harus tampil');
    final icon = tester.widget<Icon>(find.byIcon(Icons.add_rounded));
    expect(icon.color, isNot(Colors.white),
        reason: 'idle: ikon "+" warna netral, bukan putih spt sebelumnya');
  });

  testWidgets(
      'sudah di keranjang (qty>0): lingkaran KEMBALI solid berwarna, tetap '
      'TANPA shadow (flat)', (tester) async {
    await tester.pumpWidget(wrap(AddControl(qty: 2, onTap: () {})));
    await tester.pumpAndSettle();

    final decoratedBoxes =
        tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
    final mainDecoration = decoratedBoxes.first.decoration as BoxDecoration;
    expect(mainDecoration.color, isNot(Colors.transparent),
        reason: 'di keranjang: lingkaran solid berwarna spt sebelumnya');
    expect(mainDecoration.boxShadow, anyOf(isNull, isEmpty),
        reason: 'flat berlaku di kedua state, bukan cuma idle');

    // Ring putus-putus HANYA relevan saat idle -- tidak perlu digambar lagi
    // begitu sudah solid (fill sudah jadi "border"-nya secara visual).
    final hasDashedRing = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((w) => w.painter.runtimeType.toString() == '_DashedCirclePainter');
    expect(hasDashedRing, isFalse,
        reason: 'di keranjang: ring putus-putus tidak perlu digambar lagi');
  });
}
