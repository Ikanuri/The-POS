import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Item 52 ("Laci Meja") — tombol "+ Catat" di app bar Struk: satu ikon
/// gabungan (BUKAN dua ikon terpisah, app bar sudah padat), pilihan jenis
/// (Titip/Ketinggalan atau Pinjaman Barang) muncul di bottom sheet. Kedua
/// kategori SELALU menumpang transaksi yang sedang dibuka (transactionId),
/// bukan bikin nota terpisah.
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000));
  });
  tearDown(() async => db.close());

  testWidgets(
      'catat Titip/Ketinggalan dari struk -> tersimpan dgn transactionId '
      'nota yang sedang dibuka, locallyModified=false (device owner)',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    expect(find.text('Titip/Ketinggalan'), findsOneWidget);
    expect(find.text('Pinjaman Barang'), findsOneWidget);

    await tester.tap(find.text('Titip/Ketinggalan'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Nama barang'), 'Payung');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.transactionId, txId);
    expect(rows.single.itemName, 'Payung');
    expect(rows.single.jenis, 'titip');
    expect(rows.single.locallyModified, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'catat Pinjaman Barang dari struk -> tersimpan dgn qty benar',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pinjaman Barang'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Nama barang'), 'Galon Aqua');
    await tester.enterText(find.widgetWithText(TextField, 'Jumlah'), '3');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.borrowedItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.itemName, 'Galon Aqua');
    expect(rows.single.qty, 3);
    expect(rows.single.transactionId, txId);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'device NON-OWNER (kasir) mencatat -> locallyModified=true (menunggu '
      'approve owner, pola sama spt usulan produk Item 40)', (tester) async {
    await pumpWithFakeApp(
      tester,
      db: db,
      child: const ReceiptScreen(transactionId: txId),
      device: const DeviceIdentity(
        storeUuid: 'test-store-uuid',
        storeKey: 'test-store-key',
        storeName: 'Toko Uji',
        deviceName: 'Kasir Uji',
        deviceCode: 'K2',
        deviceRole: 'kasir',
      ),
    );

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Titip/Ketinggalan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nama barang'), 'Payung');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.locallyModified, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
