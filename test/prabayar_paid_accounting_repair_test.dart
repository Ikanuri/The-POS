import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Perbaikan data satu-kali-jalan KEDUA (susulan audit Pra-Bayar,
/// permintaan user "audit sync & pre-paid lagi") — `repairStalePrabayarPaidAccounting`
/// membereskan `transactions.paid/status/changeAmount` yang TERLANJUR salah
/// di jendela waktu antara commit `191570c` (9 Sep, amount Pra-Bayar mulai
/// GROSS) dan `0329583` (kemarin, reconcile akhirnya ikut mengurangi
/// potongan) — nota yang tidak pernah disentuh fungsi mutasi apa pun lagi
/// (tambah belanjaan/retur/edit/batal bayar/sync) TETAP salah selamanya
/// tanpa perbaikan ini, krn TIDAK ADA jalur app yg memicu reconcile sekadar
/// krn nota dibuka/dilihat/dicetak.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedProduct() async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P1', name: 'Gula Pasir'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
  }

  test(
      'nota rusak (paid/status/changeAmount salah krn amount gross tidak '
      'dikurangi potongan) -> diperbaiki jadi benar', () async {
    await seedProduct();
    // Simulasikan hasil checkout Pra-Bayar SEBELUM fix `0329583`: total
    // 50.000, Pra-Bayar 84.900 (potongan pre-checkout 54.900) -> SEHARUSNYA
    // paid=30.000/status=kurang_bayar/changeAmount=0, tapi kode LAMA
    // menyimpannya sbg paid=84.900/lunas/changeAmount=34.900 (langsung
    // ditulis manual di sini, BUKAN lewat buildPrabayarCheckout yg sekarang
    // sudah benar -- probe ini murni menguji jalur REPAIR data lama, bukan
    // menguji ulang checkout yg sudah dites terpisah).
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 50000,
          paid: 84900,
          changeAmount: 34900,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 50000,
        originalPrice: 50000,
        subtotal: 50000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: 'tx1',
            amount: 84900,
            method: 'tunai',
            prabayarChangeTakenBeforeCheckout: const Value(54900)));

    final fixedCount = await db.repairStalePrabayarPaidAccounting();
    expect(fixedCount, 1);

    final tx = await (db.select(db.transactions)..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(tx.paid, 30000);
    expect(tx.status, 'kurang_bayar');
    expect(tx.changeAmount, 0);
  });

  test('nota tanpa potongan Pra-Bayar sama sekali -> TIDAK disentuh (bukan kandidat)',
      () async {
    await seedProduct();
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx2',
          localId: 'K1-2',
          status: 'lunas',
          total: 30000,
          paid: 30000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: 'tx2',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 30000,
        originalPrice: 30000,
        subtotal: 30000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay2', transactionId: 'tx2', amount: 30000, method: 'tunai'));

    final fixedCount = await db.repairStalePrabayarPaidAccounting();
    expect(fixedCount, 0);
  });

  test('nota SUDAH benar (checkout via fix terbaru) -> tidak disentuh (idempotent)',
      () async {
    await seedProduct();
    // paid/status/changeAmount SUDAH benar (30.000/kurang_bayar/0) --
    // reconcile ulang harus no-op.
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx3',
          localId: 'K1-3',
          status: 'kurang_bayar',
          total: 50000,
          paid: 30000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i2',
        transactionId: 'tx3',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 50000,
        originalPrice: 50000,
        subtotal: 50000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay3',
            transactionId: 'tx3',
            amount: 84900,
            method: 'tunai',
            prabayarChangeTakenBeforeCheckout: const Value(54900)));

    final fixedCount = await db.repairStalePrabayarPaidAccounting();
    expect(fixedCount, 0);
  });

  test('nota VOID dgn potongan Pra-Bayar -> dilewati aman (tidak error, tidak disentuh)',
      () async {
    await seedProduct();
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx4',
          localId: 'K1-4',
          status: 'void',
          total: 50000,
          paid: 84900,
          changeAmount: 34900,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i3',
        transactionId: 'tx4',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 50000,
        originalPrice: 50000,
        subtotal: 50000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay4',
            transactionId: 'tx4',
            amount: 84900,
            method: 'tunai',
            prabayarChangeTakenBeforeCheckout: const Value(54900)));

    final fixedCount = await db.repairStalePrabayarPaidAccounting();
    expect(fixedCount, 0);
  });

  test('dipanggil dua kali berturut-turut -> kedua kalinya aman (idempotent)',
      () async {
    await seedProduct();
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx5',
          localId: 'K1-5',
          status: 'lunas',
          total: 50000,
          paid: 84900,
          changeAmount: 34900,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i4',
        transactionId: 'tx5',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 50000,
        originalPrice: 50000,
        subtotal: 50000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay5',
            transactionId: 'tx5',
            amount: 84900,
            method: 'tunai',
            prabayarChangeTakenBeforeCheckout: const Value(54900)));

    expect(await db.repairStalePrabayarPaidAccounting(), 1);
    expect(await db.repairStalePrabayarPaidAccounting(), 0);
  });
}
