import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/widgets/tx_history_sheet.dart';

import 'helpers/pump_app.dart';

/// Salah satu variasi skenario bug dilaporkan user: cari SATU PELANGGAN
/// tanpa filter tanggal ("dari awal" / lihat keseluruhan), lalu persempit ke
/// BULAN TERTENTU — bulan itu tidak muncul sama sekali walau transaksinya
/// ada.
///
/// Skenario: pelanggan "Budi" punya SATU transaksi di Januari 2024. Toko
/// ini juga punya >1000 transaksi pelanggan LAIN yang lebih baru (2025-2026).
///
/// CATATAN HASIL INVESTIGASI: skenario PERSIS ini (transaksi lain tersebar
/// LUAS di banyak bulan berbeda) ternyata SUDAH benar bahkan SEBELUM fix —
/// begitu filter tanggal dipersempit, query SQL baru (WHERE tanggal sempit)
/// otomatis terbebas dari limit krn hanya menyisakan sedikit baris. Akar
/// masalah SEBENARNYA baru ketemu di variasi lain (lihat
/// `test/tx_history_busy_month_search_limit_test.dart`): kalau BULAN yang
/// dipilih itu SENDIRI sudah punya >1000 transaksi dari pelanggan lain,
/// transaksi target tetap tertimbun WALAU sudah difilter tanggal — krn
/// filter nama pelanggan lama diterapkan CLIENT-SIDE, SETELAH limit SQL.
/// Test ini ditinggal sebagai regresi tambahan (fix skrg bikin search jadi
/// bagian SQL WHERE, jadi burial ini pun sekarang tidak terjadi sama sekali
/// di KEDUA langkah, bukan cuma langkah 2).
///
/// Langkah persis meniru user: (1) ketik "Budi" di search box, TANPA pilih
/// tanggal dulu, (2) baru buka filter tanggal & pilih rentang Januari 2024.
Future<void> _insertTx(
  AppDatabase db, {
  required String id,
  required String localId,
  required DateTime createdAt,
  String? customerId,
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
        customerId: Value(customerId),
        customerName: Value(customerName),
      ));
}

void main() {
  testWidgets(
      'cari nama pelanggan dulu (tanpa tanggal) lalu persempit ke bulan '
      'lama -> transaksi bulan itu tetap harus muncul', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());

    // Transaksi target: Budi, Januari 2024 — jauh di masa lalu.
    final target = DateTime(2024, 1, 15, 10, 30);
    await _insertTx(db,
        id: 'tx-budi',
        localId: 'K1-BUDI',
        createdAt: target,
        customerName: 'Budi');

    // >1000 transaksi pelanggan lain, semua LEBIH BARU dari target, supaya
    // saat query TANPA filter tanggal (ORDER BY created_at DESC LIMIT 1000)
    // transaksi Budi tertimbun di luar limit.
    final base = DateTime(2025, 6, 1);
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
            createdAt: Value(base.add(Duration(minutes: i))),
            customerName: const Value('Umum'),
          ),
      ]);
    });

    await pumpWithFakeApp(tester, db: db, child: const TxHistorySheet());

    // Langkah 1: ketik nama pelanggan, TANPA filter tanggal dulu.
    await tester.enterText(
        find.widgetWithText(TextField, 'Cari pelanggan atau no. transaksi…'),
        'Budi');
    await tester.pumpAndSettle();

    // Search sekarang bagian SQL WHERE (fix) — tidak lagi tertimbun limit
    // sama sekali, bahkan tanpa filter tanggal.
    expect(find.text('K1-BUDI'), findsOneWidget,
        reason: 'search nama pelanggan sekarang difilter di SQL, jadi tidak '
            'tertimbun limit walau tanpa filter tanggal');

    // Langkah 2: buka filter tanggal, pilih rentang Januari 2024 (lewat
    // mode input teks tanggal, bukan tap kalender — lebih stabil di test).
    await tester.ensureVisible(find.text('Semua Tanggal'));
    await tester.tap(find.text('Semua Tanggal'));
    await tester.pumpAndSettle();

    // Switch ke mode input teks (ikon edit) supaya bisa ketik tanggal
    // langsung alih-alih navigasi kalender.
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

    // Transaksi Budi di Januari 2024 HARUS muncul sekarang — bulan itu
    // sudah dipersempit lewat filter tanggal eksplisit.
    expect(find.text('K1-BUDI'), findsOneWidget,
        reason:
            'transaksi Budi Januari 2024 harus muncul setelah filter tanggal '
            'dipersempit ke bulan itu, walau sempat tertimbun saat search '
            'tanpa filter tanggal');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
