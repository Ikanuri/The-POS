import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 56 — `getDebtBook`/`getUnpaidTxDetails`/`getCustomerOutstandingDebt`/
/// `settleMergedDebt` dulu pakai `total - paid` MENTAH, padahal `paid`
/// SENGAJA boleh melebihi `total` (kembalian dipakai ulang lewat "Tambah
/// Belanjaan", pola sama bug `netRemainingOwed` yang sudah diperbaiki di
/// struk). `getDebtBook` GROUP BY customer + `HAVING SUM(total-paid) > 0` —
/// kalau pelanggan yang sama punya nota lain yang overpay begitu,
/// kontribusinya ke SUM jadi negatif, bisa menutupi nota tempo asli →
/// SELURUH pelanggan hilang dari Buku Hutang walau tiap nota individual
/// masih genuinely berstatus belum lunas.
Future<void> _insertTx(
  AppDatabase db, {
  required String id,
  required String localId,
  required String customerId,
  required String status,
  required int total,
  required int paid,
  required DateTime createdAt,
}) =>
    db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: localId,
          customerId: Value(customerId),
          status: status,
          total: total,
          paid: paid,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(createdAt),
        ));

void main() {
  test(
      'nota tempo TIDAK hilang dari Buku Hutang walau pelanggan yg sama '
      'punya nota LAIN yg overpay (kembalian dipakai ulang) — SUM raw bisa '
      'jadi negatif, SUM net tidak', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'cust-1', name: 'Budi'));

    // tx-A: tempo murni, belum dibayar sama sekali — genuinely owed 20000.
    await _insertTx(db,
        id: 'tx-a',
        localId: 'K1-A',
        customerId: 'cust-1',
        status: 'tempo',
        total: 20000,
        paid: 0,
        createdAt: DateTime(2026, 1, 1));

    // tx-B: awalnya lunas (total 15000, bayar 40000 tunai, kembalian 25000
    // diberikan), LALU "Tambah Belanjaan" menambah total jadi 15000 tetap
    // (representasi akhir: paid 40000 tapi 30000-nya adalah kembalian yg
    // dipakai ulang) -- net sisa 5000, TAPI raw (total-paid) = 15000-40000
    // = -25000, sangat negatif.
    await _insertTx(db,
        id: 'tx-b',
        localId: 'K1-B',
        customerId: 'cust-1',
        status: 'kurang_bayar',
        total: 15000,
        paid: 40000,
        createdAt: DateTime(2026, 1, 2));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
          id: 'pay-b',
          transactionId: 'tx-b',
          amount: 40000,
          method: 'tunai',
          paidAt: Value(DateTime(2026, 1, 2)),
          changeGiven: const Value(30000),
        ));

    // Raw SUM lama: 20000 + (15000-40000) = 20000 - 25000 = -5000 <= 0
    // -> customer HILANG dari Buku Hutang sama sekali (bug lama).
    // Net SUM benar: 20000 + (15000-40000+30000) = 20000 + 5000 = 25000.
    final debtBook = await db.getDebtBook();
    expect(debtBook, hasLength(1),
        reason: 'pelanggan HARUS tetap muncul di Buku Hutang — sebelum fix, '
            'kontribusi negatif nota tx-b menutupi nota tempo tx-a sepenuhnya');
    expect(debtBook.single.customerId, 'cust-1');
    expect(debtBook.single.debt, 25000,
        reason: 'total hutang net = 20000 (tx-a) + 5000 (tx-b) = 25000, '
            'bukan -5000 (raw) atau 20000 (kalau tx-b diabaikan begitu saja)');
    expect(debtBook.single.count, 2);

    final (debtTotal, debtCount) =
        await db.getCustomerOutstandingDebt('cust-1');
    expect(debtTotal, 25000);
    expect(debtCount, 2);

    final unpaid = await db.getUnpaidTxDetails('cust-1');
    expect(unpaid, hasLength(2));
    expect(unpaid.firstWhere((t) => t.id == 'tx-a').sisa, 20000);
    expect(unpaid.firstWhere((t) => t.id == 'tx-b').sisa, 5000);
  });
}
