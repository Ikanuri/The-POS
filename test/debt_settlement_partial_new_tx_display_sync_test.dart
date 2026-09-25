import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/printer_service.dart';
import 'package:the_pos/core/theme/app_theme.dart' show formatRupiah;
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Item 85 (checkout boleh sebagian lunas kalau uang cukup lunasi hutang
/// tapi tidak cukup utk belanja baru, `c6146cf`) — susulan permintaan user:
/// buktikan langsung (bukan cuma kesimpulan logis dari `buildPrabayarCheckout`
/// yang tidak diubah) bahwa skenario BARU ini (nota baru kurang_bayar +
/// debtSettlementDetail attached, nota lama ikut lunas) tampil KONSISTEN di
/// struk cetak ESC/POS & share/in-app (poin 2 permintaan user), DAN
/// tersinkron benar ke device lain (poin 3). Dibangun lewat
/// `saveTransactionWithDebtSettlements` PERSIS spt `_confirm()` di
/// `payment_screen.dart` memanggilnya — bukan insert manual — supaya jalur
/// produksi yang sesungguhnya ikut teruji, bukan cuma bentuk DB akhirnya.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  TestWidgetsFlutterBinding.ensureInitialized();

  /// Belanja Rp50.000 + hutang lama Rp30.000 (nota `old1`) = harus terima
  /// Rp80.000. Kasir cuma terima Rp45.000 (cukup utk hutang, KURANG utk
  /// belanja) — persis kasus yang diminta user. Sisa belanja: Rp35.000.
  Future<void> seedPartialSettlementCheckout() async {
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'cust1', name: 'Budi'));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'old1',
          localId: 'K1-1',
          status: 'tempo',
          total: 30000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: const Value('cust1'),
          createdAt: Value(DateTime.now().subtract(const Duration(days: 1))),
        ));

    await db.saveTransactionWithDebtSettlements(
      tx: TransactionsCompanion.insert(
        id: 'new1',
        localId: 'K1-2',
        status: 'kurang_bayar',
        total: 50000,
        paid: 15000,
        changeAmount: 0,
        paymentMethod: 'tunai',
      ),
      items: [
        TransactionItemsCompanion.insert(
          id: 'i1',
          transactionId: 'new1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 50000,
          originalPrice: 50000,
          subtotal: 50000,
        ),
      ],
      payments: [
        TransactionPaymentsCompanion.insert(
          id: 'pay1',
          transactionId: 'new1',
          amount: 15000,
          method: 'tunai',
        ),
      ],
      stockItems: const [],
      debtSettlements: [
        (
          customerName: 'Budi',
          amount: 30000,
          targets: [
            (
              invoiceId: 'old1',
              invoiceLocalId: 'K1-1',
              invoiceDate: DateTime.now().subtract(const Duration(days: 1)),
              amount: 30000,
            ),
          ],
          method: 'tunai',
          methodName: null,
        ),
      ],
      kasirId: 'K1',
    );
  }

  group('poin 2 — tampilan struk konsisten', () {
    test('cetak ESC/POS nota BARU: "Sisa" Rp35.000, TANPA "Kembali", baris '
        'Lunasi Nota tercetak', () async {
      await seedPartialSettlementCheckout();
      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('new1')))
          .getSingle();
      expect(tx.status, 'kurang_bayar', reason: 'prasyarat');
      expect(tx.paid, 15000, reason: 'prasyarat');
      final items = await (db.select(db.transactionItems)
            ..where((i) => i.transactionId.equals('new1')))
          .get();
      final payments = await db.getPaymentsForTx('new1');

      final bytes = await PrinterService.debugBuildBytes(
        tx: tx,
        items: items,
        productNames: const {'P1': 'Gula Pasir'},
        unitNames: const {'U1': 'Pcs'},
        customer: null,
        storeName: 'Toko Uji',
        storeAddress: '',
        storePhone: '',
        strukNote: null,
        payments: payments,
        settings: const PrinterSettings(),
      );
      final text = latin1.decode(bytes, allowInvalid: true);

      expect(text.contains('Kembali'), isFalse,
          reason: 'belum ada uang lebih (paid 15.000 < total 50.000) — '
              'TIDAK boleh ada baris Kembali fiktif');
      expect(text.contains('Sisa'), isTrue,
          reason: 'sisa belanja genuinely belum terbayar HARUS tercetak');
      // ESC/POS pakai koma sbg pemisah ribuan (beda dari in-app/share titik).
      expect(text.contains('35,000'), isTrue,
          reason: 'sisa = 50.000 (total belanja) - 15.000 (paid) = 35.000, '
              'BUKAN dikurangi/ditambah nominal hutang yg sudah dilunasi');
      expect(text.contains('Lunasi Nota #1'), isTrue,
          reason: 'baris pelunasan hutang tetap tercetak menyatu ke list '
              'item spt biasa (Item redesain ketiga) — TIDAK terpengaruh '
              'checkout jadi sebagian lunas');
    });

    test('cetak ESC/POS nota LAMA (sudah dilunasi): TIDAK ada baris "Sisa" '
        'lagi', () async {
      await seedPartialSettlementCheckout();
      final oldTx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('old1')))
          .getSingle();
      expect(oldTx.status, 'lunas',
          reason: 'prasyarat: hutang lama TETAP lunas penuh walau nota '
              'baru jadi kurang_bayar');
      final items = await (db.select(db.transactionItems)
            ..where((i) => i.transactionId.equals('old1')))
          .get();
      final payments = await db.getPaymentsForTx('old1');

      final bytes = await PrinterService.debugBuildBytes(
        tx: oldTx,
        items: items,
        productNames: const {},
        unitNames: const {},
        customer: null,
        storeName: 'Toko Uji',
        storeAddress: '',
        storePhone: '',
        strukNote: null,
        payments: payments,
        settings: const PrinterSettings(),
      );
      final text = latin1.decode(bytes, allowInvalid: true);

      expect(text.contains('Sisa'), isFalse,
          reason: 'nota lama sudah lunas penuh — tidak boleh ada sisa '
              'tersisa di struk cetaknya walau ditagih via pelunasan '
              'hutang dari nota lain');
    });

    testWidgets(
        'in-app & share (_ReceiptPaper) nota BARU: "Sisa Tagihan" Rp35.000, '
        'TANPA baris Kembalian', (tester) async {
      await seedPartialSettlementCheckout();
      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: 'new1'));
      await tester.pumpAndSettle();

      expect(find.text(formatRupiah(35000)), findsWidgets,
          reason: '"Sisa Tagihan" di ringkasan atas harus murni sisa item '
              'nota ini sendiri (50.000 - 15.000), TIDAK dipengaruhi '
              'nominal hutang yg sudah dilunasi');
      expect(find.textContaining('Kembalian Rp'), findsNothing,
          reason: 'belum ada uang lebih — TIDAK boleh ada baris '
              'Kembalian di Ringkasan atas');

      await tester.tap(find.byTooltip('Bagikan Struk'));
      await tester.pumpAndSettle();

      expect(find.text('Kembali'), findsNothing,
          reason: 'struk share/gambar TIDAK boleh menampilkan baris '
              'Kembali (tidak ada uang lebih)');
      expect(find.text('Sisa'), findsOneWidget,
          reason: 'struk share/gambar HARUS menampilkan baris Sisa');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  group('poin 3 — sync antar device tidak rusak', () {
    test(
        'host -> client: nota BARU (kurang_bayar) & nota LAMA (lunas + '
        'debtSettlementDetail) SAMA-SAMA sampai ke device lain', () async {
      await seedPartialSettlementCheckout();
      final clientDb = AppDatabase(NativeDatabase.memory());
      addTearDown(clientDb.close);

      final dump = await db.dumpSince(DateTime(2000));
      for (final table in [
        'transactions',
        'transaction_items',
        'transaction_payments',
        'customers',
      ]) {
        final rows = dump[table];
        if (rows == null) continue;
        await clientDb.mergeRows(table, rows, true);
      }

      final clientNew = await (clientDb.select(clientDb.transactions)
            ..where((t) => t.id.equals('new1')))
          .getSingle();
      expect(clientNew.status, 'kurang_bayar',
          reason: 'device lain harus melihat nota baru sbg kurang_bayar, '
              'bukan lunas/tempo palsu');
      expect(clientNew.paid, 15000);
      expect(clientNew.total, 50000);
      expect(clientNew.changeAmount, 0);
      expect(clientNew.debtSettlementDetail, isNotNull,
          reason: 'ringkasan pelunasan hutang harus ikut tersinkron ke '
              'device lain (bukan cuma tampil di device yg checkout)');
      final detail = jsonDecode(clientNew.debtSettlementDetail!) as List;
      expect(detail.single['amount'], 30000);

      final clientOld = await (clientDb.select(clientDb.transactions)
            ..where((t) => t.id.equals('old1')))
          .getSingle();
      expect(clientOld.status, 'lunas',
          reason: 'device lain harus melihat hutang lama SUDAH lunas — '
              'kalau tidak, kasir di device lain bisa menagih dobel');

      final clientPayments =
          await clientDb.getPaymentsForTx('new1');
      expect(clientPayments.fold<int>(0, (s, p) => s + p.amount), 15000);
    });

    test(
        'watermark KEDUA (device lain sudah sync SEBELUM checkout ini) -> '
        'perubahan nota LAMA (jadi lunas) tetap ikut dump susulan',
        () async {
      // Sync PERTAMA: device lain sudah lebih dulu tahu nota lama (masih
      // tempo) SEBELUM checkout gabungan (hutang+belanja) terjadi -- kasus
      // paling umum di lapangan (nota hutang sudah lama ada & tersinkron,
      // baru BELAKANGAN pelanggan datang bayar+belanja sekaligus).
      await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'cust1', name: 'Budi'));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'old1',
            localId: 'K1-1',
            status: 'tempo',
            total: 30000,
            paid: 0,
            changeAmount: 0,
            paymentMethod: 'tunai',
            customerId: const Value('cust1'),
            createdAt:
                Value(DateTime.now().subtract(const Duration(days: 5))),
          ));

      final clientDb = AppDatabase(NativeDatabase.memory());
      addTearDown(clientDb.close);
      final firstDump = await db.dumpSince(DateTime(2000));
      await clientDb.mergeRows(
          'transactions', firstDump['transactions']!, true);
      var clientOld = await (clientDb.select(clientDb.transactions)
            ..where((t) => t.id.equals('old1')))
          .getSingle();
      expect(clientOld.status, 'tempo', reason: 'prasyarat sync pertama');

      final watermark = DateTime.now();
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      // Checkout gabungan (hutang+belanja sebagian) terjadi SETELAH sync
      // pertama -- persis skenario "kembalian tidak muncul" yg ditanyakan
      // user, dari sudut sync.
      await db.saveTransactionWithDebtSettlements(
        tx: TransactionsCompanion.insert(
          id: 'new1',
          localId: 'K1-2',
          status: 'kurang_bayar',
          total: 50000,
          paid: 15000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ),
        items: const [],
        payments: [
          TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: 'new1',
            amount: 15000,
            method: 'tunai',
          ),
        ],
        stockItems: const [],
        debtSettlements: [
          (
            customerName: 'Budi',
            amount: 30000,
            targets: [
              (
                invoiceId: 'old1',
                invoiceLocalId: 'K1-1',
                invoiceDate:
                    DateTime.now().subtract(const Duration(days: 5)),
                amount: 30000,
              ),
            ],
            method: 'tunai',
            methodName: null,
          ),
        ],
        kasirId: 'K1',
      );

      final secondDump = await db.dumpSince(watermark);
      final txDump = secondDump['transactions'] ?? const [];
      expect(txDump.any((r) => r['id'] == 'old1'), isTrue,
          reason: 'nota LAMA (created_at sudah lewat watermark) harus '
              'tetap ikut dump susulan krn updatedAt-nya baru dicap ulang '
              '-- kalau tidak, device lain TIDAK PERNAH tahu hutang itu '
              'sudah lunas');
      expect(txDump.any((r) => r['id'] == 'new1'), isTrue);

      for (final table in ['transactions', 'transaction_payments']) {
        final rows = secondDump[table];
        if (rows == null) continue;
        await clientDb.mergeRows(table, rows, true);
      }

      clientOld = await (clientDb.select(clientDb.transactions)
            ..where((t) => t.id.equals('old1')))
          .getSingle();
      expect(clientOld.status, 'lunas',
          reason: 'device lain HARUS ikut melihat hutang lama jadi lunas '
              'setelah sync susulan');
      final clientNew = await (clientDb.select(clientDb.transactions)
            ..where((t) => t.id.equals('new1')))
          .getSingle();
      expect(clientNew.status, 'kurang_bayar');
      expect(clientNew.paid, 15000);
    });
  });
}
