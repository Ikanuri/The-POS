import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 87 (laporan user) — ganti pelanggan di nota lunas yang punya
/// pre-order: di keranjang pelanggan BARU cuma chip Hutang (membaca
/// `transactions.customer_id`) yang ikut pindah. Chip "DP Pre-order", sheet
/// Pelunasi Pre-order (termasuk "Sekaligus penuhi") & pengingat Laci Meja
/// masih mencocokkan salinan beku `customer_id`/nama di baris entri Laci
/// Meja, yang tidak pernah diperbarui `changeTransactionCustomer`.
/// Sekarang semuanya membaca identitas TERKINI nota tertaut.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// Nota lunas milik pelanggan A: satu baris pre-order DP belum dibayar
  /// (Rp 0, harga asli 30.000), satu titipan, satu pinjaman.
  Future<void> seed() async {
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'P1', name: 'LPG'));
    // `getPreorderSettlementCandidates` INNER JOIN ke product_units.
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1',
          productId: 'P1',
          isBaseUnit: const Value(true),
        ));
    for (final (id, name) in [('A', 'Andi'), ('B', 'Budi'), ('B2', 'Budi')]) {
      await db.into(db.customers)
          .insert(CustomersCompanion.insert(id: id, name: name));
    }
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'src',
          localId: 'src',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: const Value('A'),
          createdAt: Value(DateTime.now().subtract(const Duration(days: 1))),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'ti_po',
        transactionId: 'src',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 0,
        originalPrice: 30000,
        subtotal: 0));
    await db.addPreorderEntry(
        id: 'po1',
        productId: 'P1',
        productUnitId: 'U1',
        customerName: 'Andi',
        customerId: 'A',
        qtyOrdered: 1,
        transactionId: 'src',
        transactionItemId: 'ti_po');
    await db.addLeftBehindItem(
        id: 'lb1',
        transactionId: 'src',
        itemName: 'Wadah',
        jenis: 'titip',
        customerId: 'A',
        customerNameText: 'Andi');
    await db.addBorrowedItem(
        id: 'bw1',
        transactionId: 'src',
        itemName: 'Krat',
        qty: 1,
        customerId: 'A',
        customerNameText: 'Andi');
  }

  test('ganti pelanggan A -> B: DP pre-order, kandidat Pelunasi, pengingat '
      'Laci Meja pindah ke B', () async {
    await seed();
    await db.changeTransactionCustomer(txId: 'src', newCustomerId: 'B');

    final depB = await db.getCustomerOutstandingPreorderDeposit('B');
    expect(depB, (30000, 1),
        reason: 'tanpa fix: chip "DP Pre-order" tidak pernah muncul utk '
            'pelanggan baru');
    expect(await db.getCustomerOutstandingPreorderDeposit('A'), (0, 0),
        reason: 'pelanggan lama tidak boleh lagi ditagih DP pre-order ini');

    final candB = await db.getPreorderSettlementCandidates('B');
    expect(candB.map((c) => c.preorderEntryId), ['po1'],
        reason: 'sheet Pelunasi Pre-order (jalur "Sekaligus penuhi") harus '
            'menawarkan pre-order ini utk pelanggan baru');
    expect(await db.getPreorderSettlementCandidates('A'), isEmpty);

    final pendingB = await db.getLaciMejaPending(customerId: 'B');
    expect(pendingB.preorders.map((p) => p.id), ['po1']);
    expect(pendingB.titip, 1);
    expect(pendingB.pinjaman, 1);
    final pendingA = await db.getLaciMejaPending(customerId: 'A');
    expect(pendingA.preorders, isEmpty);
    expect(pendingA.titip, 0);
    expect(pendingA.pinjaman, 0);

    final refsB = await db.getOpenPreorderRefsForCustomer(
        customerId: 'B', customerName: 'Budi', excludeTransactionId: 'lain');
    expect(refsB.keys, ['P1']);
  });

  test('Item 58 tetap: pelanggan terdaftar lain dgn nama SAMA tidak ikut '
      'tertaut', () async {
    await seed();
    await db.changeTransactionCustomer(txId: 'src', newCustomerId: 'B');
    expect(await db.getCustomerOutstandingPreorderDeposit('B2'), (0, 0));
    expect((await db.getLaciMejaPending(customerId: 'B2')).preorders, isEmpty);
  });

  test('ganti ke pembeli ad-hoc: dicocokkan lewat nama nota, bukan id lama',
      () async {
    await seed();
    await db.changeTransactionCustomer(
        txId: 'src', newCustomerId: null, newCustomerName: 'Sari');
    final pending = await db.getLaciMejaPending(customerName: 'Sari');
    expect(pending.preorders.map((p) => p.id), ['po1']);
    expect(pending.titip, 1);
    expect(pending.pinjaman, 1);
    expect((await db.getLaciMejaPending(customerId: 'A')).preorders, isEmpty);
  });

  test('entri tanpa nota & nota tanpa identitas tetap pakai salinan beku',
      () async {
    await seed();
    // Pre-order berdiri sendiri (tanpa nota).
    await db.addPreorderEntry(
        id: 'po_lepas',
        productId: 'P1',
        productUnitId: 'U1',
        customerName: 'Andi',
        customerId: 'A',
        qtyOrdered: 2);
    // Nota src jadi tanpa identitas -> jatuh ke salinan beku (A).
    await db.changeTransactionCustomer(
        txId: 'src', newCustomerId: null, newCustomerName: null);
    final pendingA = await db.getLaciMejaPending(customerId: 'A');
    expect(pendingA.preorders.map((p) => p.id).toSet(), {'po1', 'po_lepas'});
    expect(pendingA.titip, 1);
  });
}
