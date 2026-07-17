import 'package:drift/drift.dart' show Value;
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
    int paid = 0,
  }) async {
    final txId = 'tx-${DateTime.now().microsecondsSinceEpoch}';
    final total = (price * qty).round();
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: txId,
          status: 'kurang_bayar',
          total: total,
          paid: paid,
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

  test(
      'nota SUDAH ada pembayaran (paid>0): newQty tidak bisa MELEBIHI qty '
      'asli (clamp, bukan nambah stok baru)', () async {
    final txId = await addUnpaidTxWithItem(qty: 2, price: 1000, paid: 1000);

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
    expect(item.qty, 2,
        reason: 'sudah ada uang masuk — clamp ke qty asli, tidak boleh nambah');
  });

  test(
      'nota BELUM ADA pembayaran sama sekali (paid==0): newQty BOLEH '
      'melebihi qty asli — potong stok tambahan seperti item baru',
      () async {
    // Seed stok cukup dulu supaya penambahan qty tidak minus. createdAt
    // eksplisit di masa lalu — hindari race precision detik SQL default
    // vs DateTime.now() presisi mikrodetik yang dipakai _appendStock.
    await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
          id: 'seed-stock',
          productUnitId: 'u',
          qtyChange: 100,
          stockAfter: 100,
          type: 'adjustment',
          createdAt: Value(DateTime.now().subtract(const Duration(minutes: 1))),
        ));
    final txId = await addUnpaidTxWithItem(qty: 2, price: 1000, paid: 0);
    final stockBefore = await db.currentStock('u');

    await db.editUnpaidTransactionItem(
      txId: txId,
      transactionItemId: '$txId-item',
      newQty: 5, // lebih besar dari qty asli (2)
      newPrice: 1000,
      kasirId: 'K1',
    );

    final item = await (db.select(db.transactionItems)
          ..where((t) => t.id.equals('$txId-item')))
        .getSingle();
    expect(item.qty, 5,
        reason: 'belum ada uang masuk — boleh naik bebas, tidak di-clamp');

    final tx =
        await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
            .getSingle();
    expect(tx.total, 5000, reason: '5 x 1000');

    final stockAfter = await db.currentStock('u');
    expect(stockAfter, stockBefore - 3,
        reason: '3 unit tambahan (5-2) dipotong dari stok, sama seperti '
            'item baru di Tambah Belanjaan');
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
