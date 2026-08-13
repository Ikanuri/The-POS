import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Riwayat Pembayaran (permintaan user, 13 Agt 2026): kartu in-app WAJIB
/// menampilkan rincian per-produk momen retur/edit (poin 1), baris "Sisa"
/// per sesi bayar nota tempo (poin 2), dan kembalian/sisa yang berlaku
/// PERSIS pada momen retur/edit itu sendiri (poin 3, "'tersebut' refer ke
/// poin 1"). Test ini membuktikan DATA-nya (bukan widget) — baris di
/// `transaction_adjustment_lines` & kolom `TransactionPayments.sisaAfter`.
Future<void> _seedProduct(AppDatabase db,
    {String id = 'p1',
    String name = 'Beras',
    String unitId = 'u1',
    int unitTypeId = 1}) async {
  await db.into(db.products).insert(ProductsCompanion.insert(id: id, name: name));
  await db
      .into(db.unitTypes)
      .insertOnConflictUpdate(UnitTypesCompanion.insert(
        id: Value(unitTypeId),
        name: 'pcs',
      ));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId,
        productId: id,
        unitTypeId: Value(unitTypeId),
        isBaseUnit: const Value(true),
      ));
}

void main() {
  test(
      'returnUnpaidTransactionItems multi-produk -> rincian per-produk '
      'tercatat lengkap dgn paymentId yg SAMA', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db, id: 'p1', name: 'Beras', unitId: 'u1');
    await _seedProduct(db, id: 'p2', name: 'Gula', unitId: 'u2', unitTypeId: 2);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'tempo',
          total: 100000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tempo',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'p1',
          productUnitId: 'u1',
          qty: 2,
          priceAtSale: 20000,
          originalPrice: 20000,
          subtotal: 40000,
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti2',
          transactionId: 'tx1',
          productId: 'p2',
          productUnitId: 'u2',
          qty: 3,
          priceAtSale: 20000,
          originalPrice: 20000,
          subtotal: 60000,
        ));

    await db.returnUnpaidTransactionItems(
      txId: 'tx1',
      returns: [
        (transactionItemId: 'ti1', qty: 1),
        (transactionItemId: 'ti2', qty: 2),
      ],
      kasirId: 'K1',
    );

    final pays = await db.getPaymentsForTx('tx1');
    expect(pays, hasLength(1));
    final marker = pays.single;
    expect(marker.method, 'retur');

    final lines = await db.getAdjustmentLinesForTx('tx1');
    expect(lines[marker.id], hasLength(2),
        reason: 'retur 2 produk dlm satu panggilan -> 2 baris rincian, '
            'satu paymentId yang sama');
    final beras = lines[marker.id]!.firstWhere((l) => l.productId == 'p1');
    expect(beras.qty, 1);
    expect(beras.priceAtSale, 20000);
    expect(beras.subtotal, 20000);
    expect(beras.productName, 'Beras');
    expect(beras.unitName, 'pcs');
    final gula = lines[marker.id]!.firstWhere((l) => l.productId == 'p2');
    expect(gula.qty, 2);
    expect(gula.subtotal, 40000);
  });

  test(
      'editUnpaidTransactionItem: qty berkurang -> satu baris rincian; '
      'edit catatan MURNI (qty/harga sama) -> TIDAK ada baris rincian',
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
          paymentMethod: 'tempo',
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

    await db.editUnpaidTransactionItem(
      txId: 'tx1',
      transactionItemId: 'ti1',
      newQty: 3,
      newPrice: 10000,
      kasirId: 'K1',
    );
    var pays = await db.getPaymentsForTx('tx1');
    var lines = await db.getAdjustmentLinesForTx('tx1');
    expect(lines[pays.single.id], hasLength(1));
    expect(lines[pays.single.id]!.single.qty, 2,
        reason: 'qty berkurang dari 5 ke 3 -> delta 2 yang dicatat');
    expect(lines[pays.single.id]!.single.subtotal, 20000);

    // Edit catatan murni pada baris item BARU (qty/harga sama persis) —
    // marker Rp0 tetap dibuat (jejak audit), tapi TIDAK ada rincian produk
    // (tidak ada apa pun yg berubah scr nilai barang).
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti2',
          transactionId: 'tx1',
          productId: 'p1',
          productUnitId: 'u1',
          qty: 3,
          priceAtSale: 10000,
          originalPrice: 10000,
          subtotal: 30000,
        ));
    await db.editUnpaidTransactionItem(
      txId: 'tx1',
      transactionItemId: 'ti2',
      newQty: 3,
      newPrice: 10000,
      newNote: 'catatan saja',
      kasirId: 'K1',
    );
    pays = await db.getPaymentsForTx('tx1');
    final noteMarker = pays.last;
    expect(noteMarker.note, 'Item diubah (nota belum lunas)');
    lines = await db.getAdjustmentLinesForTx('tx1');
    expect(lines[noteMarker.id], anyOf(isNull, isEmpty),
        reason: 'edit catatan murni tidak menghasilkan rincian produk');
  });

  test(
      'returnPaidTransactionItems -> rincian EKSAK (bukan approksimasi) '
      'tertaut ke baris refund NEGATIF', () async {
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
          paymentMethod: 'tunai',
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
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
          id: 'pay0',
          transactionId: 'tx1',
          amount: 50000,
          method: 'tunai',
        ));

    await db.returnPaidTransactionItems(
      txId: 'tx1',
      returns: [(transactionItemId: 'ti1', qty: 2)],
      kasirId: 'K1',
      refundMethod: 'tunai',
    );

    final pays = await db.getPaymentsForTx('tx1');
    final refund = pays.singleWhere((p) => p.amount < 0);
    expect(refund.amount, -20000);
    final lines = await db.getAdjustmentLinesForTx('tx1');
    expect(lines[refund.id], hasLength(1));
    expect(lines[refund.id]!.single.qty, 2);
    expect(lines[refund.id]!.single.priceAtSale, 10000);
    expect(lines[refund.id]!.single.subtotal, 20000);
  });

  test(
      'editPaidTransactionItem: delta>0 -> rincian tertaut refund; '
      'delta==0 (catatan saja) -> TIDAK ada refund & TIDAK ada rincian',
      () async {
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
          paymentMethod: 'tunai',
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
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
          id: 'pay0',
          transactionId: 'tx1',
          amount: 50000,
          method: 'tunai',
        ));

    await db.editPaidTransactionItem(
      txId: 'tx1',
      transactionItemId: 'ti1',
      newQty: 3,
      newPrice: 10000,
      kasirId: 'K1',
      refundMethod: 'tunai',
    );
    var pays = await db.getPaymentsForTx('tx1');
    expect(pays, hasLength(2), reason: 'pay0 awal + 1 refund');
    final refund1 = pays.singleWhere((p) => p.amount < 0);
    var lines = await db.getAdjustmentLinesForTx('tx1');
    expect(lines[refund1.id], hasLength(1));
    expect(lines[refund1.id]!.single.qty, 2);
    expect(lines[refund1.id]!.single.subtotal, 20000);

    // Item baru, qty/harga TIDAK berubah (cuma catatan) -> delta == 0,
    // tidak ada refund maupun rincian.
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti2',
          transactionId: 'tx1',
          productId: 'p1',
          productUnitId: 'u1',
          qty: 3,
          priceAtSale: 10000,
          originalPrice: 10000,
          subtotal: 30000,
        ));
    await db.editPaidTransactionItem(
      txId: 'tx1',
      transactionItemId: 'ti2',
      newQty: 3,
      newPrice: 10000,
      newNote: 'catatan saja',
      kasirId: 'K1',
      refundMethod: 'tunai',
    );
    pays = await db.getPaymentsForTx('tx1');
    expect(pays, hasLength(2),
        reason: 'delta 0 (cuma catatan) tidak menghasilkan baris pembayaran '
            'baru — tetap pay0 + refund1 dari sebelumnya');
  });

  test(
      'addPaymentToTransaction: bayar SEBAGIAN nota tempo -> sisaAfter '
      'tercatat, changeGiven tetap 0', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'tempo',
          total: 193000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tempo',
        ));

    await db.addPaymentToTransaction(
      txId: 'tx1',
      amount: 192000,
      method: 'tunai',
      kasirId: 'K1',
    );

    final pays = await db.getPaymentsForTx('tx1');
    expect(pays.single.sisaAfter, 1000,
        reason: 'bayar 192rb dari 193rb -> sisa 1rb, persis contoh user');
    expect(pays.single.changeGiven, 0);
  });

  test(
      'addPaymentToTransaction: bayar LEBIH -> changeGiven tercatat, '
      'sisaAfter tetap 0 (mutually exclusive)', () async {
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
          paymentMethod: 'tempo',
        ));

    await db.addPaymentToTransaction(
      txId: 'tx1',
      amount: 60000,
      method: 'tunai',
      kasirId: 'K1',
    );

    final pays = await db.getPaymentsForTx('tx1');
    expect(pays.single.changeGiven, 10000);
    expect(pays.single.sisaAfter, 0);
  });

  test(
      'returnUnpaidTransactionItems yang masih menyisakan hutang -> momen '
      'retur ITU SENDIRI punya sisaAfter (poin 3: "tersebut" = poin 1)',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db, id: 'p1', name: 'Beras', unitId: 'u1');
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'kurang_bayar',
          total: 100000,
          paid: 20000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'p1',
          productUnitId: 'u1',
          qty: 2,
          priceAtSale: 50000,
          originalPrice: 50000,
          subtotal: 100000,
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
          id: 'pay0',
          transactionId: 'tx1',
          amount: 20000,
          method: 'tunai',
        ));

    // Retur 1 dari 2 -> total jadi 50rb, sudah disetor 20rb -> masih sisa
    // 30rb PERSIS pada momen retur ini.
    await db.returnUnpaidTransactionItems(
      txId: 'tx1',
      returns: [(transactionItemId: 'ti1', qty: 1)],
      kasirId: 'K1',
    );

    final pays = await db.getPaymentsForTx('tx1');
    final marker = pays.last;
    expect(marker.method, 'retur');
    expect(marker.sisaAfter, 30000,
        reason: 'retur yg masih menyisakan hutang -> sisa momen INI harus '
            'tercatat di baris penanda retur, bukan cuma di total nota');
    expect(marker.changeGiven, 0);
  });

  test(
      'settleMergedDebt: pelunasan gabungan yg tidak cukup utk SEMUA nota -> '
      'nota yg baru terbayar sebagian tercatat sisaAfter eksak', () async {
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
          paymentMethod: 'tempo',
          createdAt: Value(DateTime(2026, 1, 1)),
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx2',
          localId: 'K1-2',
          status: 'tempo',
          total: 50000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tempo',
          createdAt: Value(DateTime(2026, 1, 2)),
        ));

    // Bayar 70rb utk 2 nota @50rb (total hutang 100rb) — tx1 (lebih lama)
    // lunas penuh, tx2 cuma kebagian 20rb, sisa 30rb.
    final (applied, change) = await db.settleMergedDebt(
      txIds: ['tx1', 'tx2'],
      amount: 70000,
      method: 'tunai',
      kasirId: 'K1',
    );
    expect(applied, 70000);
    expect(change, 0);

    final pays1 = await db.getPaymentsForTx('tx1');
    expect(pays1.single.sisaAfter, 0);
    final pays2 = await db.getPaymentsForTx('tx2');
    expect(pays2.single.sisaAfter, 30000);
  });
}
