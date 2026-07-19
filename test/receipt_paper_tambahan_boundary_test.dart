import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Permintaan user (Gaya A): struk gambar (_ReceiptPaper, tombol "Bagikan
/// Struk") menyisipkan pembatas "----- Tambahan HH:MM -----" sebelum batch
/// barang yang ditambah lewat Tambah Belanjaan — seperti struk in-app.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seed() async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 40000,
          paid: 40000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    // Barang awal (addedAt null).
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: 'tx1',
        productId: 'Beras',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 30000,
        originalPrice: 30000,
        subtotal: 30000));
    // Barang susulan (addedAt 09:19).
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: 'tx1',
        productId: 'BawangPutih',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000,
        addedAt: Value(DateTime(2026, 7, 18, 9, 19))));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: 'tx1', amount: 40000, method: 'tunai'));
  }

  testWidgets(
      'struk gambar menyisipkan "----- Tambahan 09:19 -----" sebelum barang '
      'susulan, TIDAK sebelum barang awal', (tester) async {
    await seed();
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    expect(find.text('----- Tambahan 09:19 -----'), findsOneWidget,
        reason: 'satu pembatas untuk batch susulan');

    // Pembatas harus muncul DI ANTARA barang awal (Beras) dan susulan
    // (BawangPutih) di dalam struk gambar. Nama produk juga ada di daftar
    // on-screen di baliknya — ambil `.last` (salinan _ReceiptPaper, dirender
    // di overlay paling akhir).
    final sepY =
        tester.getTopLeft(find.text('----- Tambahan 09:19 -----')).dy;
    expect(sepY, greaterThan(tester.getTopLeft(find.text('Beras').last).dy),
        reason: 'pembatas di bawah barang awal');
    expect(
        sepY, lessThan(tester.getTopLeft(find.text('BawangPutih').last).dy),
        reason: 'pembatas di atas barang susulan');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('tanpa barang susulan → tidak ada pembatas sama sekali',
      (tester) async {
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
        id: 'a0',
        transactionId: 'tx2',
        productId: 'Beras',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 30000,
        originalPrice: 30000,
        subtotal: 30000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'p0', transactionId: 'tx2', amount: 30000, method: 'tunai'));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx2'));
    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tambahan'), findsNothing,
        reason: 'transaksi tanpa item susulan tidak punya pembatas');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
