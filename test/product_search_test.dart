import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Membuktikan `findTxIdsWithProduct` & `findProductMatchesForQuery` tetap
/// benar setelah diubah dari 1-langkah (JOIN transaction_items+products lalu
/// filter LIKE — menyisir SELURUH riwayat transaksi tiap pencarian) menjadi
/// 2-langkah (cari product id dulu di tabel products yang kecil, baru lookup
/// transaction_items via index product_id) — optimasi ini TIDAK BOLEH
/// mengubah hasil, cuma caranya mencari.
Future<void> _seed(AppDatabase db) async {
  await db.into(db.products).insert(
      ProductsCompanion.insert(id: 'p-indomie', name: 'Indomie Goreng'));
  await db.into(db.products).insert(
      ProductsCompanion.insert(id: 'p-mie-sedaap', name: 'Mie Sedaap Soto'));
  await db.into(db.products)
      .insert(ProductsCompanion.insert(id: 'p-beras', name: 'Beras Premium'));

  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx1',
        localId: 'K1-1',
        status: 'lunas',
        total: 10000,
        paid: 10000,
        changeAmount: 0,
        paymentMethod: 'tunai',
      ));
  await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'ti1',
        transactionId: 'tx1',
        productId: 'p-indomie',
        productUnitId: 'u1',
        qty: 2,
        priceAtSale: 3000,
        originalPrice: 3000,
        subtotal: 6000,
      ));

  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx2',
        localId: 'K1-2',
        status: 'lunas',
        total: 20000,
        paid: 20000,
        changeAmount: 0,
        paymentMethod: 'tunai',
      ));
  // tx2 punya 2 item "mie" (nama beda) — keduanya harus ikut kecantol.
  await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'ti2',
        transactionId: 'tx2',
        productId: 'p-mie-sedaap',
        productUnitId: 'u1',
        qty: 1,
        priceAtSale: 3500,
        originalPrice: 3500,
        subtotal: 3500,
      ));
  await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'ti3',
        transactionId: 'tx2',
        productId: 'p-beras',
        productUnitId: 'u1',
        qty: 1,
        priceAtSale: 16500,
        originalPrice: 16500,
        subtotal: 16500,
      ));

  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx3',
        localId: 'K1-3',
        status: 'lunas',
        total: 16500,
        paid: 16500,
        changeAmount: 0,
        paymentMethod: 'tunai',
      ));
  // tx3 cuma beras — TIDAK boleh kecantol pencarian "mie".
  await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'ti4',
        transactionId: 'tx3',
        productId: 'p-beras',
        productUnitId: 'u1',
        qty: 1,
        priceAtSale: 16500,
        originalPrice: 16500,
        subtotal: 16500,
      ));
}

void main() {
  group('findTxIdsWithProduct', () {
    test('cocok substring "mie" (case-insensitive) mengembalikan tx1 & tx2, bukan tx3',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seed(db);

      final ids = await db.findTxIdsWithProduct('MIE');
      expect(ids, {'tx1', 'tx2'});

      await db.close();
    });

    test('query kosong → set kosong (tidak ikut nyantol semua produk)',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seed(db);

      expect(await db.findTxIdsWithProduct(''), isEmpty);
      expect(await db.findTxIdsWithProduct('   '), isEmpty);

      await db.close();
    });

    test('tidak ada produk cocok → set kosong', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seed(db);

      expect(await db.findTxIdsWithProduct('nasi goreng'), isEmpty);

      await db.close();
    });
  });

  group('findProductMatchesForQuery', () {
    test('mengembalikan detail qty & harga per transaksi, termasuk 2 item '
        'berbeda dalam satu transaksi yang sama', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seed(db);

      final matches = await db.findProductMatchesForQuery('mie');
      expect(matches.keys, containsAll(['tx1', 'tx2']));
      expect(matches.containsKey('tx3'), isFalse,
          reason: 'tx3 cuma beras, tidak boleh ikut kecantol pencarian mie');

      expect(matches['tx1']!.single.name, 'Indomie Goreng');
      expect(matches['tx1']!.single.qty, 2);
      expect(matches['tx1']!.single.price, 3000);

      // tx2 dicari "mie" — cuma item Mie Sedaap yang cocok, BUKAN item
      // Beras Premium yang juga ada di transaksi yang sama.
      expect(matches['tx2']!.length, 1);
      expect(matches['tx2']!.single.name, 'Mie Sedaap Soto');

      await db.close();
    });

    test('query kosong → map kosong', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seed(db);

      expect(await db.findProductMatchesForQuery(''), isEmpty);

      await db.close();
    });
  });
}
