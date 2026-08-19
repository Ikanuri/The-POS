import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/widgets/tx_history_sheet.dart';

import 'helpers/pump_app.dart';

/// Bug dilaporkan user (tangkapan layar): nota `A1-20260809-0030` (Buk
/// Artia) tampil "Sisa -Rp 300" di Riwayat Transaksi, TAPI struk-nya sendiri
/// bilang "Sisa Tagihan Rp 6.600" — dua angka yang seharusnya SAMA berbeda
/// total 6.900 (persis sebesar kembalian yang dipakai ulang sbg pembayaran).
///
/// Skenario nyata: bayar Rp 250.000 (kembalian Rp 6.900 DICENTANG, artinya
/// uang itu TIDAK diserahkan ke pembeli — dipakai ulang), lalu tercatat lagi
/// SEBAGAI pembayaran baru Rp 6.900. Raw `paid` jadi 250.000+6.900=256.900,
/// padahal net yang BENAR-BENAR masuk cuma 250.000 (yang 6.900 kedua itu
/// adalah uang yang SAMA, bukan uang baru). `total - paid` mentah
/// (256.600-256.900=-300) SALAH; net yang benar (dikurangi `change_given`)
/// = 256.600-256.900+6.900 = 6.600, cocok dgn struk.
///
/// formatRupiah() memakai non-breaking space (U+00A0), bukan spasi biasa.
const _nbsp = ' ';

Future<void> _insertTx(AppDatabase db,
    {required String id,
    required String localId,
    required String status,
    required int total,
    required int paid}) =>
    db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: localId,
          status: status,
          total: total,
          paid: paid,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));

Future<void> _insertPayment(AppDatabase db,
    {required String id,
    required String txId,
    required int amount,
    int changeGiven = 0}) =>
    db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
          id: id,
          transactionId: txId,
          amount: amount,
          method: 'tunai',
          changeGiven: Value(changeGiven),
        ));

void main() {
  group('AppDatabase.getNetSisaForTxIds (DB murni)', () {
    test(
        'kembalian dipakai ulang sbg pembayaran baru -> sisa NET benar, '
        'bukan raw total-paid yang bisa negatif', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _insertTx(db,
          id: 'tx1',
          localId: 'A1-1',
          status: 'kurang_bayar',
          total: 256600,
          paid: 256900);
      await _insertPayment(db,
          id: 'pay1', txId: 'tx1', amount: 250000, changeGiven: 6900);
      await _insertPayment(db, id: 'pay2', txId: 'tx1', amount: 6900);

      final sisaMap = await db.getNetSisaForTxIds(['tx1']);

      expect(sisaMap['tx1'], 6600,
          reason: 'net = 256600-256900+6900 = 6600, sama dgn Sisa Tagihan '
              'di struk — raw (total-paid) akan salah jadi -300');
    });

    test('tanpa change_given (kasus normal) -> sisa NET sama dgn raw',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _insertTx(db,
          id: 'tx1',
          localId: 'A1-1',
          status: 'kurang_bayar',
          total: 50000,
          paid: 30000);

      final sisaMap = await db.getNetSisaForTxIds(['tx1']);
      expect(sisaMap['tx1'], 20000);
    });

    test('sisa negatif (overpay bersih) di-clamp ke 0, bukan minus', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _insertTx(db,
          id: 'tx1', localId: 'A1-1', status: 'lunas', total: 50000, paid: 60000);

      final sisaMap = await db.getNetSisaForTxIds(['tx1']);
      expect(sisaMap['tx1'], 0);
    });

    test('txIds kosong -> map kosong, tidak query', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect(await db.getNetSisaForTxIds(const []), isEmpty);
    });
  });

  group('Riwayat Transaksi (widget) — Sisa yang ditampilkan sama dgn struk', () {
    testWidgets(
        'baris riwayat menampilkan Sisa NET (Rp 6.600), BUKAN raw negatif '
        '(-Rp 300)', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertTx(db,
          id: 'tx1',
          localId: 'A1-20260809-0030',
          status: 'kurang_bayar',
          total: 256600,
          paid: 256900);
      await _insertPayment(db,
          id: 'pay1', txId: 'tx1', amount: 250000, changeGiven: 6900);
      await _insertPayment(db, id: 'pay2', txId: 'tx1', amount: 6900);

      await pumpWithFakeApp(tester, db: db, child: const TxHistorySheet());
      // Provider async (FutureProvider) — beri kesempatan resolve.
      await tester.pumpAndSettle();

      expect(find.text('Sisa Rp${_nbsp}6.600'), findsOneWidget,
          reason: 'harus sama persis dgn "Sisa Tagihan" di struk untuk nota '
              'yang sama');
      expect(find.textContaining('-Rp'), findsNothing,
          reason: 'sebelum fix, baris ini tampil "Sisa -Rp 300" — raw '
              'total-paid mentah tanpa dikurangi change_given');

      await db.close();
    });

    testWidgets(
        'tombol "Lunasi" membuka sheet bayar dgn jumlah NET (Rp 6.600), bukan '
        'raw yang bisa negatif/salah — bug ini FUNGSIONAL, bukan cuma '
        'tampilan (jumlah ini yang dicatat sbg pembayaran)', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertTx(db,
          id: 'tx1',
          localId: 'A1-20260809-0030',
          status: 'kurang_bayar',
          total: 256600,
          paid: 256900);
      await _insertPayment(db,
          id: 'pay1', txId: 'tx1', amount: 250000, changeGiven: 6900);
      await _insertPayment(db, id: 'pay2', txId: 'tx1', amount: 6900);

      await pumpWithFakeApp(tester, db: db, child: const TxHistorySheet());
      await tester.pumpAndSettle();

      // Ketuk baris untuk expand detail (tombol "Lunasi" ada di situ).
      await tester.tap(find.text('A1-20260809-0030'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lunasi'));
      await tester.pumpAndSettle();

      // Sheet pelunasan menampilkan sisa di header DAN memakai angka yang
      // sama sbg nominal awal ("Dibayar"), jadi Rp 6.600 muncul >1x.
      expect(find.text('Rp${_nbsp}6.600'), findsWidgets,
          reason: 'sheet pelunasan harus pre-fill jumlah NET yang benar '
              '(6.600), bukan raw total-paid (-300) — kalau salah, jumlah '
              'yang benar-benar TERCATAT sbg pembayaran ikut salah');
      expect(find.textContaining('-Rp'), findsNothing,
          reason: 'raw negatif tidak boleh bocor ke sheet bayar');

      await db.close();
    });
  });
}
