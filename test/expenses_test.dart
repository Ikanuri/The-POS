import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/expenses_screen.dart';

import 'helpers/pump_app.dart';

/// Item 9 — pencatatan pengeluaran + total pengurang Laba Bersih.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('getNetProfitExpenseTotal', () {
    test(
        'HANYA daily_expense + change_given yang dihitung; owner_withdrawal '
        '& supplier_payment DIKECUALIKAN', () async {
      final now = DateTime.now();
      await db.addExpense(type: 'daily_expense', amount: 10000, createdAt: now);
      await db.addExpense(type: 'change_given', amount: 2000, createdAt: now);
      await db.addExpense(
          type: 'owner_withdrawal', amount: 500000, createdAt: now);
      await db.addExpense(
          type: 'supplier_payment', amount: 300000, createdAt: now);

      final total = await db.getNetProfitExpenseTotal(
          now.subtract(const Duration(days: 1)),
          now.add(const Duration(days: 1)));
      // 10000 + 2000 = 12000 saja (bukan + 500000 + 300000).
      expect(total, 12000);
    });

    test('menghormati rentang tanggal (di luar rentang tidak dihitung)',
        () async {
      final now = DateTime.now();
      final old = now.subtract(const Duration(days: 40));
      await db.addExpense(type: 'daily_expense', amount: 7000, createdAt: now);
      await db.addExpense(type: 'daily_expense', amount: 9999, createdAt: old);

      final total = await db.getNetProfitExpenseTotal(
          now.subtract(const Duration(days: 7)),
          now.add(const Duration(days: 1)));
      expect(total, 7000); // yang 40 hari lalu tidak masuk
    });

    test('tanpa pengeluaran → 0 (bukan null)', () async {
      final now = DateTime.now();
      final total = await db.getNetProfitExpenseTotal(
          now.subtract(const Duration(days: 1)), now);
      expect(total, 0);
    });
  });

  testWidgets('ExpensesScreen: tambah pengeluaran → muncul di daftar & DB',
      (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const ExpensesScreen());

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Pengeluaran'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '25000');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.expenses).get();
    expect(rows.length, 1);
    expect(rows.first.amount, 25000);
    expect(rows.first.type, 'daily_expense'); // default
    expect(find.text('Operasional'), findsOneWidget);

    // Drain drift StreamProvider disposal timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
