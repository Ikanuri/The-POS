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
      {required int debtAmount,
      required String sourceTxId,
      int itemPrice = 100000}) async {
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
    container.read(cartProvider(kMainCartId).notifier).addItem(
        itemPrice == 100000
            ? item
            : CartItem(
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
      'ketik uang KURANG dari nominal hutang SENDIRI -> checkout DITOLAK, '
      'tidak ada transaksi baru & hutang lama TETAP tempo', (tester) async {
    final db = await seedOldDebtTx('old2', total: 30000);
    // Belanja 50.000 (bukan 100.000 standar) — angka lebih kecil di sini
    // MURNI supaya label tombol konfirmasi kalkulator ("Catat Hutang
    // Rp...") tidak overflow di lebar test default (bug tampilan LAIN yg
    // tidak berkaitan, muncul kalau nominal shortfall >= Rp100.000 —
    // di luar cakupan Item 85, tidak diperbaiki di sini).
    await pumpPaymentWithDebtEntry(tester, db,
        debtAmount: 30000, sourceTxId: 'old2', itemPrice: 50000);

    await tester.tap(find.textContaining('Bayar Rp'));
    await tester.pumpAndSettle();

    // Ketik 20.000 — TIDAK CUKUP bahkan utk hutang 30.000 sendiri (apalagi
    // ditambah belanja 50.000). Ini SATU-SATUNYA kasus yang masih WAJIB
    // ditolak sepenuhnya sejak Item 85 (dulu SEMUA kekurangan dari grand
    // total ditolak, sekarang cuma kekurangan dari nominal settlement).
    for (final d in ['2', '0', '0', '0', '0']) {
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
    expect(find.textContaining('belum menutup pelunasan Hutang/Pre-order'),
        findsOneWidget,
        reason: 'checkout harus ditolak dgn peringatan krn uang blm '
            'menutup nominal settlement sendiri, bukan lanjut diam-diam '
            'ke _confirm()');

    final txs = await db.select(db.transactions).get();
    expect(txs.where((t) => t.id != 'old2'), isEmpty,
        reason: 'tidak boleh ada transaksi BARU tersimpan');
    final old = await (db.select(db.transactions)
          ..where((t) => t.id.equals('old2')))
        .getSingle();
    expect(old.status, 'tempo',
        reason: 'hutang lama TIDAK BOLEH ikut tercatat lunas kalau uang '
            'yang diterima kasir belum cukup bahkan utk hutang itu sendiri');

    await drain(tester);
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'Item 85 — ketik uang cukup utk hutang TAPI TIDAK cukup utk grand '
      'total penuh -> checkout SUKSES: hutang lama tetap lunas, nota baru '
      'jadi kurang_bayar utk sisa belanja', (tester) async {
    final db = await seedOldDebtTx('old2b', total: 30000);
    await pumpPaymentWithDebtEntry(tester, db,
        debtAmount: 30000, sourceTxId: 'old2b', itemPrice: 50000);

    await tester.tap(find.textContaining('Bayar Rp'));
    await tester.pumpAndSettle();

    // Ketik 45.000: cukup utk hutang 30.000 + sebagian belanja (15.000
    // dari 50.000), TIDAK cukup utk grand total 80.000. Kasus PERSIS yang
    // diminta user: pelanggan sekaligus melunasi hutang lama + belanja baru
    // satu nota, uangnya cukup utk hutang tapi tidak utk belanja
    // sepenuhnya.
    for (final d in ['4', '5', '0', '0', '0']) {
      await tester.tap(find.text(d));
    }
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pumpAndSettle();

    expect(find.textContaining('belum menutup'), findsNothing,
        reason: 'tidak boleh ditolak — uang sudah cukup utk pelunasan '
            'hutang, sisa belanja boleh kurang_bayar');

    final newTx = await (db.select(db.transactions)
          ..where((t) => t.id.isNotValue('old2b')))
        .getSingle();
    expect(newTx.total, 50000,
        reason: 'nota BARU cuma mencatat belanja, TIDAK diinflasi hutang');
    expect(newTx.paid, 15000,
        reason: '45.000 diterima - 30.000 utk hutang = 15.000 utk belanja');
    expect(newTx.status, 'kurang_bayar',
        reason: 'belanja baru belum lunas sepenuhnya (15.000 dari 50.000)');
    expect(newTx.changeAmount, 0,
        reason: 'tidak ada kembalian — combinedPaid (15.000) masih di '
            'bawah cartTotal (50.000)');

    final old = await (db.select(db.transactions)
          ..where((t) => t.id.equals('old2b')))
        .getSingle();
    expect(old.status, 'lunas',
        reason: 'pelunasan hutang TETAP diproses penuh krn uang yg '
            'diterima sudah cukup utk nominal hutang itu sendiri');

    await drain(tester);
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'Item 85 — tombol "Bayar Nanti" (tempo, 0 uang fisik) DINONAKTIFKAN '
      'selama ada entri Lunasi Hutang/Pre-order aktif', (tester) async {
    final db = await seedOldDebtTx('old2c');
    await pumpPaymentWithDebtEntry(tester, db,
        debtAmount: 50000, sourceTxId: 'old2c');

    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Bayar Nanti'));
    expect(button.onPressed, isNull,
        reason: '"Bayar Nanti" berarti 0 uang fisik diterima — TIDAK '
            'PERNAH bisa menutup pelunasan hutang/pre-order aktif, jadi '
            'harus dinonaktifkan (dulu tombol ini sama sekali tidak '
            'dijaga & bisa meloloskan hutang lunas tanpa uang sepeser pun)');

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
