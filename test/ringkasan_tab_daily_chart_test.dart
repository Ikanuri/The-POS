import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/laporan/tabs/ringkasan_tab.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): chart "Penjualan Harian" (bar-per-hari)
/// pecah/tumpuk labelnya di rentang panjang (sama akar masalah yg sudah
/// diperbaiki di `StatsTrendChart`, lihat dok di sana) — diganti chart
/// garis yang sama (dipakai ulang, bukan reimplementasi baru), plus label
/// nominal PUNCAK selalu tampil (quick insight tanpa tap/drag).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final range = DateTimeRange(
      start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 31, 23, 59, 59));

  Future<void> seedDay(int day, int total) async {
    final id = 'tx-$day';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: 'K1-$day',
          status: 'lunas',
          total: total,
          paid: total,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(DateTime(2026, 8, day)),
        ));
    await db.rebuildSummariesForTxIds({id});
  }

  testWidgets(
      'Penjualan Harian render sbg LineChart (bukan lagi bar-per-hari), '
      'nominal puncak tampil permanen', (tester) async {
    for (var d = 1; d <= 31; d++) {
      await seedDay(d, d == 16 ? 999000 : 10000);
    }
    await pumpWithFakeApp(tester, db: db, child: RingkasanTab(range: range));
    await tester.pumpAndSettle();

    expect(find.text('Penjualan Harian'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget,
        reason: 'chart bar-per-hari lama diganti LineChart (StatsTrendChart)');

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final lines = chart.data.extraLinesData.horizontalLines;
    expect(lines, hasLength(1));
    expect(lines.single.y, 999000,
        reason: 'garis puncak harus di nilai omzet harian TERTINGGI (16/8)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
