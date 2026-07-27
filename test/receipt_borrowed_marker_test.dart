import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Item 52 redesain (permintaan user) — struk in-app memberi penanda
/// "Pinjaman" di samping nama barang yang tertaut ke `BorrowedItem` aktif
/// dari nota ini, sbg "rujukan kebenaran" (staf bisa cek nota asli utk
/// konfirmasi barang apa yang memang dipinjamkan). Tautan PRESISI lewat
/// `transactionItemId` (pola sama `LeftBehindItems`/`getLeftBehindMarksFor
/// Transaction`), BUKAN cocok-nama.
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
        ProductsCompanion.insert(id: 'P0', name: 'Galon Aqua'));
    // Produk SAMA, 2 baris satuan berbeda di nota yg sama — penanda WAJIB
    // hanya kena baris yang benar (pola sama kasus Titip/Ketinggalan).
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i-satu',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U-satu',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i-dus',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U-dus',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: txId, amount: 20000, method: 'tunai'));
  });
  tearDown(() async => db.close());

  testWidgets(
      'baris yang tertaut BorrowedItem menampilkan " · Pinjaman"; baris '
      'produk sama satuan lain TIDAK ikut tertandai', (tester) async {
    await db.addBorrowedItem(
        id: 'b1',
        transactionId: txId,
        itemName: 'Galon Aqua',
        qty: 1,
        transactionItemId: 'i-satu');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.textContaining('Pinjaman', findRichText: true), findsOneWidget,
        reason: 'tepat SATU baris tertandai, bukan dua (produk sama, '
            'satuan beda) — tautan lewat transactionItemId, bukan nama');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'baris TANPA pinjaman tidak menampilkan penanda apa pun', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.textContaining('Pinjaman', findRichText: true), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'penanda "Pinjaman" TETAP tampil walau barangnya SUDAH kembali penuh '
      '(rujukan kebenaran historis, bukan status hidup)', (tester) async {
    await db.addBorrowedItem(
        id: 'b1',
        transactionId: txId,
        itemName: 'Galon Aqua',
        qty: 1,
        transactionItemId: 'i-satu');
    await db.returnBorrowedItemQty('b1', 1);

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.textContaining('Pinjaman', findRichText: true), findsOneWidget,
        reason: 'nota adalah bukti historis, penanda tidak boleh hilang '
            'begitu barang dikembalikan');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
