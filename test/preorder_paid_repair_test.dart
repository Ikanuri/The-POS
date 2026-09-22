import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Perbaikan data satu-kali-jalan (permintaan user, susulan dari fix
/// `applyLaciMejaProposals` di `preorder_paid_proposal_revert_test.dart`) —
/// `repairStalePreorderPaidStatus` membereskan baris `preorder_entries` yang
/// SUDAH TERLANJUR rusak (paid=false padahal DP sungguhan sudah tertagih)
/// SEBELUM fix itu ada, dipanggil tiap startup app (lihat `main.dart`).
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

  Future<void> seedTx(String txId, String itemId,
      {required int priceAtSale, required int originalPrice}) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: txId,
          status: 'lunas',
          total: 0,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(
        TransactionItemsCompanion.insert(
            id: itemId,
            transactionId: txId,
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: priceAtSale,
            originalPrice: originalPrice,
            subtotal: priceAtSale));
  }

  test('baris rusak (paid=false, DP sungguhan sudah lunas) -> diperbaiki jadi paid=true',
      () async {
    await seedProduct();
    // Subtotal SUDAH dinaikkan ke harga asli (persis efek
    // `collectPreorderDeposit`) tapi `paid` ter-revert basi.
    await seedTx('tx1', 'ti1', priceAtSale: 50000, originalPrice: 50000);
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
        id: 'po1',
        customerName: 'Budi',
        productId: 'P1',
        productUnitId: 'U1',
        qtyOrdered: 1,
        transactionId: const Value('tx1'),
        transactionItemId: const Value('ti1'),
        paid: const Value(false)));

    final fixedCount = await db.repairStalePreorderPaidStatus();
    expect(fixedCount, 1);

    final po = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(po.paid, isTrue);
  });

  test('pre-order genuinely belum dibayar (subtotal masih 0) -> TIDAK disentuh',
      () async {
    await seedProduct();
    // Harga masih dikunci Rp 0 — belum pernah dibayar sama sekali.
    await seedTx('tx2', 'ti2', priceAtSale: 0, originalPrice: 50000);
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
        id: 'po2',
        customerName: 'Ani',
        productId: 'P1',
        productUnitId: 'U1',
        qtyOrdered: 1,
        transactionId: const Value('tx2'),
        transactionItemId: const Value('ti2'),
        paid: const Value(false)));

    final fixedCount = await db.repairStalePreorderPaidStatus();
    expect(fixedCount, 0);

    final po = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po2')))
        .getSingle();
    expect(po.paid, isFalse,
        reason: 'entri yang genuinely belum dibayar tidak boleh ikut '
            'ditandai lunas');
  });

  test('sudah paid=true sebelumnya -> tidak disentuh (idempotent)', () async {
    await seedProduct();
    await seedTx('tx3', 'ti3', priceAtSale: 50000, originalPrice: 50000);
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
        id: 'po3',
        customerName: 'Citra',
        productId: 'P1',
        productUnitId: 'U1',
        qtyOrdered: 1,
        transactionId: const Value('tx3'),
        transactionItemId: const Value('ti3'),
        paid: const Value(true)));

    final fixedCount = await db.repairStalePreorderPaidStatus();
    expect(fixedCount, 0);
  });

  test('entri tanpa baris nota tertaut (transactionItemId null) -> dilewati aman',
      () async {
    await seedProduct();
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
        id: 'po4',
        customerName: 'Dedi',
        productId: 'P1',
        productUnitId: 'U1',
        qtyOrdered: 1,
        paid: const Value(false)));

    final fixedCount = await db.repairStalePreorderPaidStatus();
    expect(fixedCount, 0);
  });

  test('dipanggil dua kali berturut-turut -> kedua kalinya aman (idempotent)',
      () async {
    await seedProduct();
    await seedTx('tx5', 'ti5', priceAtSale: 50000, originalPrice: 50000);
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
        id: 'po5',
        customerName: 'Eka',
        productId: 'P1',
        productUnitId: 'U1',
        qtyOrdered: 1,
        transactionId: const Value('tx5'),
        transactionItemId: const Value('ti5'),
        paid: const Value(false)));

    expect(await db.repairStalePreorderPaidStatus(), 1);
    expect(await db.repairStalePreorderPaidStatus(), 0);
  });
}
