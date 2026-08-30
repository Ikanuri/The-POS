import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Susulan (permintaan user) — nama SPESIFIK metode pembayaran (mis. "GoPay",
/// "BCA") dari `PaymentMethods.name` harus tersnapshot ke
/// `TransactionPayments.methodName`/`Transactions.methodName` lewat
/// `addPaymentToTransaction`/`settleMergedDebt`/`returnPaidTransactionItems`,
/// bukan cuma kategori generik (`method`). Nota lama (methodName == null)
/// harus tetap bisa diproses tanpa error (fallback ditangani di sisi
/// tampilan, bukan di sini).
Future<void> _seedProduct(AppDatabase db) async {
  await db
      .into(db.products)
      .insert(ProductsCompanion.insert(id: 'p1', name: 'Beras'));
  await db.into(db.unitTypes).insertOnConflictUpdate(
      UnitTypesCompanion.insert(id: const Value(1), name: 'pcs'));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1',
        productId: 'p1',
        unitTypeId: const Value(1),
        isBaseUnit: const Value(true),
      ));
}

void main() {
  test('addPaymentToTransaction: methodName tersnapshot ke baris pembayaran',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'tempo',
          total: 50000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'ewallet',
        ));

    await db.addPaymentToTransaction(
      txId: 'tx1',
      amount: 50000,
      method: 'ewallet',
      methodName: 'GoPay',
      kasirId: 'K1',
    );

    final pays = await db.getPaymentsForTx('tx1');
    expect(pays.single.method, 'ewallet');
    expect(pays.single.methodName, 'GoPay');
  });

  test(
      'addPaymentToTransaction: methodName null (mis. kode lama/tunai) '
      'tidak error, kolom tetap null', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'tempo',
          total: 50000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));

    await db.addPaymentToTransaction(
      txId: 'tx1',
      amount: 50000,
      method: 'tunai',
      kasirId: 'K1',
    );

    final pays = await db.getPaymentsForTx('tx1');
    expect(pays.single.methodName, isNull);
  });

  test(
      'settleMergedDebt: methodName tersnapshot ke SEMUA baris pembayaran '
      'yang dibuat di batch (multi-nota)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'tempo',
          total: 30000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tempo',
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx2',
          localId: 'K1-2',
          status: 'tempo',
          total: 20000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tempo',
        ));

    await db.settleMergedDebt(
      txIds: ['tx1', 'tx2'],
      amount: 50000,
      method: 'bank',
      methodName: 'BCA',
      kasirId: 'K1',
    );

    final pays1 = await db.getPaymentsForTx('tx1');
    final pays2 = await db.getPaymentsForTx('tx2');
    expect(pays1.single.methodName, 'BCA');
    expect(pays2.single.methodName, 'BCA');
  });

  test(
      'returnPaidTransactionItems: refundMethodName tersnapshot ke baris '
      'refund negatif', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 50000,
          paid: 50000,
          changeAmount: 0,
          paymentMethod: 'qris',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'p1',
          productUnitId: 'u1',
          qty: 5,
          priceAtSale: 10000,
          originalPrice: 10000,
          subtotal: 50000,
        ));
    await db
        .into(db.transactionPayments)
        .insert(TransactionPaymentsCompanion.insert(
          id: 'pay0',
          transactionId: 'tx1',
          amount: 50000,
          method: 'qris',
          methodName: const Value('QRIS Merchant'),
        ));

    await db.returnPaidTransactionItems(
      txId: 'tx1',
      returns: [(transactionItemId: 'ti1', qty: 2)],
      kasirId: 'K1',
      refundMethod: 'qris',
      refundMethodName: 'QRIS Merchant',
    );

    final pays = await db.getPaymentsForTx('tx1');
    final refund = pays.singleWhere((p) => p.amount < 0);
    expect(refund.methodName, 'QRIS Merchant');
  });
}
