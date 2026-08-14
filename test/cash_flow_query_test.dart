import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Arus kas sungguhan — BEDA dari "Selisih Kas Operasional" di tab Ringkasan
/// (Omzet - Pengeluaran) yang bukan arus kas, karena omzet memuat nota TEMPO
/// yang belum dibayar DAN pelunasan hutang tidak jatuh di tanggal uangnya
/// benar-benar diterima.
///
/// Sumber kas masuk di sini = `transaction_payments` (kapan uang BENAR-BENAR
/// berpindah), bukan `transactions`.
late AppDatabase db;

final _from = DateTime(2026, 3, 1);
final _to = DateTime(2026, 3, 31, 23, 59, 59);

Future<void> _tx(String id, {required int total, required DateTime at,
    String status = 'lunas'}) =>
    db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: 'K1-$id',
          status: status,
          total: total,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(at),
        ));

Future<void> _pay(
  String id, {
  required String txId,
  required int amount,
  required DateTime at,
  String method = 'tunai',
  int changeGiven = 0,
  bool voided = false,
}) =>
    db.into(db.transactionPayments).insert(TransactionPaymentsCompanion.insert(
          id: id,
          transactionId: txId,
          amount: amount,
          method: method,
          paidAt: Value(at),
          changeGiven: Value(changeGiven),
          voided: Value(voided),
        ));

void main() {
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
      'nota TEMPO yang belum dibayar TIDAK dihitung sbg kas masuk '
      '(masalah utama "Selisih Kas Operasional")', () async {
    await _tx('t1', total: 500000, at: DateTime(2026, 3, 2), status: 'tempo');
    // Tidak ada baris pembayaran sama sekali.

    final s = await db.getCashFlowSummary(_from, _to);
    expect(s.cashIn, 0);
    expect(s.nonCashIn, 0);
  });

  test(
      'pelunasan hutang nota LAMA jatuh di tanggal uang diterima, bukan '
      'tanggal notanya dibuat', () async {
    // Nota dibuat Februari (DI LUAR rentang laporan Maret).
    await _tx('t1', total: 100000, at: DateTime(2026, 2, 10), status: 'tempo');
    // Dilunasi Maret — HARUS masuk sbg kas masuk Maret.
    await _pay('p1', txId: 't1', amount: 100000, at: DateTime(2026, 3, 15));

    final s = await db.getCashFlowSummary(_from, _to);
    expect(s.cashIn, 100000,
        reason: 'inilah yang TIDAK bisa dilakukan Omzet - Pengeluaran: '
            'omzet nota ini tercatat Februari, padahal uangnya masuk Maret');
  });

  test('kas masuk NET dari kembalian yang diserahkan', () async {
    await _tx('t1', total: 90000, at: DateTime(2026, 3, 5));
    // Pembeli menyerahkan 100rb, kembalian 10rb -> yang mengendap 90rb.
    await _pay('p1',
        txId: 't1', amount: 100000, at: DateTime(2026, 3, 5), changeGiven: 10000);

    final s = await db.getCashFlowSummary(_from, _to);
    expect(s.cashIn, 90000);
  });

  test('pembayaran DIBATALKAN (voided) tidak dihitung', () async {
    await _tx('t1', total: 50000, at: DateTime(2026, 3, 5));
    await _pay('p1', txId: 't1', amount: 50000, at: DateTime(2026, 3, 5));
    await _pay('p2',
        txId: 't1', amount: 50000, at: DateTime(2026, 3, 6), voided: true);

    final s = await db.getCashFlowSummary(_from, _to);
    expect(s.cashIn, 50000);
  });

  test('refund retur nota lunas (amount NEGATIF) mengurangi kas masuk',
      () async {
    await _tx('t1', total: 50000, at: DateTime(2026, 3, 5));
    await _pay('p1', txId: 't1', amount: 50000, at: DateTime(2026, 3, 5));
    await _pay('p2', txId: 't1', amount: -20000, at: DateTime(2026, 3, 8));

    final s = await db.getCashFlowSummary(_from, _to);
    expect(s.cashIn, 30000);
  });

  test('tunai vs non-tunai dipisah; rincian per metode ikut tersedia',
      () async {
    await _tx('t1', total: 100000, at: DateTime(2026, 3, 5));
    await _pay('p1', txId: 't1', amount: 40000, at: DateTime(2026, 3, 5));
    await _pay('p2',
        txId: 't1', amount: 35000, at: DateTime(2026, 3, 5), method: 'transfer');
    await _pay('p3',
        txId: 't1', amount: 25000, at: DateTime(2026, 3, 5), method: 'qris');

    final s = await db.getCashFlowSummary(_from, _to);
    expect(s.cashIn, 40000);
    expect(s.nonCashIn, 60000, reason: 'transfer 35rb + qris 25rb');
    expect(s.inByMethod['transfer'], 35000);
    expect(s.inByMethod['qris'], 25000);
  });

  test("method 'tempo' bukan uang berpindah -> tidak dihitung", () async {
    await _tx('t1', total: 50000, at: DateTime(2026, 3, 5), status: 'tempo');
    await _pay('p1',
        txId: 't1', amount: 50000, at: DateTime(2026, 3, 5), method: 'tempo');

    final s = await db.getCashFlowSummary(_from, _to);
    expect(s.cashIn, 0);
    expect(s.nonCashIn, 0);
  });

  test('kas keluar dari expenses (SEMUA jenis, bukan subset P&L)', () async {
    await db.addExpense(
        type: 'daily_expense', amount: 20000, note: 'Listrik');
    await db.addExpense(
        type: 'owner_withdrawal', amount: 100000, note: 'Ambil pribadi');

    final s = await db.getCashFlowSummary(
        DateTime.now().subtract(const Duration(days: 1)),
        DateTime.now().add(const Duration(days: 1)));
    expect(s.cashOut, 120000,
        reason: 'tab arus kas = "ke mana uang mengalir", jadi ambil-pribadi '
            'IKUT dihitung (beda dari Laba Bersih)');
    expect(s.outByType['owner_withdrawal'], 100000);
  });

  test('tren harian menggabungkan kas masuk & keluar per tanggal', () async {
    await _tx('t1', total: 50000, at: DateTime(2026, 3, 5));
    await _pay('p1', txId: 't1', amount: 50000, at: DateTime(2026, 3, 5, 9));
    await _pay('p2', txId: 't1', amount: 10000, at: DateTime(2026, 3, 5, 17));
    await _pay('p3', txId: 't1', amount: 30000, at: DateTime(2026, 3, 9));

    final daily = await db.getCashFlowDaily(_from, _to);
    expect(daily.map((e) => e.date), [DateTime(2026, 3, 5), DateTime(2026, 3, 9)]);
    expect(daily.first.cashIn, 60000, reason: '2 pembayaran hari sama digabung');
    expect(daily.last.cashIn, 30000);
  });
}
