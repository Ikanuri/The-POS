import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laporan/laporan_screen.dart';
import 'package:the_pos/features/laporan/tabs/pengeluaran_tab.dart';

import 'helpers/pump_app.dart';

/// Item 49d — tab dedicated "Laporan Pengeluaran": rincian per jenis +
/// grafik tren. Beda dari kartu "Pengeluaran" (tab Ringkasan) yang cuma
/// total P&L (subset netProfitExpenseTypes) — tab ini breakdown SEMUA
/// jenis pengeluaran yang tercatat.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final range = DateTimeRange(
      start: DateTime(2026, 7, 1), end: DateTime(2026, 7, 31, 23, 59, 59));

  testWidgets(
      'PengeluaranTab: total + rincian per jenis (SEMUA jenis, bukan cuma '
      'subset P&L) tampil dgn nominal benar', (tester) async {
    await db.addExpense(
        type: 'daily_expense',
        amount: 15000,
        createdAt: DateTime(2026, 7, 5));
    await db.addExpense(
        type: 'owner_withdrawal',
        amount: 100000,
        createdAt: DateTime(2026, 7, 10));

    await pumpWithFakeApp(tester, db: db, child: PengeluaranTab(range: range));
    await tester.pumpAndSettle();

    expect(find.text('Total Pengeluaran'), findsOneWidget);
    expect(find.text(formatRupiah(115000)), findsOneWidget,
        reason: 'total = 15.000 (operasional) + 100.000 (ambil pribadi)');
    expect(find.text('Operasional'), findsOneWidget);
    expect(find.text('Ambil Pribadi (Owner)'), findsOneWidget);
    expect(find.text(formatRupiah(15000)), findsOneWidget);
    expect(find.text(formatRupiah(100000)), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('PengeluaranTab: rentang kosong tampilkan pesan, bukan crash',
      (tester) async {
    await pumpWithFakeApp(tester, db: db, child: PengeluaranTab(range: range));
    await tester.pumpAndSettle();

    expect(find.textContaining('Belum ada pengeluaran'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('LaporanScreen: tab "Pengeluaran" ada di TabBar (index ke-7, '
      'paling akhir setelah Stok)', (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const LaporanScreen());
    await tester.pumpAndSettle();

    // Scope ke widget Tab — tab Ringkasan (yg aktif duluan) juga py kartu
    // KPI berlabel "Pengeluaran", jadi find.text('Pengeluaran') polos akan
    // menangkap 2 widget kalau tidak di-scope ke Tab saja.
    final pengeluaranTabFinder = find.descendant(
        of: find.byType(Tab), matching: find.text('Pengeluaran'));
    expect(pengeluaranTabFinder, findsOneWidget);

    // TabBar isScrollable:true + 7 tab — tab terakhir ("Pengeluaran") bisa
    // di luar viewport horizontal awal, WAJIB di-scroll dulu sebelum tap
    // (tester.tap di posisi off-screen tidak nge-hit apa pun).
    await tester.ensureVisible(pengeluaranTabFinder);
    await tester.pumpAndSettle();

    // Tap tab Pengeluaran — screen harus pindah tanpa error/crash.
    await tester.tap(pengeluaranTabFinder);
    await tester.pumpAndSettle();
    expect(find.textContaining('Belum ada pengeluaran'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
