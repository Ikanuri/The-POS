import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Susulan diskusi desain — keluhan "terlalu ramai" saat idle (banyak
/// lingkaran solid berwarna sekaligus di grid produk). SEBELUM di
/// keranjang: lingkaran TIDAK diisi (transparan) & TANPA shadow, cuma
/// ikon "+" polos warna netral + SATU garis putus-putus VERTIKAL di
/// kirinya. Begitu masuk keranjang (qty>0): kembali solid seperti
/// sebelumnya (fill + warna brand), TETAP tanpa shadow (flat).
///
/// Revisi susulan (permintaan user): ring MELINGKAR dibuang total —
/// dinilai "masih terlalu tegas" walau warnanya sudah netral (lingkaran
/// penuh = banyak garis sekaligus). Diganti satu garis vertikal saja,
/// warna `outlineVariant` (token pembatas paling samar), stroke 1.5.
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

    // Garis putus-putus vertikal (`_DashedVLinePainter`, dicari via nama
    // runtime krn private) tampil; ikon "+" netral (bukan putih).
    final hasDashedLine = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((w) => w.painter.runtimeType.toString() == '_DashedVLinePainter');
    expect(hasDashedLine, isTrue,
        reason: 'idle: garis putus-putus vertikal harus tampil');
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

    // Garis putus-putus HANYA relevan saat idle -- begitu produk sudah di
    // keranjang, stepper penuh (minus + angka) yang tampil, tanpa garis.
    final hasDashedLine = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((w) => w.painter.runtimeType.toString() == '_DashedVLinePainter');
    expect(hasDashedLine, isFalse,
        reason: 'di keranjang: garis putus-putus tidak digambar lagi');
  });
}
