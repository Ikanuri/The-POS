import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Kembalian per-pembayaran (bukan per-transaksi): tiap baris
/// `transaction_payments` punya `changeGiven`/`changeTaken` sendiri,
/// dihitung SEKALI saat baris itu dibuat — immutable setelahnya (kecuali
/// dikurangi eksplisit via reuse-kredit, fitur terpisah).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> addTx({
    required int total,
    required int paid,
    required String status,
  }) async {
    final id = 'tx-${DateTime.now().microsecondsSinceEpoch}';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: id,
          status: status,
          total: total,
          paid: paid,
          changeAmount: paid > total ? paid - total : 0,
          paymentMethod: 'tunai',
        ));
    return id;
  }

  test('addPaymentToTransaction (Tambah Bayar): kembalian dari pembayaran '
      'itu sendiri, tersimpan di baris pembayarannya', () async {
    final txId = await addTx(total: 50000, paid: 30000, status: 'kurang_bayar');

    final change = await db.addPaymentToTransaction(
      txId: txId,
      amount: 25000, // sisa 20rb + lebih 5rb
      method: 'tunai',
      kasirId: 'K1',
    );
    expect(change, 5000);

    final payments = await db.getPaymentsForTx(txId);
    expect(payments, hasLength(1));
    expect(payments.first.changeGiven, 5000);
    expect(payments.first.changeTaken, isFalse);
  });

  test(
      'addItemsToTransaction (Tambah Belanjaan) TANPA pembayaran baru: '
      'kembalian agregat (Transactions.changeAmount) otomatis berkurang '
      'sesuai penambahan (reuse implisit lewat rekonsiliasi, TIDAK berubah '
      'perilaku lama)', () async {
    final txId = await addTx(total: 50000, paid: 100000, status: 'lunas');
    // Item awal (50rb) — _reconcileTransactionTotals sumber kebenarannya
    // Σ subtotal item, BUKAN header tx.total.
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'p',
        productUnitId: 'u',
        qty: 1,
        priceAtSale: 50000,
        originalPrice: 50000,
        subtotal: 50000));
    // Simulasikan baris pembayaran awal dengan changeGiven 50000.
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'p1',
            transactionId: txId,
            amount: 100000,
            method: 'tunai',
            changeGiven: const Value(50000)));

    await db.addItemsToTransaction(
      txId: txId,
      items: [
        TransactionItemsCompanion.insert(
          id: 'i1',
          transactionId: txId,
          productId: 'p',
          productUnitId: 'u',
          qty: 1,
          priceAtSale: 30000,
          originalPrice: 30000,
          subtotal: 30000,
        ),
      ],
      stockItems: const [],
    );

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    expect(tx.total, 80000);
    expect(tx.paid, 100000);
    expect(tx.changeAmount, 20000, reason: '100rb - 80rb = 20rb sisa');

    // Baris pembayaran awal TIDAK disentuh (immutable) — masih 50000.
    final payments = await db.getPaymentsForTx(txId);
    expect(payments, hasLength(1));
    expect(payments.first.changeGiven, 50000);
  });

  test(
      'addItemsToTransaction DENGAN pembayaran baru (kasir minta bayar '
      'tambahan): kembalian baris baru dihitung terhadap total SETELAH '
      'tambahan, tidak dobel-hitung kembalian lama', () async {
    final txId = await addTx(total: 50000, paid: 100000, status: 'lunas');
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'p1',
            transactionId: txId,
            amount: 100000,
            method: 'tunai',
            changeGiven: const Value(50000)));

    // Tambah barang 80rb, kasir minta bayar fresh 100rb (tidak pakai kredit
    // lama sama sekali).
    await db.addItemsToTransaction(
      txId: txId,
      items: [
        TransactionItemsCompanion.insert(
          id: 'i1',
          transactionId: txId,
          productId: 'p',
          productUnitId: 'u',
          qty: 1,
          priceAtSale: 80000,
          originalPrice: 80000,
          subtotal: 80000,
        ),
      ],
      stockItems: const [],
      payment: TransactionPaymentsCompanion.insert(
        id: 'p2',
        transactionId: txId,
        amount: 100000,
        method: 'tunai',
      ),
    );

    final payments = await db.getPaymentsForTx(txId);
    expect(payments, hasLength(2));
    // total baru = 130rb, paid baru = 200rb → agregat kembalian 70rb.
    // Punya baris#1 = 50rb → baris#2 harus 70rb-50rb = 20rb (bukan 70rb,
    // yang akan dobel-hitung 50rb yang sudah tercatat di baris#1).
    expect(payments.last.changeGiven, 20000);
  });

  test(
      'settleMergedDebt: kembalian sisa (setelah semua nota di batch '
      'terlunasi) nempel ke baris pembayaran nota TERAKHIR, bukan dihitung '
      'per-nota', () async {
    final t1 = await addTx(total: 20000, paid: 0, status: 'tempo');
    final t2 = await addTx(total: 30000, paid: 0, status: 'tempo');

    final (applied, change) = await db.settleMergedDebt(
      txIds: [t1, t2],
      amount: 70000, // 20rb + 30rb + sisa 20rb
      method: 'tunai',
      kasirId: 'K1',
    );
    expect(applied, 50000);
    expect(change, 20000);

    final paymentsT1 = await db.getPaymentsForTx(t1);
    final paymentsT2 = await db.getPaymentsForTx(t2);
    expect(paymentsT1.single.changeGiven, 0,
        reason: 'nota pertama tidak overpay sendiri, tidak dapat kembalian');
    expect(paymentsT2.single.changeGiven, 20000,
        reason: 'nota TERAKHIR di batch ini menampung sisa kembalian');
    // Angka utang per-nota tidak digelembungkan oleh kembalian.
    final txT2 = await (db.select(db.transactions)
          ..where((t) => t.id.equals(t2)))
        .getSingle();
    expect(txT2.paid, 30000, reason: 'paid = persis sisa tagihan nota itu');
  });

  test('backfillMissingPayments: mewarisi kembalian & status ambil dari '
      'header transaksi lama (data sebelum migrasi ini)', () async {
    const txId = 'legacy-1';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: txId,
          status: 'lunas',
          total: 15000,
          paid: 20000,
          changeAmount: 5000,
          changeTaken: const Value(true),
          paymentMethod: 'tunai',
        ));

    await db.backfillMissingPayments();

    final payments = await db.getPaymentsForTx(txId);
    expect(payments, hasLength(1));
    expect(payments.first.changeGiven, 5000);
    expect(payments.first.changeTaken, isTrue);
  });
}
