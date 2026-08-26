import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// PLAN.md Item 54 poin 2 — riwayat + timestamp per nota utk KETIGA kategori
/// Laci Meja. Sebelumnya: kartu titipan & pinjaman sudah ada tapi TANPA
/// timestamp, dan pre-order tidak punya kartu sama sekali di layar nota.
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  String fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 20000,
          paid: 20000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P0', name: 'Gas LPG 3kg'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U0', productId: 'P0'));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 20000,
        originalPrice: 20000,
        subtotal: 20000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: txId, amount: 20000, method: 'tunai'));
  });
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('Pinjaman: waktu dipinjam + tiap momen pengembalian tampil, '
      'lengkap dgn sisa', (tester) async {
    await db.addBorrowedItem(
        id: 'b1', transactionId: txId, itemName: 'Krat botol', qty: 4);
    await db.returnBorrowedItemQty('b1', 3, eventId: 'e1');

    final entry = await (db.select(db.borrowedItems)
          ..where((t) => t.id.equals('b1')))
        .getSingle();
    final ev = (await db.getLaciMejaEventsForEntries(['b1']))['b1']!.single;

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.textContaining('Dipinjam ${fmt(entry.createdAt)}'),
        findsOneWidget,
        reason: 'waktu pencatatan tampil, bukan cuma nama barang');
    expect(find.textContaining(fmt(ev.createdAt)), findsWidgets,
        reason: 'tiap momen pengembalian punya barisnya sendiri');
    expect(find.text('Kembali'), findsOneWidget);
    expect(find.textContaining('Sisa 1 belum kembali'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('Titip/Ketinggalan: waktu dicatat + momen pengambilan, '
      'status Selesai saat sudah diambil semua', (tester) async {
    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: txId,
        itemName: 'Payung',
        jenis: 'titip',
        qty: 2);
    await db.collectLeftBehindQty('l1', 2, total: 2, eventId: 'e1');

    final entry = await (db.select(db.leftBehindItems)
          ..where((t) => t.id.equals('l1')))
        .getSingle();

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.textContaining('Dititip ${fmt(entry.createdAt)}'),
        findsOneWidget);
    expect(find.text('Diambil'), findsOneWidget);
    expect(find.textContaining('Selesai — sudah diambil'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('Pre-order: kartu BARU di nota (dulu tidak ada sama sekali), '
      'dgn nama produk, waktu pesan, & sisa belum dipenuhi', (tester) async {
    await db.addPreorderEntry(
        id: 'p1',
        productId: 'P0',
        productUnitId: 'U0',
        customerName: 'Warung Sari',
        qtyOrdered: 5,
        depositQty: 2,
        transactionId: txId);
    await db.fulfillPreorderQty('p1', 3, eventId: 'e1');

    final entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('p1')))
        .getSingle();

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Pre-order'), findsOneWidget,
        reason: 'judul kartu pre-order di nota');
    expect(find.textContaining('5 Gas LPG 3kg'), findsOneWidget,
        reason: 'nama produk di-resolve, bukan UUID mentah');
    expect(find.textContaining('2 jaminan'), findsOneWidget);
    expect(find.textContaining('Dipesan ${fmt(entry.createdAt)}'),
        findsOneWidget);
    expect(find.text('Dipenuhi'), findsOneWidget);
    expect(find.textContaining('Sisa 2 belum dipenuhi'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('nota tanpa pre-order TIDAK menampilkan kartunya', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Pre-order'), findsNothing);

    await drain(tester);
  });
}
