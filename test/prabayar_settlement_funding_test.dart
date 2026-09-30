import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart' show formatRupiah;
import 'package:the_pos/features/kasir/cart_debt_settlement_provider.dart';
import 'package:the_pos/features/kasir/cart_prabayar_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// Item 86 (laporan user) — hutang/pre-order yang ditambahkan ke keranjang
/// lalu dilunasi lewat Pra-Bayar TETAP ditagih ulang di layar Bayar: footer
/// keranjang menghitung Pra-Bayar thd total gabungan (belanja + hutang),
/// tapi layar Bayar (Item 65) cuma mengizinkan Pra-Bayar menutup belanja.
/// Sekarang pool Pra-Bayar ikut melunasi pelunasan (DIDAHULUKAN, prioritas
/// sama Item 85), porsinya dicatat HANYA di nota LAMA & dikeluarkan dari
/// baris Pra-Bayar nota BARU (anti hitung dobel Tutup Kasir).
void main() {
  PrabayarEntry pb(String id, int amount,
          {String method = 'tunai', int minutesAgo = 10}) =>
      PrabayarEntry(
        id: id,
        amount: amount,
        method: method,
        lockedAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      );

  group('planPrabayarSettlementFunding (fungsi murni)', () {
    test('pool menutup pelunasan DULU, dari entri PALING LAMA', () {
      final plan = planPrabayarSettlementFunding(
        prabayarEntries: [pb('a', 30000, minutesAgo: 20), pb('b', 70000)],
        changeTakenTotal: 0,
        targets: [(key: 'd:1', amount: 50000)],
        cashMethod: 'tunai',
      );
      expect(plan.poolToSettlement, 50000);
      expect(plan.entryAllocations, {'a': 30000, 'b': 20000});
      expect(plan.chunksByTarget['d:1'],
          [(amount: 50000, method: 'tunai', methodName: null)],
          reason: 'dua entri Pra-Bayar dgn metode SAMA digabung jadi satu '
              'pembayaran di nota lama');
    });

    test('pool kurang -> sisa target dibiayai uang sekarang (metode kasir)',
        () {
      final plan = planPrabayarSettlementFunding(
        prabayarEntries: [pb('a', 40000, method: 'qris')],
        changeTakenTotal: 0,
        targets: [(key: 'd:1', amount: 50000)],
        cashMethod: 'tunai',
      );
      expect(plan.poolToSettlement, 40000);
      expect(plan.chunksByTarget['d:1'], [
        (amount: 40000, method: 'qris', methodName: null),
        (amount: 10000, method: 'tunai', methodName: null),
      ]);
    });

    test('kembalian yg SUDAH diambil sebelum checkout tidak ikut dipakai '
        'melunasi', () {
      // Entri 100.000, kembalian 30.000 sudah diambil -> hanya 70.000 yg
      // masih ada di laci.
      final plan = planPrabayarSettlementFunding(
        prabayarEntries: [pb('a', 100000)],
        changeTakenTotal: 30000,
        targets: [(key: 'd:1', amount: 90000)],
        cashMethod: 'tunai',
      );
      expect(plan.poolToSettlement, 70000);
      expect(plan.entryAllocations, {'a': 70000});
    });

    test('buildPrabayarCheckout + alokasi: baris nota BARU cuma porsi belanja '
        '& invariant akuntansi tetap', () {
      final entries = [pb('a', 30000, minutesAgo: 20), pb('b', 70000)];
      final plan = planPrabayarSettlementFunding(
        prabayarEntries: entries,
        changeTakenTotal: 0,
        targets: [(key: 'd:1', amount: 50000)],
        cashMethod: 'tunai',
      );
      var i = 0;
      final r = buildPrabayarCheckout(
        txId: 'tx',
        cartTotal: 30000,
        prabayarEntries: entries,
        paidAmountNow: 0,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime.now(),
        kasirId: 'K1',
        genId: () => 'p${i++}',
        settlementAllocations: plan.entryAllocations,
      );
      // Entri 'a' habis terpakai pelunasan -> tidak ditulis sama sekali.
      expect(r.payments.length, 1);
      expect(r.payments.single.amount.value, 50000);
      expect(r.combinedPaid, 50000);
      expect(r.status, 'lunas');
      expect(r.combinedChange, 20000);
      final net = r.payments.fold<int>(
          0,
          (s, p) =>
              s +
              p.amount.value -
              p.changeGiven.value -
              (p.prabayarChangeTakenBeforeCheckout.present
                  ? (p.prabayarChangeTakenBeforeCheckout.value ?? 0)
                  : 0));
      expect(net, r.combinedPaid - r.combinedChange);
    });
  });

  group('layar Bayar + DB', () {
    const item = CartItem(
      productId: 'p1',
      productUnitId: 'u1',
      productName: 'Gula Pasir',
      unitName: 'Pcs',
      qty: 1,
      price: 30000,
      originalPrice: 30000,
      costPrice: 20000,
    );

    Future<AppDatabase> seedOldDebt() async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'cust1', name: 'Budi'));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'old1',
            localId: 'old1',
            status: 'tempo',
            total: 50000,
            paid: 0,
            changeAmount: 0,
            paymentMethod: 'tunai',
            customerId: const Value('cust1'),
            createdAt:
                Value(DateTime.now().subtract(const Duration(days: 1))),
          ));
      return db;
    }

    Future<void> pump(WidgetTester tester, AppDatabase db,
        {required List<PrabayarEntry> prabayar, int itemPrice = 30000}) async {
      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider.overrideWith((ref) => DeviceNotifier()
          ..state = const DeviceIdentity(
            storeUuid: 'test-store-uuid',
            storeKey: 'test-store-key',
            storeName: 'Toko Uji',
            deviceName: 'Kasir Uji',
            deviceCode: 'K1',
            deviceRole: 'owner',
          )),
      ]);
      addTearDown(container.dispose);
      container.read(cartProvider(kMainCartId).notifier).addItem(CartItem(
            productId: item.productId,
            productUnitId: item.productUnitId,
            productName: item.productName,
            unitName: item.unitName,
            qty: 1,
            price: itemPrice,
            originalPrice: itemPrice,
            costPrice: item.costPrice,
          ));
      container.read(cartDebtSettlementProvider(kMainCartId).notifier).add(
          DebtSettlementEntry(
            id: 'ds1',
            invoiceId: 'old1',
            invoiceLocalId: 'old1',
            invoiceDate: DateTime.now().subtract(const Duration(days: 1)),
            customerId: 'cust1',
            customerName: 'Budi',
            amount: 50000,
            createdAt: DateTime.now(),
          ));
      for (final e in prabayar) {
        container.read(cartPrabayarProvider(kMainCartId).notifier).add(e);
      }
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PaymentScreen()),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> drain(WidgetTester tester, AppDatabase db) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      await db.close();
    }

    Future<Transaction> newTx(AppDatabase db) =>
        (db.select(db.transactions)..where((t) => t.id.isNotValue('old1')))
            .getSingle();
    Future<Transaction> oldTx(AppDatabase db) =>
        (db.select(db.transactions)..where((t) => t.id.equals('old1')))
            .getSingle();

    testWidgets(
        'Pra-Bayar menutup belanja + hutang -> tombol "Selesaikan Transaksi" '
        'muncul; hutang lunas TANPA ditagih tunai lagi & tanpa hitung dobel',
        (tester) async {
      final db = await seedOldDebt();
      // Belanja 30.000 + hutang 50.000 = 80.000; Pra-Bayar 100.000.
      await pump(tester, db, prabayar: [pb('pb1', 100000)]);

      expect(find.text('Selesaikan Transaksi'), findsOneWidget,
          reason: 'tanpa fix: pool tidak pernah dianggap menutup hutang, '
              'layar Bayar tetap menagih Rp50.000 tunai');
      await tester.tap(find.text('Selesaikan Transaksi'));
      await tester.pumpAndSettle();

      final nt = await newTx(db);
      expect(nt.total, 30000);
      expect(nt.paid, 50000,
          reason: 'porsi hutang (50.000) keluar dari baris Pra-Bayar nota '
              'baru: 100.000 - 50.000');
      expect(nt.changeAmount, 20000);
      expect(nt.status, 'lunas');
      final ot = await oldTx(db);
      expect(ot.status, 'lunas');
      final oldPays = await db.getPaymentsForTx('old1');
      expect(oldPays.single.amount, 50000);

      final detail = jsonDecode(nt.debtSettlementDetail!) as List;
      expect(detail.single['amount'], 50000);

      // Anti hitung dobel: laci tunai hari ini = 100.000 masuk - 20.000
      // kembalian = 80.000 (bukan 130.000).
      final now = DateTime.now();
      final recap = await db.getTodayCashRecap(
          now.subtract(const Duration(days: 1)),
          now.add(const Duration(days: 1)));
      expect(recap.cash, 80000,
          reason: 'uang Pra-Bayar yang dipakai melunasi hutang TIDAK boleh '
              'tercatat di nota baru DAN nota lama sekaligus');

      await drain(tester, db);
    });

    testWidgets(
        'Pra-Bayar cuma menutup SEBAGIAN hutang: gerbang menuntut sisa hutang '
        'saja (bukan hutang penuh)', (tester) async {
      final db = await seedOldDebt();
      // Belanja 30.000, hutang 50.000, Pra-Bayar 40.000 -> sisa hutang
      // 10.000 wajib uang sekarang.
      await pump(tester, db, prabayar: [pb('pb1', 40000)]);

      expect(find.textContaining('Bayar ${formatRupiah(40000)}'),
          findsOneWidget);
      await tester.tap(find.textContaining('Bayar Rp'));
      await tester.pumpAndSettle();
      for (final d in ['5', '0', '0', '0']) {
        await tester.tap(find.text(d));
      }
      await tester.pump();
      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pumpAndSettle();

      expect(
          find.textContaining(
              'belum menutup pelunasan Hutang/Pre-order ${formatRupiah(10000)}'),
          findsOneWidget,
          reason: 'yang wajib ditutup uang sekarang cuma sisa hutang 10.000');
      expect(
          (await db.select(db.transactions).get())
              .where((t) => t.id != 'old1'),
          isEmpty);
      expect((await oldTx(db)).status, 'tempo');

      await drain(tester, db);
    });

    testWidgets(
        'Pra-Bayar sebagian + uang sekarang: hutang lunas (2 sumber dana), '
        'nota baru kurang_bayar utk sisa belanja', (tester) async {
      final db = await seedOldDebt();
      await pump(tester, db, prabayar: [pb('pb1', 40000)]);

      await tester.tap(find.textContaining('Bayar Rp'));
      await tester.pumpAndSettle();
      // 25.000: 10.000 menutup sisa hutang, 15.000 utk belanja 30.000.
      for (final d in ['2', '5', '0', '0', '0']) {
        await tester.tap(find.text(d));
      }
      await tester.pump();
      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pumpAndSettle();

      final ot = await oldTx(db);
      expect(ot.status, 'lunas');
      final oldPays = await db.getPaymentsForTx('old1');
      expect(oldPays.fold<int>(0, (s, p) => s + p.amount), 50000);

      final nt = await newTx(db);
      expect(nt.total, 30000);
      expect(nt.paid, 15000,
          reason: 'Pra-Bayar 40.000 habis ke hutang, sisa 15.000 dari uang '
              'sekarang');
      expect(nt.status, 'kurang_bayar');
      final newPays = await db.getPaymentsForTx(nt.id);
      expect(newPays.single.amount, 15000,
          reason: 'baris Pra-Bayar yang habis terpakai hutang tidak ditulis');
      final detail = jsonDecode(nt.debtSettlementDetail!) as List;
      expect(detail.length, 1,
          reason: 'dua sumber dana utk nota yg SAMA tetap satu baris struk');
      expect(detail.single['amount'], 50000);

      await drain(tester, db);
    });

    testWidgets(
        '"Bayar Nanti" aktif lagi kalau hutang SUDAH tertutup penuh '
        'Pra-Bayar (belanja boleh tempo)', (tester) async {
      final db = await seedOldDebt();
      await pump(tester, db, prabayar: [pb('pb1', 60000)], itemPrice: 100000);

      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Bayar Nanti'));
      expect(button.onPressed, isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Bayar Nanti'));
      await tester.pumpAndSettle();

      expect((await oldTx(db)).status, 'lunas');
      final nt = await newTx(db);
      expect(nt.paid, 10000, reason: 'sisa pool 60.000 - 50.000');
      expect(nt.status, 'kurang_bayar');

      await drain(tester, db);
    });
  });

  group('saveTransactionWithDebtSettlements: pre-order 2 sumber dana', () {
    test('DP dikumpulkan sekali, pembayaran ke-2 tetap tercatat, ringkasan '
        'satu baris', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.into(db.products)
          .insert(ProductsCompanion.insert(id: 'P1', name: 'LPG'));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'src',
            localId: 'src',
            status: 'lunas',
            total: 0,
            paid: 0,
            changeAmount: 0,
            paymentMethod: 'tunai',
            createdAt:
                Value(DateTime.now().subtract(const Duration(days: 2))),
          ));
      await db.into(db.transactionItems).insert(
          TransactionItemsCompanion.insert(
              id: 'ti',
              transactionId: 'src',
              productId: 'P1',
              productUnitId: 'U1',
              qty: 1,
              priceAtSale: 0,
              originalPrice: 30000,
              subtotal: 0));
      await db.addPreorderEntry(
          id: 'po1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Sari',
          qtyOrdered: 1,
          transactionId: 'src',
          transactionItemId: 'ti');

      ({
        String preorderEntryId,
        String invoiceId,
        String invoiceLocalId,
        DateTime invoiceDate,
        String customerName,
        int amount,
        String method,
        String? methodName,
        bool fulfillOnSettle,
      }) chunk(int amount, String method) => (
            preorderEntryId: 'po1',
            invoiceId: 'src',
            invoiceLocalId: 'src',
            invoiceDate: DateTime.now(),
            customerName: 'Sari',
            amount: amount,
            method: method,
            methodName: null,
            fulfillOnSettle: false,
          );

      await db.saveTransactionWithDebtSettlements(
        tx: TransactionsCompanion.insert(
          id: 'new',
          localId: 'new',
          status: 'lunas',
          total: 0,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ),
        items: const [],
        payments: const [],
        stockItems: const [],
        debtSettlements: const [],
        preorderSettlements: [chunk(20000, 'qris'), chunk(10000, 'tunai')],
        kasirId: 'K1',
      );

      final src = await (db.select(db.transactions)
            ..where((t) => t.id.equals('src')))
          .getSingle();
      expect(src.status, 'lunas');
      final pays = await db.getPaymentsForTx('src');
      expect(pays.map((p) => (p.amount, p.method)).toSet(),
          {(20000, 'qris'), (10000, 'tunai')});
      final po = await (db.select(db.preorderEntries)
            ..where((t) => t.id.equals('po1')))
          .getSingle();
      expect(po.paid, isTrue);
      final nt = await (db.select(db.transactions)
            ..where((t) => t.id.equals('new')))
          .getSingle();
      final detail = jsonDecode(nt.debtSettlementDetail!) as List;
      expect(detail.length, 1);
      expect(detail.single['amount'], 30000);
      expect(detail.single.containsKey('_key'), isFalse);
    });
  });
}
