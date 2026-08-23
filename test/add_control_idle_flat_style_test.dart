import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Susulan diskusi desain — keluhan "terlalu ramai" saat idle (banyak
/// lingkaran solid berwarna sekaligus di grid produk). SEBELUM di
/// keranjang: lingkaran TIDAK diisi (transparan) & TANPA shadow, cuma
/// ikon "+" polos warna netral + SATU garis putus-putus VERTIKAL di
/// kirinya. Awalnya begitu masuk keranjang (qty>0) lingkaran kembali
/// solid berwarna — TAPI itu SUPERSEDED oleh revisi susulan di bawah.
///
/// Revisi susulan #1 — ring MELINGKAR dibuang total, diganti satu garis
/// vertikal saja, warna `outlineVariant`.
///
/// Revisi susulan #2 (permintaan user, TERBARU) — lingkaran solid yang
/// tadinya "kembali" saat qty>0 SEKARANG DIHILANGKAN JUGA: baik idle
/// maupun di-keranjang, TIDAK ADA fill/latar sama sekali (`AddControl`
/// tidak lagi punya `AnimatedContainer`/`Container` berdekorasi warna utk
/// lingkaran utama/minus — cuma `SizedBox` transparan sbg cakupan
/// sentuh). Warna kini murni pada ANGKA/IKON-nya, mengikuti sisi (kanan
/// = hijau `AppTheme.changeFg`, kiri = merah `AppTheme.debtFg`), bukan
/// pada fill lingkaran (yang sudah tidak ada). Ikon "+" idle JUGA
/// dikecilkan sedikit (permintaan user) — cakupan sentuh TIDAK ikut
/// mengecil.
void main() {
  setUp(() => AddControl.clearActive());

  Widget wrap(Widget child) => MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets(
      'idle (qty=0): TIDAK ada fill/Container sama sekali, ikon "+" warna '
      'netral (bukan putih), garis putus-putus vertikal tampil',
      (tester) async {
    await tester.pumpWidget(wrap(AddControl(qty: 0, onTap: () {})));
    await tester.pumpAndSettle();

    // Tidak ada lagi AnimatedContainer/Container berdekorasi warna untuk
    // lingkaran utama — sudah diganti SizedBox transparan.
    expect(find.byType(AnimatedContainer), findsNothing,
        reason: 'lingkaran utama tidak lagi memakai AnimatedContainer '
            'berdekorasi (fill dihilangkan total)');

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
      'sudah di keranjang (qty>0): TETAP tidak ada fill/lingkaran solid — '
      'hanya angka & ikon minus yang tampil, mengambang tanpa latar',
      (tester) async {
    await tester.pumpWidget(wrap(AddControl(qty: 2, onTap: () {})));
    await tester.pumpAndSettle();

    expect(find.byType(AnimatedContainer), findsNothing,
        reason: 'di keranjang pun lingkaran solid SUDAH DIHILANGKAN — '
            'revisi susulan terbaru, beda dari perilaku lama');

    // Angka qty (sisi kanan/"+") warna hijau, ikon minus (sisi kiri) merah
    // — warna "sisi", bukan lagi kontras thd fill yang sudah tak ada.
    final qtyText = tester.widget<Text>(find.text('2'));
    expect(qtyText.style?.color, AppTheme.changeFg(false));

    final minusIcon = tester.widget<Icon>(find.byIcon(Icons.remove_rounded));
    expect(minusIcon.color, AppTheme.debtFg(false));

    // Garis putus-putus HANYA relevan saat idle -- begitu produk sudah di
    // keranjang, stepper penuh (minus + angka) yang tampil, tanpa garis.
    final hasDashedLine = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((w) => w.painter.runtimeType.toString() == '_DashedVLinePainter');
    expect(hasDashedLine, isFalse,
        reason: 'di keranjang: garis putus-putus tidak digambar lagi');
  });
}
