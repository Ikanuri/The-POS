import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 4 — "Batalkan Pembayaran": baris pembayaran TETAP tersimpan (jejak
/// audit), tapi paid/status nota dihitung ulang seolah baris itu tak pernah
/// ada. Beda dari void transaksi (`voidTransaction`) yang membatalkan
/// SELURUH nota + stok + poin.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> addTx({
    required int total,
    required int paid,
    required String status,
  }) async {
    final id = 'tx-${DateTime.now().microsecondsSinceEpoch}-${total}_$paid';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: id,
          status: status,
          total: total,
          paid: paid,
          changeAmount: paid > total ? paid - total : 0,
          paymentMethod: 'tunai',
        ));
    // `voidPayment` -> `_reconcileTransactionTotals` selalu menghitung ulang
    // `total` dari Σ transaction_items.subtotal — perlu baris item yang
    // cocok, kalau tidak `total` akan ke-nol-kan tanpa sengaja oleh
    // reconcile (bukan bug voidPayment, murni fixture test).
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: '$id-item',
        transactionId: id,
        productId: 'p',
        productUnitId: 'u',
        qty: 1,
        priceAtSale: total,
        originalPrice: total,
        subtotal: total));
    return id;
  }

  test('voidPayment pada nota lunas (1 pembayaran): paid balik ke 0, status '
      'balik ke kurang_bayar, baris pembayaran TETAP ada (voided=true)',
      () async {
    final txId = await addTx(total: 50000, paid: 50000, status: 'lunas');
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'p1', transactionId: txId, amount: 50000, method: 'tunai'));

    await db.voidPayment('p1');

    final tx =
        await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
            .getSingle();
    expect(tx.paid, 0);
    expect(tx.status, 'kurang_bayar');

    final payments = await db.getPaymentsForTx(txId);
    expect(payments, hasLength(1),
        reason: 'baris TETAP ada sbg jejak audit, tidak dihapus');
    expect(payments.single.voided, isTrue);
    expect(payments.single.amount, 50000, reason: 'nominal historis utuh');
  });

  test('voidPayment membatalkan SATU dari DUA pembayaran: paid dihitung '
      'ulang dari sisa yang tidak dibatalkan saja', () async {
    final txId = await addTx(total: 50000, paid: 50000, status: 'lunas');
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'p1', transactionId: txId, amount: 20000, method: 'tunai'));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'p2', transactionId: txId, amount: 30000, method: 'tunai'));

    await db.voidPayment('p1');

    final tx =
        await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
            .getSingle();
    expect(tx.paid, 30000, reason: 'cuma p2 yang masih dihitung');
    expect(tx.status, 'kurang_bayar');

    final payments = await db.getPaymentsForTx(txId);
    expect(payments, hasLength(2));
    expect(payments.firstWhere((p) => p.id == 'p1').voided, isTrue);
    expect(payments.firstWhere((p) => p.id == 'p2').voided, isFalse);
  });

  test('voidPayment pada pembayaran yang menghasilkan kembalian: '
      'changeGiven baris itu ikut dikeluarkan dari perhitungan status',
      () async {
    final txId = await addTx(total: 30000, paid: 40000, status: 'lunas');
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'p1',
            transactionId: txId,
            amount: 40000,
            method: 'tunai',
            changeGiven: const Value(10000)));

    await db.voidPayment('p1');

    final tx =
        await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
            .getSingle();
    expect(tx.paid, 0);
    expect(tx.status, 'kurang_bayar');
  });

  test('voidPayment pada pembayaran yang sudah dibatalkan: tidak melakukan '
      'apa-apa (idempoten)', () async {
    final txId = await addTx(total: 50000, paid: 50000, status: 'lunas');
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'p1', transactionId: txId, amount: 50000, method: 'tunai'));
    await db.voidPayment('p1');
    await db.voidPayment('p1'); // kedua kali — no-op.

    final tx =
        await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
            .getSingle();
    expect(tx.paid, 0, reason: 'tidak berubah lagi, tidak error');
  });

  test('voidPayment pada nota yang statusnya sudah void: tidak melakukan '
      'apa-apa', () async {
    final txId = await addTx(total: 50000, paid: 50000, status: 'void');
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'p1', transactionId: txId, amount: 50000, method: 'tunai'));

    await db.voidPayment('p1');

    final payments = await db.getPaymentsForTx(txId);
    expect(payments.single.voided, isFalse,
        reason: 'nota void tidak boleh diutak-atik payment-nya lagi');
  });
}
