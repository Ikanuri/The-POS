import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Permintaan user (Item 13): supaya tidak salah pencet, tap +/- yang datang
/// terlalu rapat (jari geser dikit lalu kena tombol sebelah) diabaikan —
/// disepakati pakai "debounce logic" (bukan physical dead-zone di sekitar
/// tombol).
void main() {
  testWidgets(
      'tap ganda dalam waktu SANGAT singkat (<150ms) — hanya tap pertama '
      'diproses, tap kedua diabaikan (anti-missclick)', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AddControl(qty: 0, onTap: () => tapCount++),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AddControl));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.byType(AddControl));
    await tester.pump(const Duration(milliseconds: 200)); // lunasi Timer internal

    expect(tapCount, 1,
        reason: 'tap kedua yang datang <150ms setelah tap pertama harus '
            'diabaikan (kemungkinan missclick, bukan niat user)');
  });

  testWidgets('tap dengan jeda WAJAR (>150ms) — semua tap diproses normal',
      (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AddControl(qty: 0, onTap: () => tapCount++),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AddControl));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(AddControl));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(AddControl));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tapCount, 3,
        reason: 'tap berjeda wajar (niat user nambah qty berkali-kali) '
            'tidak boleh ikut kena debounce');
  });
}
