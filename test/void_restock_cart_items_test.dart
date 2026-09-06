import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// "Batalkan & Susun Ulang" (fitur baru) — `AppDatabase.cartItemsFromTransaction`
/// menyusun ulang baris nota jadi `List<CartItem>` siap diisi ke keranjang
/// aktif. Test Tier 1 (DB murni, lihat CLAUDE.md §Metode Test) — murni
/// membuktikan query/transformasinya, TANPA widget.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(201), name: 'Pcs'));
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(202), name: 'Dus'));
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Beras'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true),
        unitTypeId: const Value(201)));
    // Varian anak dari p1.
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v1', name: 'Beras Premium',
        parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'uv1', productId: 'v1', unitTypeId: const Value(202)));
  });
  tearDown(() async => db.close());

  Future<void> seedTx(String id, {String status = 'lunas'}) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: id,
            localId: id,
            status: status,
            total: 18000,
            paid: 18000,
            changeAmount: 0,
            paymentMethod: 'tunai',
          ));

  test('menyusun ulang baris induk + varian, urut induk DULU baru varian',
      () async {
    await seedTx('tx1');
    // Sengaja disimpan varian DULU (urutan insert acak) — hasil harus tetap
    // induk dulu.
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i-variant', transactionId: 'tx1', productId: 'v1',
        productUnitId: 'uv1', qty: 1, priceAtSale: 8000, originalPrice: 8000,
        subtotal: 8000));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i-parent', transactionId: 'tx1', productId: 'p1',
        productUnitId: 'u1', qty: 2, priceAtSale: 5000, originalPrice: 5000,
        subtotal: 10000));

    final lines = await db.cartItemsFromTransaction('tx1');

    expect(lines, hasLength(2));
    expect(lines[0].productId, 'p1',
        reason: 'induk harus lebih dulu di list — CartNotifier.addItem perlu '
            'induk sudah ada di cart sebelum varian menyusul, supaya '
            'storedQty induk ikut naik otomatis');
    expect(lines[0].isVariant, isFalse);
    expect(lines[0].qty, 2);
    expect(lines[0].productName, 'Beras');
    expect(lines[0].unitName, 'Pcs');
    expect(lines[1].productId, 'v1');
    expect(lines[1].isVariant, isTrue);
    expect(lines[1].parentProductId, 'p1');
    expect(lines[1].qty, 1);
    expect(lines[1].unitName, 'Dus');
  });

  test('baris RETUR (qty negatif) DIKECUALIKAN — barang sudah kembali ke rak',
      () async {
    await seedTx('tx2');
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1', transactionId: 'tx2', productId: 'p1', productUnitId: 'u1',
        qty: 3, priceAtSale: 5000, originalPrice: 5000, subtotal: 15000));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1-retur', transactionId: 'tx2', productId: 'p1',
        productUnitId: 'u1', qty: -1, priceAtSale: 5000, originalPrice: 5000,
        subtotal: -5000, returnedAt: Value(DateTime.now())));

    final lines = await db.cartItemsFromTransaction('tx2');

    expect(lines, hasLength(1),
        reason: 'baris retur (qty negatif) tidak boleh ikut disusun ulang');
    expect(lines.single.qty, 3);
  });

  test('nota tanpa baris apa pun (mis. id tidak ditemukan) -> list kosong',
      () async {
    final lines = await db.cartItemsFromTransaction('tx-tak-ada');
    expect(lines, isEmpty);
  });

  test('harga/HPP/override per baris ikut tersalin apa adanya', () async {
    await seedTx('tx4');
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1', transactionId: 'tx4', productId: 'p1', productUnitId: 'u1',
        qty: 1, priceAtSale: 4500, originalPrice: 5000,
        priceOverridden: const Value(true), costAtSale: const Value(3000),
        itemNote: const Value('Diskon karyawan'), subtotal: 4500));

    final lines = await db.cartItemsFromTransaction('tx4');
    final line = lines.single;
    expect(line.price, 4500);
    expect(line.originalPrice, 5000);
    expect(line.priceOverridden, isTrue);
    expect(line.costPrice, 3000);
    expect(line.itemNote, 'Diskon karyawan');
  });
}
