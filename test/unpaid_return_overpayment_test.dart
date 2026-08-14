import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Dilaporkan user (11 Agt 2026): pelanggan punya hutang tempo lalu meretur
/// barang senilai LEBIH dari sisa hutangnya — kelebihannya jadi hak
/// pelanggan, tapi dulu TIDAK PERNAH muncul di layar manapun.
///
/// Akar: `returnUnpaidTransactionItems`/`editUnpaidTransactionItem` cuma
/// menyisipkan baris penanda `amount: 0` dgn `changeGiven` 0. Kelebihannya
/// memang terhitung, TAPI cuma mendarat di `transactions.changeAmount` —
/// kolom yang TIDAK PERNAH dirender: baris "Kembalian" di struk membaca
/// `changeGiven` pembayaran TERAKHIR (`_latestPayment`), bukan kolom header
/// itu. Jadi uangnya hilang tanpa jejak yang bisa dilihat kasir.
///
/// Fix (keputusan user: "samakan dgn UI/UX kembalian yang sudah ada"):
/// kelebihan ditulis sbg `changeGiven` di baris penanda, memakai
/// `_computePaymentChangeGiven` yang SAMA dgn kembalian biasa — sehingga
/// seluruh UX kembalian yang sudah ada (baris Kembalian di struk, centang
/// `changeTaken`, hitungan `netRemainingOwed`) langsung berlaku.
Future<void> _seedProduct(AppDatabase db) async {
  await db.into(db.products).insert(
      ProductsCompanion.insert(id: 'p1', name: 'Beras'));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1',
        productId: 'p1',
        isBaseUnit: const Value(true),
      ));
}

/// Nota kurang_bayar: total 100rb (2 baris @50rb), sudah disetor 30rb.
Future<void> _seedTx(AppDatabase db) async {
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx1',
        localId: 'K1-1',
        status: 'kurang_bayar',
        total: 100000,
        paid: 30000,
        changeAmount: 0,
        paymentMethod: 'tunai',
      ));
  for (final i in [1, 2]) {
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti$i',
          transactionId: 'tx1',
          productId: 'p1',
          productUnitId: 'u1',
          qty: 1,
          priceAtSale: 50000,
          originalPrice: 50000,
          subtotal: 50000,
        ));
  }
  await db.into(db.transactionPayments).insert(
      TransactionPaymentsCompanion.insert(
        id: 'pay1',
        transactionId: 'tx1',
        amount: 30000,
        method: 'tunai',
      ));
}

void main() {
  test(
      'retur melebihi sisa hutang -> kelebihan tercatat sbg changeGiven di '
      'baris penanda (bukan angka mati di changeAmount)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db);
    await _seedTx(db);

    // Retur SATU baris 50rb -> total jadi 50rb, padahal sudah bayar 30rb.
    // Belum lebih bayar (50rb > 30rb) — kembalian harus TETAP 0.
    await db.returnUnpaidTransactionItems(
      txId: 'tx1',
      returns: [(transactionItemId: 'ti1', qty: 1)],
      kasirId: 'K1',
    );
    var pays = await db.getPaymentsForTx('tx1');
    expect(pays.last.changeGiven, 0,
        reason: 'total 50rb masih di atas setoran 30rb — belum ada kelebihan');

    // Retur baris KEDUA -> total jadi 0, setoran 30rb jadi kelebihan penuh.
    await db.returnUnpaidTransactionItems(
      txId: 'tx1',
      returns: [(transactionItemId: 'ti2', qty: 1)],
      kasirId: 'K1',
    );
    pays = await db.getPaymentsForTx('tx1');
    expect(pays.last.changeGiven, 30000,
        reason: 'seluruh isi nota diretur -> 30rb yang sudah disetor jadi '
            'hak pelanggan, harus tampil sbg kembalian');
  });

  test('kelebihan bikin sisa tagihan NET jadi 0, bukan negatif', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db);
    await _seedTx(db);

    await db.returnUnpaidTransactionItems(
      txId: 'tx1',
      returns: [
        (transactionItemId: 'ti1', qty: 1),
        (transactionItemId: 'ti2', qty: 1),
      ],
      kasirId: 'K1',
    );

    final sisa = await db.getNetSisaForTxIds(['tx1']);
    expect(sisa['tx1'], 0);

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(tx.status, 'lunas');
  });

  test(
      'HAPUS item (editUnpaidTransactionItem qty->0) kena pola yang SAMA — '
      'kelebihan juga tercatat sbg changeGiven', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db);
    await _seedTx(db);

    await db.editUnpaidTransactionItem(
      txId: 'tx1',
      transactionItemId: 'ti1',
      newQty: 0,
      newPrice: 50000,
      kasirId: 'K1',
    );
    await db.editUnpaidTransactionItem(
      txId: 'tx1',
      transactionItemId: 'ti2',
      newQty: 0,
      newPrice: 50000,
      kasirId: 'K1',
    );

    final pays = await db.getPaymentsForTx('tx1');
    expect(pays.last.changeGiven, 30000,
        reason: 'hapus item sampai nota kosong menghasilkan kelebihan bayar '
            'yang identik dgn retur — jalurnya beda, bugnya sama');
  });

  test('nota belum pernah dibayar sama sekali (tempo murni) -> tidak ada '
      'kembalian palsu', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx2',
          localId: 'K1-2',
          status: 'tempo',
          total: 50000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tempo',
        ));
    await db.into(db.transactionItems).insert(
        TransactionItemsCompanion.insert(
          id: 'ti9',
          transactionId: 'tx2',
          productId: 'p1',
          productUnitId: 'u1',
          qty: 1,
          priceAtSale: 50000,
          originalPrice: 50000,
          subtotal: 50000,
        ));

    await db.returnUnpaidTransactionItems(
      txId: 'tx2',
      returns: [(transactionItemId: 'ti9', qty: 1)],
      kasirId: 'K1',
    );

    final pays = await db.getPaymentsForTx('tx2');
    expect(pays.last.changeGiven, 0,
        reason: 'belum ada uang masuk sama sekali — tidak ada yang bisa '
            'dikembalikan');
  });
}
