import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug: `getTodayCashRecap` sebelum fix pakai `transactions.created_at`
/// (tanggal NOTA DIBUAT) & `SUM(transactions.paid)` (kumulatif nota) —
/// nota yg dibuat kemarin tapi DILUNASI hari ini (mis. pre-order DP 0,
/// dilunasi saat pengambilan) TIDAK PERNAH muncul di rekonsiliasi kas hari
/// pelunasan. Fix: basis `transaction_payments.paid_at`/`amount`.
late AppDatabase db;

Future<void> _tx(String id,
        {required int total, required DateTime createdAt,
        String status = 'lunas', int paid = 0, String method = 'tunai'}) =>
    db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: 'K1-$id',
          status: status,
          total: total,
          paid: paid,
          changeAmount: 0,
          paymentMethod: method,
          createdAt: Value(createdAt),
        ));

Future<void> _pay(String id,
        {required String txId,
        required int amount,
        required DateTime at,
        String method = 'tunai',
        bool voided = false,
        int changeGiven = 0}) =>
    db.into(db.transactionPayments).insert(TransactionPaymentsCompanion.insert(
          id: id,
          transactionId: txId,
          amount: amount,
          method: method,
          paidAt: Value(at),
          voided: Value(voided),
          changeGiven: Value(changeGiven),
        ));

void main() {
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
      'pelunasan HARI INI dari nota yg DIBUAT kemarin MUNCUL di rekap kas '
      'hari ini (bug asli: hilang total krn filter created_at)', () async {
    final kemarin = DateTime(2026, 9, 7, 10);
    final hariIni = DateTime(2026, 9, 8);
    final hariIniAkhir = DateTime(2026, 9, 8, 23, 59, 59);

    // Nota DIBUAT kemarin, status tempo (belum dibayar sama sekali).
    await _tx('t1',
        total: 150000, createdAt: kemarin, status: 'tempo', paid: 0);
    // Dilunasi HARI INI.
    await _pay('p1', txId: 't1', amount: 150000, at: DateTime(2026, 9, 8, 14));

    final recap = await db.getTodayCashRecap(hariIni, hariIniAkhir);

    expect(recap.cash, 150000,
        reason: 'uang yg BENAR-BENAR diterima hari ini harus tercatat, '
            'walau nota dibuat kemarin');
    expect(recap.txCount, 1);
  });

  test('metode campuran dalam 1 nota dipisah per baris pembayaran, bukan '
      'snapshot payment_method nota', () async {
    final hariIni = DateTime(2026, 9, 8);
    final hariIniAkhir = DateTime(2026, 9, 8, 23, 59, 59);

    await _tx('t1',
        total: 100000, createdAt: hariIni, paid: 100000, method: 'tunai');
    await _pay('p1', txId: 't1', amount: 40000, at: DateTime(2026, 9, 8, 9));
    await _pay('p2',
        txId: 't1', amount: 60000, at: DateTime(2026, 9, 8, 9), method: 'transfer');

    final recap = await db.getTodayCashRecap(hariIni, hariIniAkhir);
    expect(recap.cash, 40000);
    expect(recap.nonCash, 60000);
    expect(recap.txCount, 1, reason: '1 nota, walau 2 baris pembayaran');
  });

  test('pembayaran voided tidak dihitung', () async {
    final hariIni = DateTime(2026, 9, 8);
    final hariIniAkhir = DateTime(2026, 9, 8, 23, 59, 59);
    await _tx('t1', total: 50000, createdAt: hariIni, paid: 50000);
    await _pay('p1', txId: 't1', amount: 50000, at: DateTime(2026, 9, 8, 9));
    await _pay('p2',
        txId: 't1',
        amount: 50000,
        at: DateTime(2026, 9, 8, 10),
        voided: true);

    final recap = await db.getTodayCashRecap(hariIni, hariIniAkhir);
    expect(recap.cash, 50000);
  });

  test('nota status void SAAT INI dikecualikan walau ada baris pembayaran',
      () async {
    final hariIni = DateTime(2026, 9, 8);
    final hariIniAkhir = DateTime(2026, 9, 8, 23, 59, 59);
    await _tx('t1',
        total: 50000, createdAt: hariIni, paid: 50000, status: 'void');
    await _pay('p1', txId: 't1', amount: 50000, at: DateTime(2026, 9, 8, 9));

    final recap = await db.getTodayCashRecap(hariIni, hariIniAkhir);
    expect(recap.cash, 0);
    expect(recap.txCount, 0);
  });

  test("method 'tempo' tidak pernah muncul sbg baris pembayaran uang -> "
      "tidak dihitung meski ada", () async {
    final hariIni = DateTime(2026, 9, 8);
    final hariIniAkhir = DateTime(2026, 9, 8, 23, 59, 59);
    await _tx('t1', total: 50000, createdAt: hariIni, status: 'tempo');
    await _pay('p1',
        txId: 't1', amount: 50000, at: DateTime(2026, 9, 8, 9), method: 'tempo');

    final recap = await db.getTodayCashRecap(hariIni, hariIniAkhir);
    expect(recap.cash, 0);
    expect(recap.nonCash, 0);
  });

  test(
      'bayar tunai dgn kembalian -> cash recap NET (dikurangi kembalian), '
      'bukan gross tendered', () async {
    final hariIni = DateTime(2026, 9, 8);
    final hariIniAkhir = DateTime(2026, 9, 8, 23, 59, 59);
    // Belanja 30rb, bayar tunai 50rb -> kembalian 20rb. Uang yg BENAR-BENAR
    // tertinggal di laci cuma 30rb, bukan 50rb (gross tendered).
    await _tx('t1', total: 30000, createdAt: hariIni, paid: 30000);
    await _pay('p1',
        txId: 't1',
        amount: 50000,
        at: DateTime(2026, 9, 8, 9),
        changeGiven: 20000);

    final recap = await db.getTodayCashRecap(hariIni, hariIniAkhir);
    expect(recap.cash, 30000,
        reason: 'kas tunai harus net dari kembalian, bukan gross 50rb');
  });

  test(
      'bayar via transfer dgn kembalian TUNAI -> non-tunai TETAP FULL (uang '
      'transfer utuh), tunai laci BERKURANG (bahkan bisa NEGATIF) krn '
      'kembalian fisik SELALU tunai apa pun metode aslinya', () async {
    final hariIni = DateTime(2026, 9, 8);
    final hariIniAkhir = DateTime(2026, 9, 8, 23, 59, 59);
    // Belanja 80rb, bayar transfer 100rb -> kembalian 20rb diserahkan TUNAI
    // (kasir tidak bisa "transfer balik" 20rb). Ini satu-satunya
    // pembayaran hari ini -> tunai laci net NEGATIF (uang keluar dari
    // modal, belum ada uang tunai masuk hari ini sama sekali).
    await _tx('t1', total: 80000, createdAt: hariIni, paid: 80000);
    await _pay('p1',
        txId: 't1',
        amount: 100000,
        at: DateTime(2026, 9, 8, 9),
        method: 'transfer',
        changeGiven: 20000);

    final recap = await db.getTodayCashRecap(hariIni, hariIniAkhir);
    expect(recap.nonCash, 100000,
        reason: 'uang transfer masuk utuh ke rekening, tidak berkurang');
    expect(recap.cash, -20000,
        reason: 'tunai laci berkurang 20rb krn kembalian fisik tunai — '
            'JANGAN di-floor ke 0, ini valid utk rekonsiliasi kas fisik');
  });

  test(
      'marker retur nota BELUM-LUNAS (method retur/edit, amount 0) dgn '
      'change_given metadata TIDAK ikut dipotong dari cash — bukan uang '
      'yg sungguhan keluar hari ini', () async {
    final hariIni = DateTime(2026, 9, 8);
    final hariIniAkhir = DateTime(2026, 9, 8, 23, 59, 59);
    await _tx('t1', total: 50000, createdAt: hariIni, paid: 20000);
    await _pay('p1', txId: 't1', amount: 20000, at: DateTime(2026, 9, 8, 9));
    // Marker audit retur nota belum-lunas: amount 0, changeGiven metadata
    // (BUKAN uang fisik yg keluar hari ini).
    await _pay('p2',
        txId: 't1',
        amount: 0,
        at: DateTime(2026, 9, 8, 10),
        method: 'retur',
        changeGiven: 15000);

    final recap = await db.getTodayCashRecap(hariIni, hariIniAkhir);
    expect(recap.cash, 20000,
        reason: 'changeGiven marker retur/edit murni audit, tidak boleh '
            'memotong kas fisik hari ini');
  });
}
