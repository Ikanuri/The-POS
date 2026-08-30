import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/widgets/tx_history_sheet.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): Riwayat Transaksi sekarang bisa difilter by
/// kategori metode pembayaran ('tunai'/'bank'/'qris'/'ewallet'/'tempo'),
/// bukan cuma status lunas/hutang seperti sebelumnya.
Future<void> _insertTx(AppDatabase db,
    {required String id,
    required String localId,
    required String method}) async {
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id,
        localId: localId,
        status: 'lunas',
        total: 10000,
        paid: 10000,
        changeAmount: 0,
        paymentMethod: method,
      ));
}

void main() {
  testWidgets(
      'filter "QRIS" -> hanya nota metode qris yang tampil, lainnya '
      'tersembunyi', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertTx(db, id: 'tx1', localId: 'K1-1', method: 'tunai');
    await _insertTx(db, id: 'tx2', localId: 'K1-2', method: 'qris');
    await _insertTx(db, id: 'tx3', localId: 'K1-3', method: 'bank');

    await pumpWithFakeApp(tester, db: db, child: const TxHistorySheet());

    expect(find.text('K1-1'), findsOneWidget);
    expect(find.text('K1-2'), findsOneWidget);
    expect(find.text('K1-3'), findsOneWidget);

    await tester.ensureVisible(find.text('Semua Metode'));
    await tester.tap(find.text('Semua Metode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QRIS'));
    await tester.pumpAndSettle();

    expect(find.text('K1-1'), findsNothing);
    expect(find.text('K1-2'), findsOneWidget);
    expect(find.text('K1-3'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'pilih ulang "Semua Metode" di picker -> filter dilepas, semua nota '
      'tampil lagi', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertTx(db, id: 'tx1', localId: 'K1-1', method: 'tunai');
    await _insertTx(db, id: 'tx2', localId: 'K1-2', method: 'qris');

    await pumpWithFakeApp(tester, db: db, child: const TxHistorySheet());

    await tester.ensureVisible(find.text('Semua Metode'));
    await tester.tap(find.text('Semua Metode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QRIS'));
    await tester.pumpAndSettle();
    expect(find.text('K1-1'), findsNothing,
        reason: 'filter QRIS aktif -> nota tunai tersembunyi');

    // Chip sekarang berlabel "QRIS" (bukan lagi "Semua Metode") — buka
    // picker lagi lewat label itu, pilih "Semua Metode" utk melepas filter.
    await tester.tap(find.text('QRIS'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Semua Metode'));
    await tester.tap(find.text('Semua Metode'));
    await tester.pumpAndSettle();

    expect(find.text('K1-1'), findsOneWidget);
    expect(find.text('K1-2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
