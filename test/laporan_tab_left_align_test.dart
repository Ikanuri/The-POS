import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/laporan/laporan_screen.dart';

import 'helpers/pump_app.dart';

/// User (screenshot beranotasi panah, laporan ke-2): gap "renggang" yang
/// dimaksud SEJAK AWAL adalah jarak HORIZONTAL di kiri tab "Ringkasan" itu
/// sendiri (bukan jarak vertikal ke kartu KPI, 2 percobaan sebelumnya salah
/// sasaran) — akar: `TabBar(isScrollable: true)` default `TabAlignment.
/// startOffset` (~52dp inset). Fix: `TabAlignment.start`.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'tab "Ringkasan" menempel flush ke kiri (bukan ~52dp inset bawaan '
      'TabBar scrollable)', (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const LaporanScreen());
    await tester.pumpAndSettle();

    final tabLeft = tester.getTopLeft(find.text('Ringkasan')).dx;
    // Judul "Laporan" (AppBar title, inset standar Material ~16-20px) jadi
    // acuan pembanding — tab pertama harus sejajar/dekat, BUKAN puluhan px
    // lebih ke kanan lagi krn inset bawaan TabAlignment.startOffset (~52px).
    final titleLeft = tester.getTopLeft(find.text('Laporan')).dx;
    expect(tabLeft, lessThan(titleLeft + 20),
        reason: 'tab pertama harus flush kiri, bukan ada inset besar ~52px '
            'tambahan dari TabAlignment.startOffset bawaan Flutter');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
