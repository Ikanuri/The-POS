import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 61 — `voidPayment` pada pembayaran DP/jaminan pre-order sebelumnya
/// HANYA membalik nominal `paid`/status nota lewat `_reconcileTransactionTotals`
/// (tidak ada uang hilang scr nominal), TAPI tidak pernah membalik efek lain
/// dari `collectPreorderDeposit`: `transactionItems.priceAtSale`/`subtotal`
/// baris pre-order (yang tadinya dinaikkan dari Rp0 ke harga asli) TETAP di
/// harga asli, dan `preorderEntries.paid` tetap `true` — status "DP sudah
/// dibayar" nyangkut walau pembayarannya sudah dibatalkan.
///
/// Fix: `voidPayment` guard tambahan — kalau baris pembayaran yg dibatalkan
/// punya note persis `collectPreorderDeposit` ('DP/jaminan pre-order'),
/// REVERSE eksplisit (kebalikan persis): item balik ke Rp0, `paid` balik
/// `false`, total nota ikut turun.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedTx() async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P1', name: 'Tabung Gas'));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 30000,
          paid: 30000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti_lain',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 30000,
          originalPrice: 30000,
          subtotal: 30000,
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti_lpg',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U2',
          qty: 2,
          priceAtSale: 0,
          originalPrice: 15000,
          subtotal: 0,
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: 'tx1', amount: 30000, method: 'tunai'));
  }

  test(
      'voidPayment pada DP pre-order -> priceAtSale/subtotal balik 0, '
      'preorderEntries.paid balik false, total nota turun', () async {
    await seedTx();
    await db.addPreorderEntry(
        id: 'po1',
        productId: 'P1',
        productUnitId: 'U2',
        customerName: 'Umum',
        qtyOrdered: 2,
        transactionId: 'tx1',
        transactionItemId: 'ti_lpg');

    await db.collectPreorderDeposit(
        preorderEntryId: 'po1',
        amount: 30000,
        method: 'tunai',
        kasirId: 'K1');

    // Sanity: DP sudah dibayar, item sudah naik ke harga asli.
    var item = await (db.select(db.transactionItems)
          ..where((t) => t.id.equals('ti_lpg')))
        .getSingle();
    expect(item.priceAtSale, 15000);
    expect(item.subtotal, 30000);
    var entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(entry.paid, isTrue);
    var tx =
        await (db.select(db.transactions)..where((t) => t.id.equals('tx1')))
            .getSingle();
    expect(tx.total, 60000);

    // Cari baris pembayaran DP yang baru saja dicatat (bukan pay1 awal).
    final dpPayment = await (db.select(db.transactionPayments)
          ..where((t) =>
              t.transactionId.equals('tx1') & t.id.isNotValue('pay1')))
        .getSingle();
    expect(dpPayment.note, 'DP/jaminan pre-order');

    // Batalkan pembayaran DP itu.
    await db.voidPayment(dpPayment.id);

    // Item HARUS balik ke Rp0 (kebalikan persis collectPreorderDeposit).
    item = await (db.select(db.transactionItems)
          ..where((t) => t.id.equals('ti_lpg')))
        .getSingle();
    expect(item.priceAtSale, 0,
        reason: 'tanpa fix, priceAtSale tetap di harga asli walau DP-nya '
            'sudah dibatalkan');
    expect(item.subtotal, 0);

    // preorderEntries.paid HARUS balik false.
    entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(entry.paid, isFalse,
        reason: 'tanpa fix, status "DP sudah dibayar" nyangkut walau '
            'pembayarannya sudah dibatalkan');

    // Total nota HARUS turun balik (item LPG kembali Rp0).
    tx = await (db.select(db.transactions)..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(tx.total, 30000,
        reason: 'total nota harus turun balik setelah DP pre-order '
            'dibatalkan (item LPG kembali dihargai Rp0)');

    // Pembayaran DP itu sendiri tetap tercatat sbg voided (bukan dihapus —
    // pola soft-delete konsisten app ini), paid nota juga turun konsisten.
    final voidedPay = await (db.select(db.transactionPayments)
          ..where((t) => t.id.equals(dpPayment.id)))
        .getSingle();
    expect(voidedPay.voided, isTrue);
    expect(tx.paid, 30000);
  });
}
