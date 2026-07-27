import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/laporan/tabs/ringkasan_tab.dart';

import 'helpers/pump_app.dart';

/// User: "di tab Ringkasan agak ada renggang, mungkin bug". Akar: `Card`
/// bawaan Material 3 punya margin default `EdgeInsets.all(4)` — dipasang
/// berulang di 4 baris KPI (_KpiRow) YANG SUDAH punya jarak eksplisit
/// `SizedBox(height: 12)` antar baris, jadi jarak sungguhannya jadi 12+4+4=20,
/// tidak konsisten dgn jarak yg didesain. Fix: `margin: EdgeInsets.zero` di
/// Card KPI, biar HANYA SizedBox eksplisit yang mengatur jarak.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final range = DateTimeRange(
      start: DateTime(2026, 7, 1), end: DateTime(2026, 7, 31, 23, 59, 59));

  testWidgets('kartu KPI (Omzet/Transaksi/dst) tidak punya margin bawaan',
      (tester) async {
    await pumpWithFakeApp(tester, db: db, child: RingkasanTab(range: range));
    await tester.pumpAndSettle();

    final cards = tester.widgetList<Card>(find.byType(Card));
    expect(cards, isNotEmpty);
    for (final card in cards.take(4)) {
      expect(card.margin, EdgeInsets.zero,
          reason: 'kartu KPI tidak boleh punya margin bawaan Card default '
              '(4px) — jarak antar baris HARUS murni dari SizedBox eksplisit');
    }

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
