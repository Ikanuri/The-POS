import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/widgets/tx_history_sheet.dart';

import 'helpers/pump_app.dart';

/// Log void (permintaan user) — dialog `showVoidTransactionDialog` (dipakai
/// bersama Riwayat Transaksi & struk) kini punya field "Alasan (opsional)".
/// Test ini membuktikan wiring UI -> DB: alasan yang diketik benar-benar
/// diteruskan ke `voidTransaction(reason: ...)`, TIDAK cuma tampil di dialog
/// tanpa efek.
void main() {
  testWidgets(
      'isi alasan di dialog Batalkan -> tersimpan sbg voidReason di DB',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 50000,
          paid: 50000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));

    await pumpWithFakeApp(tester, db: db, child: const TxHistorySheet());

    // Expand baris supaya tombol Batalkan muncul.
    await tester.tap(find.text('K1-1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Batalkan'));
    await tester.pumpAndSettle();

    expect(find.text('Alasan (opsional)'), findsOneWidget,
        reason: 'dialog void harus punya field alasan opsional');

    await tester.enterText(
        find.widgetWithText(TextField, 'Alasan (opsional)'),
        'Salah input harga jual');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Batalkan Transaksi'));
    await tester.pumpAndSettle();

    final row = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(row.status, 'void');
    expect(row.voidReason, 'Salah input harga jual',
        reason: 'alasan yang diketik di dialog harus diteruskan ke '
            'voidTransaction(reason: ...), bukan cuma tampil di UI tanpa '
            'efek');
    expect(row.voidedBy, 'K1');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'Batalkan TANPA mengisi alasan -> voidReason null (opsional benar2 '
      'opsional)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 50000,
          paid: 50000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));

    await pumpWithFakeApp(tester, db: db, child: const TxHistorySheet());

    await tester.tap(find.text('K1-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batalkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batalkan Transaksi'));
    await tester.pumpAndSettle();

    final row = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(row.status, 'void');
    expect(row.voidReason, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
