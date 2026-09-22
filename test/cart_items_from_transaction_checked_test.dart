import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Permintaan user — fitur "Batalkan & Susun Ulang" (`tx_history_sheet.dart`
/// `_redoCartFromVoidedTransaction`) mengisi ulang keranjang dari
/// `cartItemsFromTransaction`. Kalau nota lama sudah punya barang yang
/// dicentang (checklist verifikasi `transactions.checkedItemIds`, lihat
/// `receipt_screen.dart`), centang itu harus ikut terbawa ke `CartItem.checked`
/// di keranjang baru — bukan direset ke false semua.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> seedTxWithTwoItems({required bool checkFirstOnly}) async {
    const txId = 'tx1';
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Gula 1kg'));
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P2', name: 'Minyak 1L'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U2', productId: 'P2', isBaseUnit: const Value(true)));

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 25000,
          paid: 25000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(DateTime.now()),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: txId,
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 15000,
          originalPrice: 15000,
          subtotal: 15000,
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti2',
          transactionId: txId,
          productId: 'P2',
          productUnitId: 'U2',
          qty: 1,
          priceAtSale: 10000,
          originalPrice: 10000,
          subtotal: 10000,
        ));

    final checked = checkFirstOnly ? ['ti1'] : <String>[];
    await (db.update(db.transactions)..where((t) => t.id.equals(txId)))
        .write(TransactionsCompanion(
      checkedItemIds: Value(jsonEncode(checked)),
    ));
    return txId;
  }

  test('item yang sudah dicentang di nota lama ikut checked=true di cart',
      () async {
    final txId = await seedTxWithTwoItems(checkFirstOnly: true);

    final lines = await db.cartItemsFromTransaction(txId);

    expect(lines, hasLength(2));
    final gula = lines.firstWhere((l) => l.productId == 'P1');
    final minyak = lines.firstWhere((l) => l.productId == 'P2');
    expect(gula.checked, isTrue,
        reason: 'ti1 ada di checkedItemIds nota lama');
    expect(minyak.checked, isFalse,
        reason: 'ti2 TIDAK ada di checkedItemIds nota lama');
  });

  test('tidak ada centang di nota lama -> semua checked=false', () async {
    final txId = await seedTxWithTwoItems(checkFirstOnly: false);

    final lines = await db.cartItemsFromTransaction(txId);

    expect(lines, hasLength(2));
    expect(lines.every((l) => !l.checked), isTrue);
  });

  test('checkedItemIds null (nota lama belum pernah dicentang) tidak error',
      () async {
    const txId = 'tx2';
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Gula 1kg'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-2',
          status: 'lunas',
          total: 15000,
          paid: 15000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(DateTime.now()),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti3',
          transactionId: txId,
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 15000,
          originalPrice: 15000,
          subtotal: 15000,
        ));

    final lines = await db.cartItemsFromTransaction(txId);
    expect(lines, hasLength(1));
    expect(lines.single.checked, isFalse);
  });
}
