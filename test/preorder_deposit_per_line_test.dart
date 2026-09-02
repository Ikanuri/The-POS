import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/utils/preorder_calc.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Bug nyata dilaporkan user (nota A1-20260902-0014): satu nota punya 2
/// baris LPG — baris asli checkout (entri pre-order belakangan DIEDIT jadi
/// 2 LPG / 2 jaminan) + baris "Tambahan" (entri baru 1 LPG / 1 jaminan).
/// Kartu Pre-order benar menampilkan 2 + 1, TAPI kedua baris item sama-sama
/// tertulis "Titip 1". Akar: `getPreorderDepositForTransaction` keyed
/// `product|unit` saja — entri kedua MENIMPA yang pertama. Sekarang: keyed
/// PER BARIS (`transaction_item_id`), fallback `product|unit` DIJUMLAHKAN
/// utk entri lama tanpa tautan, dan nilainya jaminan SISA (`sisaDeposit`).
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'A1-20260902-0014',
          status: 'lunas',
          total: 60000,
          paid: 60000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P0', name: 'Gas LPG 3kg'));
    await db
        .into(db.productUnits)
        .insert(ProductUnitsCompanion.insert(id: 'U0', productId: 'P0'));
    for (final (id, qty) in [('iA', 2.0), ('iB', 1.0)]) {
      await db.into(db.transactionItems).insert(
          TransactionItemsCompanion.insert(
              id: id,
              transactionId: txId,
              productId: 'P0',
              productUnitId: 'U0',
              qty: qty,
              priceAtSale: 20000,
              originalPrice: 20000,
              subtotal: (20000 * qty).round()));
    }
  });
  tearDown(() async => db.close());

  Future<TransactionItem> line(String id) =>
      (db.select(db.transactionItems)..where((t) => t.id.equals(id)))
          .getSingle();

  test(
      '2 entri produk+satuan SAMA, masing-masing tertaut baris berbeda -> '
      'label per baris benar (2 & 1), bukan saling menimpa', () async {
    await db.addPreorderEntry(
        id: 'pA',
        productId: 'P0',
        productUnitId: 'U0',
        customerName: 'Ari',
        qtyOrdered: 2,
        depositQty: 2,
        transactionId: txId,
        transactionItemId: 'iA');
    await db.addPreorderEntry(
        id: 'pB',
        productId: 'P0',
        productUnitId: 'U0',
        customerName: 'Ari',
        qtyOrdered: 1,
        depositQty: 1,
        transactionId: txId,
        transactionItemId: 'iB');

    final marks = await db.getPreorderDepositForTransaction(txId);
    expect(preorderDepositForLine(marks, await line('iA')), 2);
    expect(preorderDepositForLine(marks, await line('iB')), 1);
  });

  test(
      'entri LAMA tanpa tautan baris -> fallback produk+satuan DIJUMLAHKAN '
      '(bukan ditimpa)', () async {
    for (final id in ['p1', 'p2']) {
      await db.addPreorderEntry(
          id: id,
          productId: 'P0',
          productUnitId: 'U0',
          customerName: 'Ari',
          qtyOrdered: 1,
          depositQty: 1,
          transactionId: txId);
    }

    final marks = await db.getPreorderDepositForTransaction(txId);
    expect(preorderDepositForLine(marks, await line('iA')), 2,
        reason: '1 + 1 jaminan dari dua entri legacy utk produk yang sama');
  });

  test(
      'jaminan yang tampil = SISA (dikurangi qty sudah dipenuhi sebagian), '
      'konsisten dgn dashboard/laporan; sisa 0 -> tidak ada penanda',
      () async {
    await db.addPreorderEntry(
        id: 'pA',
        productId: 'P0',
        productUnitId: 'U0',
        customerName: 'Ari',
        qtyOrdered: 2,
        depositQty: 2,
        transactionId: txId,
        transactionItemId: 'iA');
    await db.fulfillPreorderQty('pA', 1, eventId: 'e1');

    var marks = await db.getPreorderDepositForTransaction(txId);
    expect(preorderDepositForLine(marks, await line('iA')), 1);

    await db.fulfillPreorderQty('pA', 1, eventId: 'e2');
    marks = await db.getPreorderDepositForTransaction(txId);
    expect(preorderDepositForLine(marks, await line('iA')), isNull,
        reason: 'sudah dipenuhi penuh -> penanda hilang (temporary)');
  });

  testWidgets(
      'struk in-app: baris asli "Titip 2" & baris Tambahan "Titip 1" '
      '(skenario persis laporan user)', (tester) async {
    await db.addPreorderEntry(
        id: 'pA',
        productId: 'P0',
        productUnitId: 'U0',
        customerName: 'Ari',
        qtyOrdered: 2,
        depositQty: 2,
        transactionId: txId,
        transactionItemId: 'iA');
    await db.addPreorderEntry(
        id: 'pB',
        productId: 'P0',
        productUnitId: 'U0',
        customerName: 'Ari',
        qtyOrdered: 1,
        depositQty: 1,
        transactionId: txId,
        transactionItemId: 'iB');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.textContaining('Titip 2', findRichText: true), findsOneWidget,
        reason: 'baris asli harus menampilkan jaminan entri-nya sendiri (2)');
    expect(find.textContaining('Titip 1', findRichText: true), findsOneWidget,
        reason: 'baris Tambahan menampilkan jaminan entri-nya sendiri (1)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
