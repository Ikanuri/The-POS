import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laporan/laporan_screen.dart';
import 'package:the_pos/features/laporan/tabs/arus_kas_tab.dart';

import 'helpers/pump_app.dart';

/// Tab Arus Kas — uang yang BENAR-BENAR berpindah, beda dari kartu "Selisih
/// Kas Operasional" di Ringkasan (Omzet - Pengeluaran).
final _range = DateTimeRange(
  start: DateTime(2026, 3, 1),
  end: DateTime(2026, 3, 31, 23, 59, 59),
);

Future<AppDatabase> _seed() async {
  final db = AppDatabase(NativeDatabase.memory());
  // Nota TEMPO dari Februari (di luar rentang) yang baru dilunasi Maret —
  // skenario yang TIDAK bisa ditangkap Omzet - Pengeluaran.
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 't1',
        localId: 'K1-0001',
        status: 'lunas',
        total: 100000,
        paid: 100000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt: Value(DateTime(2026, 2, 10)),
      ));
  await db.into(db.transactionPayments).insert(
      TransactionPaymentsCompanion.insert(
        id: 'p1',
        transactionId: 't1',
        amount: 100000,
        method: 'tunai',
        paidAt: Value(DateTime(2026, 3, 15)),
      ));
  return db;
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets('menampilkan kas masuk dari pelunasan nota lama di tanggal '
      'uang diterima', (tester) async {
    final db = await _seed();
    await pumpWithFakeApp(tester, db: db, child: ArusKasTab(range: _range));
    await tester.pumpAndSettle();

    expect(find.text('Kas masuk'), findsOneWidget);
    expect(find.text('Arus kas bersih'), findsOneWidget);
    expect(find.text(formatRupiah(100000)), findsWidgets,
        reason: 'nota dibuat Februari tapi dilunasi Maret — harus muncul '
            'sbg kas masuk Maret');

    await _drain(tester);
    await db.close();
  });

  testWidgets('nota tempo yang BELUM dibayar tidak muncul sbg kas masuk',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 't9',
          localId: 'K1-0009',
          status: 'tempo',
          total: 500000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tempo',
          createdAt: Value(DateTime(2026, 3, 2)),
        ));

    await pumpWithFakeApp(tester, db: db, child: ArusKasTab(range: _range));
    await tester.pumpAndSettle();

    expect(find.text(formatRupiah(500000)), findsNothing,
        reason: 'nota tempo belum menghasilkan uang masuk sama sekali');
    expect(find.text(formatRupiah(0)), findsWidgets);

    await _drain(tester);
    await db.close();
  });

  testWidgets('tab "Arus Kas" terdaftar di LaporanScreen', (tester) async {
    final db = await _seed();
    await pumpWithFakeApp(tester, db: db, child: const LaporanScreen());
    await tester.pumpAndSettle();

    expect(find.text('Arus Kas'), findsOneWidget);

    await _drain(tester);
    await db.close();
  });
}
