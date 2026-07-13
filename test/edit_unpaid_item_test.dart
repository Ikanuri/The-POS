import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 5 — edit item langsung di nota BELUM LUNAS (ubah harga/catatan,
/// atau hapus via qty=0). Reuse pola rekonsiliasi `returnUnpaidTransactionItems`
/// (stok dikembalikan utk qty yang tidak jadi terjual, total/paid dihitung
/// ulang dari child rows, tanpa refund tunai).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> addUnpaidTxWithItem({
    required double qty,
    required int price,
  }) async {
    final txId = 'tx-${DateTime.now().microsecondsSinceEpoch}';
    final total = (price * qty).round();
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: txId,
          status: 'kurang_bayar',
          total: total,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: '$txId-item',
        transactionId: txId,
        productId: 'p',
        productUnitId: 'u',
        qty: qty,
        priceAtSale: price,
        originalPrice: price,
        subtotal: total));
    return txId;
  }

  test('ubah harga item: total nota dihitung ulang dari harga baru', () async {
    final txId = await addUnpaidTxWithItem(qty: 2, price: 10000);

    await db.editUnpaidTransactionItem(
      txId: txId,
      transactionItemId: '$txId-item',
      newQty: 2,
      newPrice: 8000,
      kasirId: 'K1',
    );

    final tx =
        await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
            .getSingle();
    expect(tx.total, 16000, reason: '2 x 8000 (bukan 20000 lama)');

    final item = await (db.select(db.transactionItems)
          ..where((t) => t.id.equals('$txId-item')))
        .getSingle();
    expect(item.priceAtSale, 8000);
    expect(item.qty, 2, reason: 'qty tidak ikut berubah');
  });

  test('hapus item (newQty=0): baris hilang, total nota jadi 0, status '
      'lunas (tidak menggantung)', () async {
    final txId = await addUnpaidTxWithItem(qty: 3, price: 5000);

    await db.editUnpaidTransactionItem(
      txId: txId,
      transactionItemId: '$txId-item',
      newQty: 0,
      newPrice: 5000,
      kasirId: 'K1',
    );

    final tx =
        await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
            .getSingle();
    expect(tx.total, 0);
    expect(tx.status, 'lunas',
        reason: 'nota tanpa tagihan tersisa tidak boleh menggantung');

    final items = await (db.select(db.transactionItems)
          ..where((t) => t.transactionId.equals(txId)))
        .get();
    expect(items, isEmpty);
  });

  test('qty dikurangi (bukan dihapus total): stok yang tidak jadi terjual '
      'dikembalikan', () async {
    final txId = await addUnpaidTxWithItem(qty: 5, price: 2000);

    await db.editUnpaidTransactionItem(
      txId: txId,
      transactionItemId: '$txId-item',
      newQty: 2,
      newPrice: 2000,
      kasirId: 'K1',
    );

    final stock = await db.currentStock('u');
    expect(stock, 3, reason: '3 unit (5-2) dikembalikan ke stok');

    final item = await (db.select(db.transactionItems)
          ..where((t) => t.id.equals('$txId-item')))
        .getSingle();
    expect(item.qty, 2);
  });

  test('newQty tidak bisa MELEBIHI qty asli (clamp, bukan nambah stok baru)',
      () async {
    final txId = await addUnpaidTxWithItem(qty: 2, price: 1000);

    await db.editUnpaidTransactionItem(
      txId: txId,
      transactionItemId: '$txId-item',
      newQty: 99, // lebih besar dari qty asli (2)
      newPrice: 1000,
      kasirId: 'K1',
    );

    final item = await (db.select(db.transactionItems)
          ..where((t) => t.id.equals('$txId-item')))
        .getSingle();
    expect(item.qty, 2, reason: 'clamp ke qty asli, tidak boleh nambah');
  });

  test('edit catatan item', () async {
    final txId = await addUnpaidTxWithItem(qty: 1, price: 1000);

    await db.editUnpaidTransactionItem(
      txId: txId,
      transactionItemId: '$txId-item',
      newQty: 1,
      newPrice: 1000,
      newNote: 'minta dibungkus terpisah',
      kasirId: 'K1',
    );

    final item = await (db.select(db.transactionItems)
          ..where((t) => t.id.equals('$txId-item')))
        .getSingle();
    expect(item.itemNote, 'minta dibungkus terpisah');
  });

  test('editUnpaidTransactionItem menolak nota yang SUDAH lunas', () async {
    const txId = 'tx-lunas';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: txId,
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'item1',
        transactionId: txId,
        productId: 'p',
        productUnitId: 'u',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000));

    expect(
      () => db.editUnpaidTransactionItem(
        txId: txId,
        transactionItemId: 'item1',
        newQty: 1,
        newPrice: 5000,
        kasirId: 'K1',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
