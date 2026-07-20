import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 49d — query agregat baru untuk tab "Laporan Pengeluaran" (rincian +
/// grafik): breakdown per JENIS (SEMUA jenis, beda dari
/// [AppDatabase.netProfitExpenseTypes] yang cuma subset utk P&L) & total
/// per HARI. DB-tier murni (bukan widget) — sesuai jenjang test CLAUDE.md
/// utk logic/DB.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final from = DateTime(2026, 7, 1);
  final to = DateTime(2026, 7, 31, 23, 59, 59);

  test('getExpenseBreakdownByType — jumlah per jenis, SEMUA 4 jenis ikut '
      '(bukan cuma subset netProfitExpenseTypes)', () async {
    await db.addExpense(
        type: 'daily_expense',
        amount: 15000,
        createdAt: DateTime(2026, 7, 5));
    await db.addExpense(
        type: 'daily_expense',
        amount: 5000,
        createdAt: DateTime(2026, 7, 6));
    await db.addExpense(
        type: 'owner_withdrawal',
        amount: 100000,
        createdAt: DateTime(2026, 7, 10));
    await db.addExpense(
        type: 'supplier_payment',
        amount: 50000,
        createdAt: DateTime(2026, 7, 12));
    await db.addExpense(
        type: 'change_given',
        amount: 2000,
        createdAt: DateTime(2026, 7, 15));
    // Di luar rentang — tidak boleh ikut terhitung.
    await db.addExpense(
        type: 'daily_expense',
        amount: 999999,
        createdAt: DateTime(2026, 8, 1));

    final result = await db.getExpenseBreakdownByType(from, to);

    expect(result['daily_expense'], 20000,
        reason: '15.000 + 5.000 digabung per jenis yang sama');
    expect(result['owner_withdrawal'], 100000);
    expect(result['supplier_payment'], 50000);
    expect(result['change_given'], 2000);
    expect(result.values.fold<int>(0, (s, v) => s + v), 172000,
        reason: 'total gabungan tidak boleh ikut angka di luar rentang');
  });

  test(
      'getExpenseDailyTotals — jumlah SEMUA jenis digabung per hari, '
      'dikelompokkan benar walau beda jenis', () async {
    await db.addExpense(
        type: 'daily_expense',
        amount: 10000,
        createdAt: DateTime(2026, 7, 5, 9, 0));
    await db.addExpense(
        type: 'owner_withdrawal',
        amount: 20000,
        createdAt: DateTime(2026, 7, 5, 15, 0));
    await db.addExpense(
        type: 'supplier_payment',
        amount: 7000,
        createdAt: DateTime(2026, 7, 6, 8, 0));

    final result = await db.getExpenseDailyTotals(from, to);

    expect(result[DateTime(2026, 7, 5)], 30000,
        reason: '2 pengeluaran beda jenis di tanggal sama digabung');
    expect(result[DateTime(2026, 7, 6)], 7000);
    expect(result.length, 2, reason: 'cuma 2 tanggal yang punya data');
  });
}
