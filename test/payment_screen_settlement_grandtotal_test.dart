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

/// Item 65 — bug nyata dilaporkan user: tombol "Bayar"/kalkulator tunai
/// (label, "Uang Pas", kembalian/kurang) pakai `_total` (belanja saja),
/// TIDAK termasuk `_debtSettlementTotal`/`_preorderSettlementTotal`, padahal
/// kasir harus menerima SATU nominal fisik gabungan sekali jalan. Ditambah:
/// pelunasan hutang/pre-order dijalankan TANPA SYARAT (nominalnya beku,
/// tidak pernah dicek ulang thd uang yg sungguhan diterima) — tanpa gerbang
/// baru ini, kasir bisa checkout dgn uang kurang dari semestinya sementara
/// hutang pelanggan lain tetap tercatat LUNAS.
void main() {
  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Gula Pasir',
    unitName: 'Pcs',
    qty: 1,
    price: 100000,
    originalPrice: 100000,
    costPrice: 60000,
  );

  Future<AppDatabase> seedOldDebtTx(String txId, {int total = 50000}) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'cust1', name: 'Budi'));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: txId,
          status: 'tempo',
          total: total,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: const Value('cust1'),
          createdAt: Value(DateTime.now().subtract(const Duration(days: 1))),
        ));
    return db;
  }

  Future<ProviderContainer> pumpPaymentWithDebtEntry(
      WidgetTester tester, AppDatabase db,
      {required int debtAmount, required String sourceTxId}) async {
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
    container.read(cartProvider(kMainCartId).notifier).addItem(item);
    container.read(cartDebtSettlementProvider(kMainCartId).notifier).add(
        DebtSettlementEntry(
          id: 'ds1',
          invoiceId: sourceTxId,
          invoiceLocalId: sourceTxId,
          invoiceDate: DateTime.now().subtract(const Duration(days: 1)),
          customerId: 'cust1',
          customerName: 'Budi',
          amount: debtAmount,
          createdAt: DateTime.now(),
        ));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PaymentScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets(
      'ada entri Lunasi Hutang: label "Bayar" & Total di kalkulator = '
      'GRAND TOTAL (belanja + hutang), bukan belanja saja', (tester) async {
    final db = await seedOldDebtTx('old1');
    await pumpPaymentWithDebtEntry(tester, db,
        debtAmount: 50000, sourceTxId: 'old1');

    // Total belanja 100.000 + hutang 50.000 = 150.000. `formatRupiah` pakai
    // non-breaking space (U+00A0) antara "Rp" & angka — literal spasi biasa
    // TIDAK match walau tampil identik di layar (lihat gotcha CLAUDE.md).
    final grandTotalLabel = formatRupiah(150000);
    expect(find.textContaining('Bayar $grandTotalLabel'), findsOneWidget,
        reason: 'label tombol Bayar HARUS grand total, sebelumnya cuma '
            'menampilkan belanja (${formatRupiah(100000)})');

    await tester.tap(find.textContaining('Bayar $grandTotalLabel'));
    await tester.pumpAndSettle();

    expect(find.textContaining(grandTotalLabel), findsWidgets,
        reason: 'header "Total" di kalkulator HARUS grand total juga');

    await tester.tap(find.text('Uang Pas'));
    await tester.pump();
    expect(find.text(grandTotalLabel), findsWidgets,
        reason: '"Uang Pas" HARUS mengisi grand total, bukan belanja saja');

    await drain(tester);
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'ketik uang KURANG dari grand total (cuma cukup belanja) -> checkout '
      'DITOLAK, tidak ada transaksi baru & hutang lama TETAP tempo',
      (tester) async {
    final db = await seedOldDebtTx('old2');
    await pumpPaymentWithDebtEntry(tester, db,
        debtAmount: 50000, sourceTxId: 'old2');

    await tester.tap(find.textContaining('Bayar Rp'));
    await tester.pumpAndSettle();

    // Ketik PERSIS 100.000 (cukup utk belanja SENDIRI, TIDAK cukup utk
    // grand total 150.000) lalu tap tombol konfirmasi di kalkulator.
    for (final d in ['1', '0', '0', '0', '0', '0']) {
      await tester.tap(find.text(d));
    }
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pumpAndSettle();

    // Sheet kalkulatornya sendiri SELALU tertutup begitu tombol
    // konfirmasinya ditap (itu Navigator.pop biasa) — gerbang barunya ada
    // di LUAR sheet (`_onBayarPressed`, SETELAH nilai kembali), jadi yang
    // dibuktikan di sini BUKAN sheet tetap terbuka, tapi checkout-nya
    // sendiri yang batal (tidak ada transaksi tersimpan) + peringatan.
    expect(find.textContaining('belum menutup Total Diterima'), findsOneWidget,
        reason: 'checkout harus ditolak dgn peringatan krn uang blm '
            'menutup grand total, bukan lanjut diam-diam ke _confirm()');

    final txs = await db.select(db.transactions).get();
    expect(txs.where((t) => t.id != 'old2'), isEmpty,
        reason: 'tidak boleh ada transaksi BARU tersimpan');
    final old = await (db.select(db.transactions)
          ..where((t) => t.id.equals('old2')))
        .getSingle();
    expect(old.status, 'tempo',
        reason: 'hutang lama TIDAK BOLEH ikut tercatat lunas kalau uang '
            'yang diterima kasir belum cukup');

    await drain(tester);
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'ketik uang PAS grand total -> checkout sukses: nota baru total/paid '
      'HANYA belanja, hutang lama ikut lunas', (tester) async {
    final db = await seedOldDebtTx('old3');
    await pumpPaymentWithDebtEntry(tester, db,
        debtAmount: 50000, sourceTxId: 'old3');

    await tester.tap(find.textContaining('Bayar Rp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uang Pas'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pumpAndSettle();

    final newTx = await (db.select(db.transactions)
          ..where((t) => t.id.isNotValue('old3')))
        .getSingle();
    expect(newTx.total, 100000,
        reason: 'nota BARU cuma mencatat belanja, TIDAK diinflasi hutang');
    expect(newTx.paid, 100000);

    final old = await (db.select(db.transactions)
          ..where((t) => t.id.equals('old3')))
        .getSingle();
    expect(old.status, 'lunas',
        reason: 'hutang lama ikut lunas krn uang yg diterima sudah cukup');

    await drain(tester);
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'Pra-Bayar SENDIRI cukup menutup belanja DAN ada entri Lunasi Hutang '
      'AKTIF: tombol pintas "Selesaikan Transaksi" TIDAK ditawarkan -- '
      'WAJIB tetap lewat kalkulator supaya uang pelunasan hutang benar2 '
      'diterima', (tester) async {
    final db = await seedOldDebtTx('old4');
    final container = await pumpPaymentWithDebtEntry(tester, db,
        debtAmount: 50000, sourceTxId: 'old4');
    // Pra-Bayar 100.000 -- PAS menutup belanja (100.000) SENDIRI, TANPA
    // gerbang baru ini tombol pintas akan tampil & meloloskan checkout
    // tanpa kasir pernah menerima uang tambahan utk hutang 50.000.
    container.read(cartPrabayarProvider(kMainCartId).notifier).add(
        PrabayarEntry(
          id: 'pb1',
          amount: 100000,
          method: 'tunai',
          lockedAt: DateTime.now(),
        ));
    await tester.pumpAndSettle();

    expect(find.text('Selesaikan Transaksi'), findsNothing,
        reason: 'tanpa fix, tombol pintas ini akan tampil & meloloskan '
            'checkout TANPA kasir pernah menerima uang tambahan utk '
            'pelunasan hutang');
    expect(find.textContaining('Bayar Rp'), findsOneWidget);

    await drain(tester);
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
