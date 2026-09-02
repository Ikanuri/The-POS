import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/widgets/tx_history_sheet.dart';

import 'helpers/pump_app.dart';

/// Variasi lain dari hipotesis limit 1000: apakah transaksi seorang
/// pelanggan bisa tertimbun bahkan SETELAH filter tanggal dipersempit ke
/// satu bulan, kalau bulan itu SENDIRI sudah punya >1000 transaksi dari
/// pelanggan lain (bukan skenario realistis toko kecil, tapi dicek utk
/// menutup kemungkinan sebelum menyimpulkan tidak bisa direproduksi).
Future<void> _insertTx(
  AppDatabase db, {
  required String id,
  required String localId,
  required DateTime createdAt,
  String? customerName,
}) async {
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id,
        localId: localId,
        status: 'lunas',
        total: 10000,
        paid: 10000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt: Value(createdAt),
        customerName: Value(customerName),
      ));
}

void main() {
  testWidgets(
      'bulan yang dipilih punya >1000 transaksi lain -> transaksi '
      'pelanggan target di awal bulan tetap harus muncul', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());

    // Transaksi target: Budi, paling AWAL di bulan Januari 2024 (posisi
    // "tertua" kalau diurutkan DESC di dalam bulan itu).
    final target = DateTime(2024, 1, 1, 8, 0);
    await _insertTx(db,
        id: 'tx-budi',
        localId: 'K1-BUDI',
        createdAt: target,
        customerName: 'Budi');

    // >1000 transaksi lain DI DALAM BULAN YANG SAMA, semua lebih baru dari
    // transaksi Budi (tanggal 2-31 Januari 2024).
    final base = DateTime(2024, 1, 2, 0, 0);
    await db.batch((batch) {
      batch.insertAll(db.transactions, [
        for (var i = 0; i < 1200; i++)
          TransactionsCompanion.insert(
            id: 'tx-other-$i',
            localId: 'K1-O$i',
            status: 'lunas',
            total: 5000,
            paid: 5000,
            changeAmount: 0,
            paymentMethod: 'tunai',
            createdAt: Value(base.add(Duration(minutes: i * 30))),
            customerName: const Value('Umum'),
          ),
      ]);
    });

    await pumpWithFakeApp(tester, db: db, child: const TxHistorySheet());

    await tester.enterText(
        find.widgetWithText(TextField, 'Cari pelanggan atau no. transaksi…'),
        'Budi');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Semua Tanggal'));
    await tester.tap(find.text('Semua Tanggal'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Start Date', skipOffstage: false),
        '1/1/2024');
    await tester.enterText(
        find.widgetWithText(TextField, 'End Date', skipOffstage: false),
        '1/31/2024');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('K1-BUDI'), findsOneWidget,
        reason: 'transaksi Budi harus tetap muncul walau bulan itu sendiri '
            'punya >1000 transaksi pelanggan lain yang lebih baru');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
