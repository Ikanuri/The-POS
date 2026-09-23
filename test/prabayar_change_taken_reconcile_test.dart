import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/cart_prabayar_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

/// Audit Pra-Bayar (permintaan user, "masalah keuangan serius"): sejak
/// `191570c` baris Pra-Bayar ditulis dgn `amount` GROSS & kembalian yang
/// SUDAH diambil sebelum checkout dicatat terpisah di
/// `prabayarChangeTakenBeforeCheckout` — tapi `_reconcileTransactionTotals`
/// & `_computePaymentDelta` tetap menjumlah `amount` mentah. Akibatnya
/// (semua terbukti reproduksi sebelum fix):
///  A. nota Pra-Bayar yang berhutang berubah LUNAS begitu dihitung ulang
///     (tiap sync LAN, tambah belanjaan, retur, edit item, batal bayar);
///  B. `paid`/`changeAmount` membengkak sebesar kembalian yang sudah diambil;
///  C. melunasi sisa hutang PAS lewat "Tambah Bayar" menyuruh kasir
///     menyerahkan kembalian LAGI sebesar potongan itu, lalu nota tercatat
///     berhutang fiktif;
///  D. sama spt C, lewat Tambah Belanjaan.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// Checkout Pra-Bayar Rp84.900 dgn kembalian Rp54.900 SUDAH diambil
  /// sebelum checkout (pool Rp30.000), tanpa bayar tambahan — jalur & fungsi
  /// persis `payment_screen.dart` `_confirm`.
  Future<void> checkoutPrabayar({required int cartTotal}) async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P1', name: 'Gula'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
    var n = 0;
    final r = buildPrabayarCheckout(
      txId: 'tx1',
      cartTotal: cartTotal,
      prabayarEntries: [
        PrabayarEntry(
            id: 'e1', amount: 84900, method: 'tunai', lockedAt: DateTime.now()),
      ],
      paidAmountNow: 0,
      isTempo: false,
      nowMethodType: 'tunai',
      now: DateTime.now(),
      kasirId: 'K1',
      genId: () => 'pay${n++}',
      changeTakenTotal: 54900,
    );
    await db.saveTransaction(
      tx: TransactionsCompanion.insert(
        id: 'tx1',
        localId: 'K1-1',
        status: r.status,
        total: cartTotal,
        paid: r.combinedPaid,
        changeAmount: r.combinedChange,
        paymentMethod: r.displayMethodType,
      ),
      items: [
        TransactionItemsCompanion.insert(
            id: 'ti1',
            transactionId: 'tx1',
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: cartTotal,
            originalPrice: cartTotal,
            subtotal: cartTotal),
      ],
      payments: r.payments,
      stockItems: const [],
      now: DateTime.now(),
    );
  }

  Future<Transaction> tx() => (db.select(db.transactions)
        ..where((t) => t.id.equals('tx1')))
      .getSingle();
  Future<List<TransactionPayment>> pays() => (db.select(db.transactionPayments)
        ..where((t) => t.transactionId.equals('tx1')))
      .get();

  test(
      'A: nota Pra-Bayar berhutang Rp20.000 TETAP berhutang setelah dihitung '
      'ulang (sync) — tidak berubah jadi lunas', () async {
    await checkoutPrabayar(cartTotal: 50000);
    await db.reconcileTransactionsByIds({'tx1'});

    final t = await tx();
    expect(t.status, 'kurang_bayar',
        reason: 'tanpa fix: paid dihitung dari amount gross 84.900 -> lunas');
    expect(t.paid, 30000);
    expect(t.changeAmount, 0);
    expect(netRemainingOwed(t, await pays()), 20000);
  });

  test(
      'B: nota Pra-Bayar lunas pas — paid & kembalian header TIDAK membengkak '
      'setelah dihitung ulang', () async {
    await checkoutPrabayar(cartTotal: 30000);
    await db.reconcileTransactionsByIds({'tx1'});

    final t = await tx();
    expect(t.paid, 30000,
        reason: 'tanpa fix: 84.900 (termasuk kembalian yang sudah diambil)');
    expect(t.changeAmount, 0, reason: 'tanpa fix: kembalian fiktif 54.900');
    expect(t.status, 'lunas');
  });

  test(
      'C: melunasi sisa hutang PAS lewat Tambah Bayar -> TIDAK ada kembalian, '
      'nota lunas', () async {
    await checkoutPrabayar(cartTotal: 50000);

    final change = await db.addPaymentToTransaction(
        txId: 'tx1', amount: 20000, method: 'tunai', kasirId: 'K1');

    expect(change, 0,
        reason: 'tanpa fix: kasir disuruh menyerahkan kembalian 54.900 LAGI');
    final t = await tx();
    expect(t.status, 'lunas');
    expect(netRemainingOwed(t, await pays()), 0,
        reason: 'tanpa fix: nota tercatat berhutang fiktif 54.900');
  });

  test(
      'D: Tambah Belanjaan dibayar PAS pada nota Pra-Bayar -> TIDAK ada '
      'kembalian fiktif', () async {
    await checkoutPrabayar(cartTotal: 30000);

    await db.addItemsToTransaction(
      txId: 'tx1',
      items: [
        TransactionItemsCompanion.insert(
            id: 'ti2',
            transactionId: 'tx1',
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: 10000,
            originalPrice: 10000,
            subtotal: 10000),
      ],
      stockItems: const [],
      payment: TransactionPaymentsCompanion.insert(
          id: 'payAdd',
          transactionId: 'tx1',
          amount: 10000,
          method: 'tunai',
          note: const Value('Tambah belanjaan')),
    );

    final add = (await pays()).singleWhere((p) => p.id == 'payAdd');
    expect(add.changeGiven, 0,
        reason: 'tanpa fix: kembalian fiktif 54.900 di baris pembayaran ini');
    final t = await tx();
    expect(t.paid, 40000);
    expect(t.status, 'lunas');
  });
}
