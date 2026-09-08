import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 15 — Tutup Kasir: rekap kas hari ini + simpan satu entri per hari.
///
/// `getTodayCashRecap` basisnya `transaction_payments` (kapan & berapa uang
/// SUNGGUHAN diterima), BUKAN `transactions.created_at`/`paid` — lihat dok
/// di `app_database.dart` & bukti bug di `tutup_kasir_recap_paid_at_test.dart`.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> addTx({
    required String id,
    required int total,
    required int paid,
    required String method,
    required String status,
    required DateTime at,
  }) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: id,
            localId: id,
            status: status,
            total: total,
            paid: paid,
            changeAmount: 0,
            paymentMethod: method,
            createdAt: Value(at),
          ));

  Future<void> addPayment({
    required String id,
    required String txId,
    required int amount,
    required String method,
    required DateTime at,
  }) =>
      db.into(db.transactionPayments).insert(TransactionPaymentsCompanion.insert(
            id: id,
            transactionId: txId,
            amount: amount,
            method: method,
            paidAt: Value(at),
          ));

  test('getTodayCashRecap: tunai vs non-tunai vs count; void & tempo diabaikan',
      () async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    await addTx(
        id: 't1', total: 50000, paid: 50000, method: 'tunai', status: 'lunas', at: now);
    await addPayment(id: 'p1', txId: 't1', amount: 50000, method: 'tunai', at: now);
    await addTx(
        id: 't2', total: 30000, paid: 30000, method: 'qris', status: 'lunas', at: now);
    await addPayment(id: 'p2', txId: 't2', amount: 30000, method: 'qris', at: now);
    await addTx(
        id: 't3', total: 20000, paid: 20000, method: 'tunai', status: 'lunas', at: now);
    await addPayment(id: 'p3', txId: 't3', amount: 20000, method: 'tunai', at: now);
    // void → diabaikan walau punya baris pembayaran.
    await addTx(
        id: 't4', total: 99000, paid: 99000, method: 'tunai', status: 'void', at: now);
    await addPayment(id: 'p4', txId: 't4', amount: 99000, method: 'tunai', at: now);
    // tempo (belum bayar sama sekali) → tidak ada baris transaction_payments.
    await addTx(
        id: 't5', total: 40000, paid: 0, method: 'tempo', status: 'tempo', at: now);

    final r = await db.getTodayCashRecap(from, now);
    expect(r.cash, 70000); // 50k + 20k
    expect(r.nonCash, 30000); // qris
    expect(r.txCount, 3, reason: 't1,t2,t3 (void t4 & tempo t5 tanpa '
        'pembayaran tidak dihitung)');
  });

  test('saveCashClosing upsert: id deterministik → 1 baris per hari, ter-update',
      () async {
    CashClosingsCompanion entry(int physical) => CashClosingsCompanion(
          id: const Value('2026-07-10_K1'),
          date: const Value('2026-07-10'),
          deviceCode: const Value('K1'),
          systemCash: const Value(70000),
          physicalCash: Value(physical),
          difference: Value(physical - 70000),
        );

    await db.saveCashClosing(entry(68000)); // kurang 2000
    await db.saveCashClosing(entry(70000)); // koreksi jadi pas

    final all = await db.watchCashClosings().first;
    expect(all.length, 1, reason: 'satu entri per (tanggal, device)');
    expect(all.first.physicalCash, 70000);
    expect(all.first.difference, 0);
  });
}
