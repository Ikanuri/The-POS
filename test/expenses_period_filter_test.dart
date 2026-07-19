import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/pengaturan/expenses_screen.dart';

import 'helpers/pump_app.dart';

/// Item 42 — filter periode di tab Pengeluaran. Total & daftar mengikuti
/// periode terpilih (Hari Ini / Minggu Ini / Bulan Ini / Custom), bukan lagi
/// selalu bulan berjalan.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'default periode "Bulan Ini": pengeluaran lama (di luar rentang) '
      'TIDAK ikut; ganti periode mengubah label total', (tester) async {
    final now = DateTime.now();
    // Pengeluaran hari ini (masuk semua periode).
    await db.addExpense(type: 'daily_expense', amount: 10000, createdAt: now);
    // Pengeluaran jauh di masa lalu (fixed 2020) — HARUS terfilter keluar
    // dari default "Bulan Ini" (bukti rentang benar-benar dipakai).
    await db.addExpense(
        type: 'daily_expense',
        amount: 5000,
        createdAt: DateTime(2020, 1, 15));

    await pumpWithFakeApp(tester, db: db, child: const ExpensesScreen());
    await tester.pumpAndSettle();

    // Default = Bulan Ini.
    expect(find.text('Total bulan ini'), findsOneWidget);
    expect(find.text(formatRupiah(10000)), findsWidgets,
        reason: 'pengeluaran hari ini masuk periode bulan ini');
    expect(find.text(formatRupiah(5000)), findsNothing,
        reason: 'pengeluaran 2020 di luar rentang bulan ini — tidak tampil');

    // Ganti ke Hari Ini → label total ikut berubah (filter aktif).
    await tester.tap(find.text('Hari Ini'));
    await tester.pumpAndSettle();
    expect(find.text('Total hari ini'), findsOneWidget);
    expect(find.text('Total bulan ini'), findsNothing);
    expect(find.text(formatRupiah(10000)), findsWidgets,
        reason: 'pengeluaran hari ini tetap masuk periode hari ini');

    // Drain drift StreamProvider disposal timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
