import 'package:drift/drift.dart' show Value;
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
///
/// Titip/Ketinggalan (koreksi user): WAJIB ditaut ke produk NYATA yang ada
/// di nota ini — UX-nya toggle centang barang mana yang titip/ketinggalan
/// (bisa lebih dari satu), BUKAN mengetik nama bebas.
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
        ProductsCompanion.insert(id: 'P0', name: 'Payung Lipat'));
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Topi'));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: 2,
        priceAtSale: 5000,
        originalPrice: 5000,
        subtotal: 10000));
  });
  tearDown(() async => db.close());

  testWidgets(
      'catat Titip/Ketinggalan dari struk -> toggle centang produk yang '
      'ada di nota (bukan ketik bebas), tersimpan dgn transactionId nota '
      'yang sedang dibuka, locallyModified=false (device owner)',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    expect(find.text('Titip/Ketinggalan'), findsOneWidget);
    expect(find.text('Pinjaman Barang'), findsOneWidget);

    await tester.tap(find.text('Titip/Ketinggalan'));
    await tester.pumpAndSettle();

    // Dua produk nota ini tampil sbg pilihan centang, bukan field teks.
    expect(find.text('Payung Lipat (1)'), findsOneWidget);
    expect(find.text('Topi (2)'), findsOneWidget);

    await tester.tap(find.text('Payung Lipat (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.transactionId, txId);
    expect(rows.single.itemName, 'Payung Lipat',
        reason: 'nama produk diambil dari nota, bukan diketik bebas');
    expect(rows.single.jenis, 'titip');
    expect(rows.single.locallyModified, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'toggle lebih dari satu produk -> masing-masing jadi baris '
      'LeftBehindItem terpisah', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Titip/Ketinggalan'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Payung Lipat (1)'));
    await tester.tap(find.text('Topi (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.itemName).toSet(), {'Payung Lipat', 'Topi'});

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'nama pelanggan DIWARISI dari nota (pra-isi & tersimpan), tidak perlu '
      'diketik ulang — supaya kartu dashboard Laci Meja menampilkan namanya',
      (tester) async {
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Bu Sari'));
    await (db.update(db.transactions)..where((t) => t.id.equals(txId)))
        .write(const TransactionsCompanion(
            customerId: Value('c1'), customerName: Value('Bu Sari')));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Titip/Ketinggalan'));
    await tester.pumpAndSettle();

    // Field pelanggan sudah PRA-ISI dari nota, staf tidak mengetik apa pun.
    expect(find.widgetWithText(TextField, 'Bu Sari'), findsOneWidget);

    await tester.tap(find.text('Payung Lipat (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.customerNameText, 'Bu Sari');
    expect(rows.single.customerId, 'c1',
        reason: 'ditaut ke pelanggan terdaftar dari nota, bukan cuma teks');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'catat Pinjaman Barang dari struk -> checklist barang nyata di nota, '
      'tersimpan dgn qty & transactionItemId benar', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pinjaman Barang'));
    await tester.pumpAndSettle();

    // Item 52 redesain — bukan lagi TextField nama bebas, tapi checklist
    // barang NYATA di nota ini (pola sama Titip/Ketinggalan) — dibutuhkan
    // supaya tertaut presisi ke baris nota (transactionItemId).
    expect(find.text('Payung Lipat (1)'), findsOneWidget);
    expect(find.text('Topi (2)'), findsOneWidget);

    await tester.tap(find.text('Topi (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.borrowedItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.itemName, 'Topi');
    expect(rows.single.qty, 2, reason: 'qty diambil dari qty produk di nota');
    expect(rows.single.transactionId, txId);
    expect(rows.single.transactionItemId, 'i1',
        reason: 'tertaut PRESISI ke baris nota, bukan cocok-nama');

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
    await tester.tap(find.text('Payung Lipat (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.locallyModified, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
