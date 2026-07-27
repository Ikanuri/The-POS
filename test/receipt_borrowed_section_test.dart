import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Permintaan user: pinjaman barang kembali PLAIN TEXT (nama bebas ketik),
/// karena yang dipinjamkan biasanya WADAH (galon/tabung kosong) yang justru
/// BUKAN baris di nota. Konsekuensinya penanda di struk tidak bisa nempel
/// per-baris produk lagi — diganti SECTION "Pinjaman Barang" tersendiri,
/// yang tetap memenuhi maksud "rujukan kebenaran".
void main() {
  late AppDatabase db;
  const txId = 'tx1';

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
      'section "Pinjaman Barang" menampilkan barang yg dipinjamkan lewat nota '
      'ini, walau namanya BUKAN produk di nota', (tester) async {
    await db.addBorrowedItem(
      id: 'b1',
      transactionId: txId,
      // Sengaja nama yang TIDAK ada di nota — inti dari kembali ke plain text.
      itemName: 'Tabung kosong 3kg',
      qty: 1,
    );

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Pinjaman Barang'), findsOneWidget,
        reason: 'judul section muncul');
    expect(find.textContaining('Tabung kosong 3kg'), findsOneWidget,
        reason: 'barang pinjaman tampil walau bukan baris nota');
    expect(find.textContaining('belum kembali'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('nota tanpa pinjaman TIDAK menampilkan section sama sekali',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Pinjaman Barang'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'section TETAP tampil walau barangnya SUDAH kembali penuh (nota = '
      'bukti historis, bukan status hidup)', (tester) async {
    await db.addBorrowedItem(
        id: 'b1', transactionId: txId, itemName: 'Tabung kosong', qty: 1);
    await db.returnBorrowedItemQty('b1', 1);

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Pinjaman Barang'), findsOneWidget);
    expect(find.textContaining('sudah kembali'), findsOneWidget,
        reason: 'statusnya berubah, tapi catatannya tidak hilang');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'keterangan jaminan pre-order TIDAK hilang dari nota setelah pre-order '
      'DIPENUHI (permintaan user)', (tester) async {
    await db.addPreorderEntry(
      id: 'p1',
      productId: 'P0',
      productUnitId: 'U0',
      customerName: 'Bu Artia',
      qtyOrdered: 1,
      depositQty: 2,
      transactionId: txId,
    );

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));
    expect(find.textContaining('Titip 2', findRichText: true), findsOneWidget,
        reason: 'prakondisi: jaminan tampil sebelum dipenuhi');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));

    // Penuhi pre-order-nya, lalu buka ulang nota yang sama.
    await db.fulfillPreorderEntry('p1');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));
    expect(find.textContaining('Titip 2', findRichText: true), findsOneWidget,
        reason: 'jaminan WAJIB tetap tercatat di nota walau pre-order sudah '
            'dipenuhi — nota adalah bukti historis permanen');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
