import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug ditemukan (laporan user, terkonfirmasi reproduksi): pre-order yang
/// notanya di-VOID (`voidTransaction` sudah benar membatalkan entri pending
/// via `cancelPreorderEntry`, `cancelledAt` ter-stamp) TETAP muncul sbg
/// kandidat "Pelunasi Pre-order" di keranjang SELAMANYA — `getPreorderSettlementCandidates`/
/// `getCustomerOutstandingPreorderDeposit` cuma cek `paid = false`, tidak
/// pernah cek `cancelledAt`/status nota induk. Diverifikasi (§CLAUDE.md):
/// `voidTransaction` adalah SATU-SATUNYA tempat di app yang men-set
/// `status = 'void'`, dan "Batalkan & Susun Ulang" sendiri memanggil
/// `voidTransaction` lebih dulu — jadi fix ini otomatis mencakup SEMUA nota
/// void, baru maupun lama, tanpa perlu migrasi data.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  const customerId = 'c1';
  const customerName = 'Buk Artia';
  const txId = 'po_src1';
  const preorderId = 'po1';

  Future<void> seedPreorderSource() async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Tabung Gas LPG'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1',
          productId: 'P1',
          isBaseUnit: const Value(true),
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U2',
          productId: 'P1',
        ));
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: customerId, name: customerName));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: txId,
          status: 'lunas',
          total: 30000,
          paid: 30000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: const Value(customerId),
          createdAt: Value(DateTime.now().subtract(const Duration(days: 2))),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: '${txId}_ti_lain',
          transactionId: txId,
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 30000,
          originalPrice: 30000,
          subtotal: 30000,
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: '${txId}_ti_lpg',
          transactionId: txId,
          productId: 'P1',
          productUnitId: 'U2',
          qty: 2,
          priceAtSale: 0,
          originalPrice: 18000,
          subtotal: 0,
        ));
    await db.addPreorderEntry(
        id: preorderId,
        productId: 'P1',
        productUnitId: 'U2',
        customerName: customerName,
        customerId: customerId,
        qtyOrdered: 2,
        transactionId: txId,
        transactionItemId: '${txId}_ti_lpg');
  }

  test(
      'SEBELUM void: pre-order DP-0 muncul sbg kandidat pelunasan (sanity check)',
      () async {
    await seedPreorderSource();
    final candidates = await db.getPreorderSettlementCandidates(customerId);
    expect(candidates, hasLength(1));
    expect(candidates.single.amount, 36000);

    final outstanding =
        await db.getCustomerOutstandingPreorderDeposit(customerId);
    expect(outstanding.$1, 36000);
    expect(outstanding.$2, 1);
  });

  test(
      'SETELAH nota di-void: pre-order TIDAK BOLEH lagi muncul sbg kandidat '
      'pelunasan (bug: dulu tetap nyangkut selamanya)', () async {
    await seedPreorderSource();
    await db.voidTransaction(txId, 'K1');

    // Sanity: cancelPreorderEntry sudah benar men-stamp cancelledAt.
    final entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals(preorderId)))
        .getSingle();
    expect(entry.cancelledAt, isNotNull);

    final candidates = await db.getPreorderSettlementCandidates(customerId);
    expect(candidates, isEmpty,
        reason: 'nota sumbernya sudah void — tidak ada apa pun yang perlu '
            'dilunasi lagi, tapi query lama tidak pernah cek cancelledAt/'
            'status void');

    final outstanding =
        await db.getCustomerOutstandingPreorderDeposit(customerId);
    expect(outstanding.$2, 0,
        reason: 'chip pengingat cart bar tidak boleh menghitung pre-order '
            'dari nota yang sudah void');
    expect(outstanding.$1, 0);
  });
}
