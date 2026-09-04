import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/cart_prabayar_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// Fitur "Pra-Bayar" — checkout gabungan (entri yang sudah terkunci +
/// pilihan kasir SEKARANG). Menguji [buildPrabayarCheckout] (fungsi murni,
/// diekstrak dari `_confirm()` di `payment_screen.dart`) — logika UANG paling
/// sensitif di fitur ini — LANGSUNG, plus rekam ulang hasilnya ke
/// `AppDatabase` sungguhan (bukan mock) utk membuktikan `transactions`/
/// `transaction_payments` tersimpan benar end-to-end.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  int seq = 0;
  String genId() => 'gen-${seq++}';

  group('buildPrabayarCheckout — komposisi murni', () {
    test('lockedSum < total: status kurang_bayar, paid = gabungan, '
        'kembalian nempel ke baris "sekarang"', () {
      final lockedAt = DateTime(2026, 1, 1, 10, 0);
      final result = buildPrabayarCheckout(
        txId: 'tx1',
        cartTotal: 60000,
        prabayarEntries: [
          PrabayarEntry(
              id: 'pb1', amount: 30000, method: 'tunai', lockedAt: lockedAt),
        ],
        paidAmountNow: 20000,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 1, 2, 12, 0),
        kasirId: 'K1',
        genId: genId,
      );

      expect(result.combinedPaid, 50000);
      expect(result.status, 'kurang_bayar');
      expect(result.combinedChange, 0);
      expect(result.payments, hasLength(2));
      expect(result.payments[0].amount.value, 30000);
      expect(result.payments[0].paidAt.value, lockedAt,
          reason: 'baris Pra-Bayar HARUS pakai lockedAt ASLI, bukan waktu checkout');
      expect(result.payments[0].changeGiven.value, 0);
      expect(result.payments[1].amount.value, 20000);
      expect(result.payments[1].paidAt.value, DateTime(2026, 1, 2, 12, 0));
      expect(result.payments[1].changeGiven.value, 0);
    });

    test('lockedSum == total (persis pas): auto lunas, tidak ada baris '
        '"sekarang" sama sekali', () {
      final lockedAt = DateTime(2026, 1, 1, 10, 0);
      final result = buildPrabayarCheckout(
        txId: 'tx2',
        cartTotal: 60000,
        prabayarEntries: [
          PrabayarEntry(
              id: 'pb1', amount: 60000, method: 'qris', lockedAt: lockedAt),
        ],
        paidAmountNow: 0,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 1, 2, 12, 0),
        kasirId: 'K1',
        genId: genId,
      );

      expect(result.combinedPaid, 60000);
      expect(result.status, 'lunas');
      expect(result.combinedChange, 0);
      expect(result.payments, hasLength(1));
      expect(result.displayMethodType, 'qris',
          reason: 'tidak ada baris sekarang → label ambil dari entri '
              'Pra-Bayar terakhir');
    });

    test('lockedSum > total (kelebihan): auto lunas + kembalian nempel ke '
        'baris Pra-Bayar PALING TERAKHIR (tidak ada baris "sekarang")', () {
      final t1 = DateTime(2026, 1, 1, 9, 0);
      final t2 = DateTime(2026, 1, 1, 10, 0);
      final result = buildPrabayarCheckout(
        txId: 'tx3',
        cartTotal: 60000,
        prabayarEntries: [
          PrabayarEntry(id: 'pb1', amount: 40000, method: 'tunai', lockedAt: t1),
          PrabayarEntry(id: 'pb2', amount: 30000, method: 'qris', lockedAt: t2),
        ],
        paidAmountNow: 0,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 1, 2, 12, 0),
        kasirId: 'K1',
        genId: genId,
      );

      expect(result.combinedPaid, 70000);
      expect(result.status, 'lunas');
      expect(result.combinedChange, 10000);
      expect(result.payments, hasLength(2));
      expect(result.payments[0].changeGiven.value, 0,
          reason: 'entri PERTAMA tidak menampung kembalian');
      expect(result.payments[1].changeGiven.value, 10000,
          reason: 'entri Pra-Bayar TERAKHIR (paling baru dikunci) menampung '
              'kembalian gabungan');
    });

    test('tempo DENGAN lockedSum > 0: BUKAN status tempo murni lagi — jatuh '
        'ke kurang_bayar (selaras invariant _reconcileTransactionTotals: '
        'tempo cuma valid kalau paid == 0)', () {
      final result = buildPrabayarCheckout(
        txId: 'tx4',
        cartTotal: 50000,
        prabayarEntries: [
          PrabayarEntry(
              id: 'pb1',
              amount: 20000,
              method: 'tunai',
              lockedAt: DateTime(2026, 1, 1)),
        ],
        paidAmountNow: 0, // isTempo selalu memaksa paidAmountNow = 0
        isTempo: true,
        nowMethodType: 'tempo',
        now: DateTime(2026, 1, 2),
        kasirId: 'K1',
        genId: genId,
      );

      expect(result.combinedPaid, 20000);
      expect(result.status, 'kurang_bayar');
      expect(result.combinedChange, 0);
    });

    test('tempo TANPA prabayar sama sekali (perilaku lama): status tetap '
        'tempo, tidak ada baris pembayaran', () {
      final result = buildPrabayarCheckout(
        txId: 'tx5',
        cartTotal: 50000,
        prabayarEntries: const [],
        paidAmountNow: 0,
        isTempo: true,
        nowMethodType: 'tempo',
        now: DateTime(2026, 1, 2),
        kasirId: 'K1',
        genId: genId,
      );

      expect(result.combinedPaid, 0);
      expect(result.status, 'tempo');
      expect(result.combinedChange, 0);
      expect(result.payments, isEmpty);
    });

    test('tanpa prabayar sama sekali (perilaku lama tetap SAMA PERSIS): '
        'satu baris pembayaran normal, kembalian di baris itu', () {
      final result = buildPrabayarCheckout(
        txId: 'tx6',
        cartTotal: 50000,
        prabayarEntries: const [],
        paidAmountNow: 60000,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 1, 2),
        kasirId: 'K1',
        genId: genId,
      );

      expect(result.combinedPaid, 60000);
      expect(result.status, 'lunas');
      expect(result.combinedChange, 10000);
      expect(result.payments, hasLength(1));
      expect(result.payments.single.changeGiven.value, 10000);
    });
  });

  group('buildPrabayarCheckout + AppDatabase — round-trip sungguhan', () {
    test('lockedSum < total tersimpan benar: transactions.paid/status, '
        'SEMUA baris transaction_payments (paidAt masing2 benar)', () async {
      final lockedAt = DateTime(2026, 2, 1, 8, 30);
      final now = DateTime(2026, 2, 2, 14, 0);
      final result = buildPrabayarCheckout(
        txId: 'txA',
        cartTotal: 100000,
        prabayarEntries: [
          PrabayarEntry(
              id: 'pb1', amount: 40000, method: 'tunai', lockedAt: lockedAt),
        ],
        paidAmountNow: 30000,
        isTempo: false,
        nowMethodType: 'qris',
        nowMethodName: 'QRIS Toko',
        now: now,
        kasirId: 'K1',
        genId: genId,
      );

      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'txA',
            localId: 'txA',
            status: result.status,
            total: 100000,
            paid: result.combinedPaid,
            changeAmount: result.combinedChange,
            paymentMethod: result.displayMethodType,
            methodName: Value(result.displayMethodName),
            createdAt: Value(now),
          ));
      await db.batch((b) => b.insertAll(db.transactionPayments, result.payments));

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('txA')))
          .getSingle();
      expect(tx.paid, 70000);
      expect(tx.status, 'kurang_bayar');
      expect(tx.changeAmount, 0);

      final payments = await db.getPaymentsForTx('txA');
      expect(payments, hasLength(2));
      expect(payments[0].amount, 40000);
      expect(payments[0].method, 'tunai');
      expect(payments[0].paidAt, lockedAt);
      expect(payments[1].amount, 30000);
      expect(payments[1].method, 'qris');
      expect(payments[1].methodName, 'QRIS Toko');
      expect(payments[1].paidAt, now);
    });

    test('lockedSum >= total tersimpan benar: auto lunas + kembalian benar, '
        'SEMUA row berasal dari Pra-Bayar (tidak ada baris "sekarang")',
        () async {
      final t1 = DateTime(2026, 2, 1, 8, 0);
      final t2 = DateTime(2026, 2, 1, 9, 0);
      final result = buildPrabayarCheckout(
        txId: 'txB',
        cartTotal: 50000,
        prabayarEntries: [
          PrabayarEntry(id: 'pb1', amount: 30000, method: 'tunai', lockedAt: t1),
          PrabayarEntry(id: 'pb2', amount: 30000, method: 'tunai', lockedAt: t2),
        ],
        paidAmountNow: 0,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 2, 2),
        kasirId: 'K1',
        genId: genId,
      );

      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'txB',
            localId: 'txB',
            status: result.status,
            total: 50000,
            paid: result.combinedPaid,
            changeAmount: result.combinedChange,
            paymentMethod: result.displayMethodType,
            createdAt: Value(DateTime(2026, 2, 2)),
          ));
      await db.batch((b) => b.insertAll(db.transactionPayments, result.payments));

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('txB')))
          .getSingle();
      expect(tx.paid, 60000);
      expect(tx.status, 'lunas');
      expect(tx.changeAmount, 10000, reason: '60rb - 50rb = 10rb kembalian');

      final payments = await db.getPaymentsForTx('txB');
      expect(payments, hasLength(2));
      expect(payments.fold<int>(0, (s, p) => s + p.changeGiven), 10000,
          reason: 'total changeGiven semua baris harus == kembalian gabungan');
      expect(payments[0].paidAt, t1);
      expect(payments[1].paidAt, t2);
      expect(payments[1].changeGiven, 10000,
          reason: 'baris Pra-Bayar terakhir (t2) menampung kembalian');
    });
  });
}
