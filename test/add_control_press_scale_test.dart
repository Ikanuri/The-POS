import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Permintaan user: tombol stepper (`AddControl`) membesar sesaat saat
/// ditekan, mengecil lagi saat dilepas atau jari geser keluar area tombol
/// (feedback taktil, bukan cuma tap instan tanpa respons visual).
void main() {
  testWidgets(
      'tombol "+" membesar (AnimatedScale) saat ditekan, kembali normal '
      'saat dilepas', (tester) async {
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

    expect(scaleOf().scale, 1.0, reason: 'normal sebelum ditekan');

    final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AddControl)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(scaleOf().scale, greaterThan(1.0),
        reason: 'membesar selagi jari masih menekan tombol');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(scaleOf().scale, 1.0, reason: 'kembali normal setelah dilepas');
  });

  testWidgets(
      'tombol mengecil lagi kalau jari geser keluar area tombol sebelum '
      'dilepas (tap dibatalkan, bukan diproses)', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AddControl(qty: 0, onTap: () => tapCount++),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    AnimatedScale scaleOf() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale));

    final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AddControl)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(scaleOf().scale, greaterThan(1.0));

    // Geser jauh keluar area tombol kecil ini (jauh melebihi touch slop)
    // sebelum dilepas — TapGestureRecognizer bawaan Flutter membatalkan
    // tap-nya sendiri (onTapCancel), tombol harus ikut mengecil balik.
    await gesture.moveBy(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(scaleOf().scale, 1.0,
        reason: 'mengecil lagi krn tap dibatalkan (jari sudah pindah area)');
    expect(tapCount, 0,
        reason: 'tap yang dibatalkan (geser keluar) tidak boleh diproses');
  });
}
