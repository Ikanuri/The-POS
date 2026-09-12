import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Tombol "Penuhi" langsung di kartu Pre-order layar nota (permintaan user:
/// "malas buka laci meja misal, jadi langsung tap ... penuhi di card in app
/// struknya") — meniru alur "Penuhi" di `laci_meja_dashboard_screen.dart`.
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

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

  testWidgets(
      'sisa > 1: tap Penuhi -> dialog qty muncul, konfirmasi parsial -> '
      'fulfillPreorderQty dgn jumlah yg benar', (tester) async {
    await db.addPreorderEntry(
        id: 'p1',
        productId: 'P0',
        productUnitId: 'U0',
        customerName: 'Warung Sari',
        qtyOrdered: 5,
        depositQty: 0,
        transactionId: txId);

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Penuhi'), findsOneWidget);
    await tester.tap(find.text('Penuhi'));
    await tester.pumpAndSettle();

    // Dialog qty muncul, prefill seluruh sisa (5).
    expect(find.text('Penuhi — Gas LPG 3kg'), findsOneWidget);
    expect(find.widgetWithText(TextField, ''), findsNothing);

    final field = find.byType(TextField);
    await tester.enterText(field, '3');
    await tester.tap(find.widgetWithText(FilledButton, 'Penuhi'));
    await tester.pumpAndSettle();

    final entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('p1')))
        .getSingle();
    final events = (await db.getLaciMejaEventsForEntries(['p1']))['p1'] ?? [];
    final terpenuhi = events
        .where((e) => e.aksi != 'batal')
        .fold<double>(0, (s, e) => s + e.qty);

    expect(terpenuhi, 3, reason: 'fulfillPreorderQty dipanggil dgn 3, bukan 5');
    expect(entry.fulfilledAt, isNull,
        reason: 'baru sebagian, belum selesai sepenuhnya');
    expect(find.textContaining('Sisa 2 belum dipenuhi'), findsOneWidget,
        reason: 'kartu langsung refresh menampilkan sisa terbaru');

    await drain(tester);
  });

  testWidgets(
      'sisa <= 1: tap Penuhi -> langsung fulfillPreorderEntry tanpa dialog',
      (tester) async {
    await db.addPreorderEntry(
        id: 'p1',
        productId: 'P0',
        productUnitId: 'U0',
        customerName: 'Warung Sari',
        qtyOrdered: 1,
        depositQty: 0,
        transactionId: txId);

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.text('Penuhi'));
    await tester.pumpAndSettle();

    // Tidak ada dialog qty — langsung selesai.
    expect(find.text('Penuhi — Gas LPG 3kg'), findsNothing);
    final entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(entry.fulfilledAt, isNotNull);
    expect(find.textContaining('Selesai — sudah dipenuhi'), findsOneWidget);

    await drain(tester);
  });

  testWidgets(
      'entri dgn DP/jaminan tertunda -> setelah dipenuhi, sheet DP/jaminan '
      'ditawarkan', (tester) async {
    // Item nota "lunas" (priceAtSale = originalPrice) tapi DP pre-order ini
    // sendiri belum masuk -> `getPreorderDepositOwed` akan > 0 setelah harga
    // dikunci Rp 0 di baris nota (originalPrice > priceAtSale).
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 0,
        originalPrice: 15000,
        subtotal: 0));
    await db.addPreorderEntry(
        id: 'p1',
        productId: 'P0',
        productUnitId: 'U0',
        customerName: 'Warung Sari',
        qtyOrdered: 1,
        depositQty: 0,
        transactionId: txId,
        transactionItemId: 'i1');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.text('Penuhi'));
    await tester.pumpAndSettle();

    // Sheet DP/jaminan ditawarkan dgn judul yg sesuai.
    expect(find.textContaining('DP/Jaminan — Gas LPG 3kg'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('entri Dibatalkan tidak menampilkan tombol Penuhi',
      (tester) async {
    await db.addPreorderEntry(
        id: 'p1',
        productId: 'P0',
        productUnitId: 'U0',
        customerName: 'Warung Sari',
        qtyOrdered: 5,
        depositQty: 0,
        transactionId: txId);
    await db.cancelPreorderEntry('p1');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Penuhi'), findsNothing);
    expect(find.text('✓ Dibatalkan'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('entri sudah Selesai (sudah dipenuhi) tidak menampilkan tombol Penuhi',
      (tester) async {
    await db.addPreorderEntry(
        id: 'p1',
        productId: 'P0',
        productUnitId: 'U0',
        customerName: 'Warung Sari',
        qtyOrdered: 2,
        depositQty: 0,
        transactionId: txId);
    await db.fulfillPreorderEntry('p1');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Penuhi'), findsNothing);
    expect(find.textContaining('Selesai — sudah dipenuhi'), findsOneWidget);

    await drain(tester);
  });

  testWidgets(
      'kartu Pinjaman/Titip TIDAK terpengaruh — tetap tanpa tombol Penuhi',
      (tester) async {
    await db.addBorrowedItem(
        id: 'b1', transactionId: txId, itemName: 'Krat botol', qty: 4);
    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: txId,
        itemName: 'Payung',
        jenis: 'titip',
        qty: 2);

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Penuhi'), findsNothing);
    expect(find.text('Pinjaman Barang'), findsOneWidget);
    expect(find.text('Titip/Ketinggalan (di luar nota)'), findsOneWidget);

    await drain(tester);
  });
}
