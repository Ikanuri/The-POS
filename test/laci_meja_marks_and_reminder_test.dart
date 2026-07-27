import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';
import 'package:the_pos/features/laci_meja/laci_meja_reminder.dart';

import 'helpers/pump_app.dart';

/// Item 52 susulan (permintaan user):
/// - #3 struk in-app memberi PENANDA per-barang utk yang dititip/ketinggalan
///   (pola sama dgn badge "Habis" di katalog kasir).
/// - #4 pengingat Laci Meja (mirip pengingat hutang, tapi aksen sendiri)
///   supaya barang titipan/pinjaman/pre-order tidak terlupa.
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
        ProductsCompanion.insert(id: 'P0', name: 'Kopi Sachet'));
    // Produk SAMA, dua satuan berbeda — persis pola data toko user
    // ("234 12 Edisi" Pak & Slop). Penanda WAJIB hanya kena baris yang benar.
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i-pak',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U-pak',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i-slop',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U-slop',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000));
  });
  tearDown(() async => db.close());

  testWidgets(
      'struk in-app menandai HANYA baris yang benar-benar dititip — produk '
      'sama dgn satuan lain di nota yang sama TIDAK ikut tertandai',
      (tester) async {
    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: txId,
        itemName: 'Kopi Sachet',
        jenis: 'titip',
        transactionItemId: 'i-pak');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Dititip'), findsOneWidget,
        reason: 'tepat SATU baris tertandai, bukan dua (produk sama, '
            'satuan beda) — tautan lewat transactionItemId, bukan nama');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('jenis ketinggalan memakai label sendiri', (tester) async {
    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: txId,
        itemName: 'Kopi Sachet',
        jenis: 'ketinggalan',
        transactionItemId: 'i-slop');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Ketinggalan'), findsOneWidget);
    expect(find.text('Dititip'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('entri yang SUDAH diambil tidak lagi diberi penanda',
      (tester) async {
    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: txId,
        itemName: 'Kopi Sachet',
        jenis: 'titip',
        transactionItemId: 'i-pak');
    await db.markLeftBehindCollected('l1');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Dititip'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  group('pengingat (#4)', () {
    test('ringkasan hanya menyebut kategori yang memang ada isinya', () {
      expect(
          LaciMejaReminder.summaryOf(
              (titip: 2, ketinggalan: 0, pinjaman: 0, preorder: 1)),
          '2 barang dititip · 1 pre-order menunggu');
      expect(
          LaciMejaReminder.summaryOf(
              (titip: 0, ketinggalan: 0, pinjaman: 0, preorder: 0)),
          isNull,
          reason: 'tidak ada yang menggantung -> pengingat tidak muncul');
      expect(LaciMejaReminder.summaryOf(null), isNull);
    });

    test(
        'jenis titip & ketinggalan WAJIB jadi klausa terpisah, bukan '
        'digabung selalu tertulis "dititip" (bug dilaporkan user)', () {
      expect(
          LaciMejaReminder.summaryOf(
              (titip: 0, ketinggalan: 3, pinjaman: 0, preorder: 0)),
          '3 barang ketinggalan',
          reason: 'barang yang jenisnya ketinggalan TIDAK BOLEH tertulis '
              '"dititip"');
      expect(
          LaciMejaReminder.summaryOf(
              (titip: 1, ketinggalan: 2, pinjaman: 0, preorder: 0)),
          '1 barang dititip · 2 barang ketinggalan');
    });

    test('query per-pelanggan TERDAFTAR hanya menghitung yang menggantung',
        () async {
      await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'c1', name: 'Bu Sari'));
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: txId,
          itemName: 'A',
          jenis: 'titip',
          customerId: 'c1');
      await db.addLeftBehindItem(
          id: 'l2',
          transactionId: txId,
          itemName: 'B',
          jenis: 'titip',
          customerId: 'c1');
      await db.markLeftBehindCollected('l2');
      await db.addBorrowedItem(
          id: 'b1',
          transactionId: txId,
          itemName: 'Galon',
          qty: 1,
          customerId: 'c1');

      final p = await db.getLaciMejaPendingForCustomer('c1');
      expect(p.titip, 1, reason: 'yang sudah diambil tidak dihitung');
      expect(p.pinjaman, 1);
    });

    test('query per-pelanggan membedakan jenis titip vs ketinggalan',
        () async {
      await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'c2', name: 'Pak Joko'));
      await db.addLeftBehindItem(
          id: 'l3',
          transactionId: txId,
          itemName: 'Payung',
          jenis: 'ketinggalan',
          customerId: 'c2');
      await db.addLeftBehindItem(
          id: 'l4',
          transactionId: txId,
          itemName: 'Botol',
          jenis: 'titip',
          customerId: 'c2');

      final p = await db.getLaciMejaPendingForCustomer('c2');
      expect(p.titip, 1);
      expect(p.ketinggalan, 1);
    });

    test(
        'query per-NAMA (pembeli tak terdaftar) ikut menghitung pre-order '
        '— Pre-order memang hanya menyimpan nama', () async {
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'prod1',
          productUnitId: 'unit1',
          customerName: 'Pak Budi',
          qtyOrdered: 1);
      await db.addPreorderEntry(
          id: 'p2',
          productId: 'prod1',
          productUnitId: 'unit1',
          customerName: 'Pak Budi',
          qtyOrdered: 1);
      await db.cancelPreorderEntry('p2');

      final p = await db.getLaciMejaPendingForName('Pak Budi');
      expect(p.preorder, 1, reason: 'yang dibatalkan tidak dihitung');

      final kosong = await db.getLaciMejaPendingForName('');
      expect(kosong.preorder, 0);
    });
  });

  testWidgets('kartu pengingat memakai warna Laci Meja, bukan merah hutang',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LaciMejaReminder(
            pending:
                (titip: 1, ketinggalan: 0, pinjaman: 0, preorder: 0)),
      ),
    ));
    expect(find.textContaining('Laci Meja: 1 barang dititip'), findsOneWidget);

    final scheme = ThemeData.light().colorScheme;
    final box = tester.widget<Container>(find.byType(Container).first);
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, isNot(scheme.errorContainer),
        reason: 'aksen WAJIB beda dari pengingat hutang supaya tidak '
            'tertukar maknanya');
  });
}
