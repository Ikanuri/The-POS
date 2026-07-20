import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laporan/tabs/ringkasan_tab.dart';

import 'helpers/pump_app.dart';

/// Permintaan user — kartu KPI baru "Selisih Kas Operasional" = Omzet −
/// Pengeluaran (TANPA kurangi HPP), berbeda dari "Laba Bersih" yang sudah
/// ada (Omzet − HPP − Pengeluaran).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final range = DateTimeRange(
      start: DateTime(2026, 7, 1), end: DateTime(2026, 7, 31, 23, 59, 59));

  Future<void> seed() async {
    // Omzet 100.000 (HPP 60.000 → Laba Kotor 40.000), Pengeluaran 15.000.
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 100000,
          paid: 100000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(DateTime(2026, 7, 15)),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 100000,
        costAtSale: const Value(60000),
        originalPrice: 100000,
        subtotal: 100000));
    await db.rebuildSummariesForTxIds({'tx1'});
    await db.addExpense(
        type: 'daily_expense',
        amount: 15000,
        note: 'Listrik',
        createdAt: DateTime(2026, 7, 15));
  }

  testWidgets(
      'kartu "Selisih Kas Operasional" tampil = Omzet - Pengeluaran, BEDA '
      'dari Laba Bersih (Omzet-HPP-Pengeluaran)', (tester) async {
    await seed();
    await pumpWithFakeApp(tester, db: db, child: RingkasanTab(range: range));
    await tester.pumpAndSettle();

    expect(find.text('Selisih Kas Operasional'), findsOneWidget);
    // Omzet(100.000) - Pengeluaran(15.000) = 85.000.
    expect(find.text(formatRupiah(85000)), findsOneWidget,
        reason: 'Selisih Kas Operasional TIDAK boleh kurangi HPP');
    // Laba Bersih = 40.000 (Laba Kotor) - 15.000 (Pengeluaran) = 25.000 —
    // harus tetap ada & BEDA dari Selisih Kas Operasional.
    expect(find.text(formatRupiah(25000)), findsOneWidget,
        reason: 'Laba Bersih (mengurangi HPP) harus tetap benar & berbeda');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
