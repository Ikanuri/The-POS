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

  group('buildPrabayarCheckout + changeTakenTotal — "kembalian sudah diambil" '
      'TIDAK boleh dihitung ulang sbg kredit tersedia', () {
    test('kembalian SUDAH diambil penuh sebelumnya, cart naik lagi: '
        'poolTersedia (bukan lockedSum mentah) yg dipakai utk status/sisa', () {
      // Entri Pra-Bayar Rp100rb dikunci saat cart masih Rp60rb (kembalian
      // Rp40rb SUDAH diambil kasir sebelum layar bayar ini dibuka — cart
      // lalu naik lagi jadi Rp90rb, kasir mengumpulkan sisa Rp30rb via
      // keypad). Tanpa fix: lockedSum(100rb)+30rb=130rb dianggap "lunas +
      // kembalian 40rb" -> kembalian Rp40rb yg SUDAH diserahkan diserahkan
      // LAGI (dobel). Dengan fix: poolTersedia = 100rb-40rb = 60rb, gabungan
      // 60rb+30rb = 90rb = PAS, TANPA kembalian tambahan.
      final lockedAt = DateTime(2026, 3, 1, 8, 0);
      final result = buildPrabayarCheckout(
        txId: 'txC',
        cartTotal: 90000,
        prabayarEntries: [
          PrabayarEntry(
              id: 'pbC', amount: 100000, method: 'tunai', lockedAt: lockedAt),
        ],
        paidAmountNow: 30000,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 3, 2, 10, 0),
        kasirId: 'K1',
        genId: genId,
        changeTakenTotal: 40000,
      );

      expect(result.combinedPaid, 90000,
          reason: 'poolTersedia(60rb) + paidAmountNow(30rb), BUKAN '
              'lockedSum(100rb) + paidAmountNow(30rb)');
      expect(result.status, 'lunas');
      expect(result.combinedChange, 0,
          reason: 'kembalian Rp40rb SUDAH diserahkan sebelumnya — TIDAK '
              'boleh dihitung ulang jadi kembalian tambahan di checkout ini');
      // Invariant lama (sum(payments.amount) == combinedPaid) tetap terjaga
      // — porsi yang sudah diambil dipotong dari entri PALING BARU dikunci
      // (di sini cuma satu entri, jadi amount efektifnya 60rb).
      expect(result.payments.fold<int>(0, (s, p) => s + p.amount.value), 90000);
      expect(result.payments, hasLength(2),
          reason: 'baris entri Pra-Bayar (dipotong) + baris "sekarang"');
      expect(result.payments[0].amount.value, 60000);
      expect(result.payments[0].changeGiven.value, 0);
      expect(result.payments[1].amount.value, 30000);
      expect(result.payments[1].changeGiven.value, 0);
    });

    test('kembalian SEBAGIAN diambil, lockedSum SENDIRI masih menutup total: '
        'status lunas, TANPA baris "sekarang"', () {
      // Dua entri (30rb lalu 40rb, total 70rb). Sebelumnya sempat muncul
      // kembalian Rp10rb (saat cart masih 60rb) yg SUDAH diambil. Cart tetap
      // 60rb saat checkout (tidak berubah lagi) → poolTersedia = 70-10=60,
      // PAS dgn total, TANPA paidAmountNow, TANPA kembalian baru.
      final t1 = DateTime(2026, 3, 1, 9, 0);
      final t2 = DateTime(2026, 3, 1, 10, 0);
      final result = buildPrabayarCheckout(
        txId: 'txD',
        cartTotal: 60000,
        prabayarEntries: [
          PrabayarEntry(id: 'pbD1', amount: 30000, method: 'tunai', lockedAt: t1),
          PrabayarEntry(id: 'pbD2', amount: 40000, method: 'qris', lockedAt: t2),
        ],
        paidAmountNow: 0,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 3, 2, 11, 0),
        kasirId: 'K1',
        genId: genId,
        changeTakenTotal: 10000,
      );

      expect(result.combinedPaid, 60000);
      expect(result.status, 'lunas');
      expect(result.combinedChange, 0);
      // Potongan Rp10rb diambil dari entri PALING BARU dikunci (pbD2, t2)
      // dulu (mundur) — entri pbD1 (t1) tetap utuh Rp30rb.
      expect(result.payments, hasLength(2));
      expect(result.payments[0].amount.value, 30000,
          reason: 'entri PERTAMA (t1) tidak tersentuh');
      expect(result.payments[1].amount.value, 30000,
          reason: 'entri TERAKHIR (t2, 40rb) dipotong 10rb jadi 30rb');
      expect(
          result.payments.fold<int>(0, (s, p) => s + p.amount.value), 60000);
    });

    test('changeTakenTotal MELEBIHI/SAMA lockedSum sepenuhnya (entri habis '
        'terpotong): baris entri itu TIDAK muncul sama sekali di payments',
        () {
      final lockedAt = DateTime(2026, 3, 1, 8, 0);
      final result = buildPrabayarCheckout(
        txId: 'txE',
        cartTotal: 50000,
        prabayarEntries: [
          PrabayarEntry(
              id: 'pbE', amount: 40000, method: 'tunai', lockedAt: lockedAt),
        ],
        paidAmountNow: 50000,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 3, 2),
        kasirId: 'K1',
        genId: genId,
        changeTakenTotal: 40000, // seluruh entri sudah diambil balik
      );

      expect(result.combinedPaid, 50000,
          reason: 'poolTersedia(0) + paidAmountNow(50rb)');
      expect(result.status, 'lunas');
      expect(result.combinedChange, 0);
      expect(result.payments, hasLength(1),
          reason: 'entri Pra-Bayar yg amount efektifnya 0 tidak menghasilkan '
              'baris TransactionPayments sama sekali');
      expect(result.payments.single.amount.value, 50000);
      expect(result.payments.single.method.value, 'tunai');
    });

    test('changeTakenTotal default 0 (perilaku lama TIDAK berubah)', () {
      final result = buildPrabayarCheckout(
        txId: 'txF',
        cartTotal: 50000,
        prabayarEntries: [
          PrabayarEntry(
              id: 'pbF',
              amount: 60000,
              method: 'tunai',
              lockedAt: DateTime(2026, 3, 1)),
        ],
        paidAmountNow: 0,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 3, 2),
        kasirId: 'K1',
        genId: genId,
      );

      expect(result.combinedPaid, 60000);
      expect(result.combinedChange, 10000);
      expect(result.payments.single.amount.value, 60000);
    });
  });

  group('buildPrabayarCheckout — prabayarChangeTakenBeforeCheckout '
      '(metadata "kembalian sudah diambil sebelum checkout")', () {
    test('baris yang KENA potongan mundur dapat metadata = nilai potongan, '
        'baris yang TIDAK kena tetap null', () {
      final t1 = DateTime(2026, 3, 1, 9, 0);
      final t2 = DateTime(2026, 3, 1, 10, 0);
      final result = buildPrabayarCheckout(
        txId: 'txG',
        cartTotal: 60000,
        prabayarEntries: [
          PrabayarEntry(id: 'pbG1', amount: 30000, method: 'tunai', lockedAt: t1),
          PrabayarEntry(id: 'pbG2', amount: 40000, method: 'qris', lockedAt: t2),
        ],
        paidAmountNow: 0,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 3, 2, 11, 0),
        kasirId: 'K1',
        genId: genId,
        changeTakenTotal: 10000,
      );

      expect(result.payments, hasLength(2));
      // pbG1 (t1) tidak tersentuh potongan (potongan diambil mundur dari
      // yg PALING BARU dulu) — metadata harus tetap `Value.absent()` (null).
      expect(result.payments[0].amount.value, 30000);
      expect(result.payments[0].prabayarChangeTakenBeforeCheckout.present, false,
          reason: 'entri yg TIDAK kena potongan tidak boleh punya metadata '
              'ini sama sekali (bukan 0)');
      // pbG2 (t2, PALING BARU) dipotong 10rb dari 40rb asli jadi 30rb —
      // metadata harus merekam nilai yg dipotong (10rb), BUKAN amount
      // efektif (30rb) atau amount asli (40rb).
      expect(result.payments[1].amount.value, 30000);
      expect(result.payments[1].prabayarChangeTakenBeforeCheckout.value, 10000);

      // Invariant lama TETAP terjaga — amount efektif (SUDAH dipotong)
      // tidak berubah walau ada metadata baru ini.
      expect(result.payments.fold<int>(0, (s, p) => s + p.amount.value), 60000);
      expect(result.combinedPaid, 60000);
    });

    test('potongan MELINTASI dua entri sekaligus: masing2 dapat metadata '
        'sesuai porsi yg dipotong DARI ENTRI ITU, bukan total potongan', () {
      // Dua entri (t1=20rb, t2=30rb, total lockedSum 50rb). changeTakenTotal
      // 25rb: dipotong mundur — t2 (30rb) dipotong penuh 25rb dulu? Tidak,
      // logic memotong MIN(remainingCut, e.amount) per entri: t2 dipotong
      // min(25,30)=25 -> t2 jadi 5rb, sisa potongan 0. t1 tidak tersentuh.
      final t1 = DateTime(2026, 3, 1, 9, 0);
      final t2 = DateTime(2026, 3, 1, 10, 0);
      final result = buildPrabayarCheckout(
        txId: 'txH',
        cartTotal: 25000,
        prabayarEntries: [
          PrabayarEntry(id: 'pbH1', amount: 20000, method: 'tunai', lockedAt: t1),
          PrabayarEntry(id: 'pbH2', amount: 30000, method: 'tunai', lockedAt: t2),
        ],
        paidAmountNow: 0,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 3, 2),
        kasirId: 'K1',
        genId: genId,
        changeTakenTotal: 25000,
      );

      expect(result.payments, hasLength(2));
      expect(result.payments[0].amount.value, 20000);
      expect(result.payments[0].prabayarChangeTakenBeforeCheckout.present, false);
      expect(result.payments[1].amount.value, 5000);
      expect(result.payments[1].prabayarChangeTakenBeforeCheckout.value, 25000);
    });

    test('entri yg HABIS terpotong (amount efektif 0, tidak muncul di '
        'payments) tidak bocorkan metadata ke baris lain', () {
      final lockedAt = DateTime(2026, 3, 1, 8, 0);
      final result = buildPrabayarCheckout(
        txId: 'txI',
        cartTotal: 50000,
        prabayarEntries: [
          PrabayarEntry(id: 'pbI', amount: 40000, method: 'tunai', lockedAt: lockedAt),
        ],
        paidAmountNow: 50000,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 3, 2),
        kasirId: 'K1',
        genId: genId,
        changeTakenTotal: 40000,
      );

      expect(result.payments, hasLength(1),
          reason: 'entri pbI habis terpotong, tidak menghasilkan baris sama '
              'sekali');
      expect(result.payments.single.amount.value, 50000,
          reason: 'baris "sekarang", bukan entri Pra-Bayar');
      expect(
          result.payments.single.prabayarChangeTakenBeforeCheckout.present,
          false);
    });

    test('changeTakenTotal 0 (default): TIDAK ADA baris yg dapat metadata '
        'sama sekali (perilaku lama utuh)', () {
      final result = buildPrabayarCheckout(
        txId: 'txJ',
        cartTotal: 50000,
        prabayarEntries: [
          PrabayarEntry(
              id: 'pbJ',
              amount: 60000,
              method: 'tunai',
              lockedAt: DateTime(2026, 3, 1)),
        ],
        paidAmountNow: 0,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 3, 2),
        kasirId: 'K1',
        genId: genId,
      );

      expect(result.payments.single.prabayarChangeTakenBeforeCheckout.present,
          false);
    });
  });

  group('buildPrabayarCheckout + AppDatabase — metadata '
      'prabayarChangeTakenBeforeCheckout round-trip + invariant Σamount', () {
    test('metadata tersimpan & terbaca benar dari DB sungguhan, DAN '
        'Σ payments.amount == transactions.paid (invariant TIDAK pecah)',
        () async {
      final t1 = DateTime(2026, 4, 1, 9, 0);
      final t2 = DateTime(2026, 4, 1, 10, 0);
      final result = buildPrabayarCheckout(
        txId: 'txK',
        cartTotal: 60000,
        prabayarEntries: [
          PrabayarEntry(id: 'pbK1', amount: 30000, method: 'tunai', lockedAt: t1),
          PrabayarEntry(id: 'pbK2', amount: 40000, method: 'qris', lockedAt: t2),
        ],
        paidAmountNow: 0,
        isTempo: false,
        nowMethodType: 'tunai',
        now: DateTime(2026, 4, 2, 11, 0),
        kasirId: 'K1',
        genId: genId,
        changeTakenTotal: 10000,
      );

      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'txK',
            localId: 'txK',
            status: result.status,
            total: 60000,
            paid: result.combinedPaid,
            changeAmount: result.combinedChange,
            paymentMethod: result.displayMethodType,
            createdAt: Value(DateTime(2026, 4, 2, 11, 0)),
          ));
      await db.batch((b) => b.insertAll(db.transactionPayments, result.payments));

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('txK')))
          .getSingle();
      final payments = await db.getPaymentsForTx('txK');

      // Invariant WAJIB (regresi dilindungi test lama juga) — ini
      // menegaskan kolom baru TIDAK mengganggu invariant tsb.
      expect(payments.fold<int>(0, (s, p) => s + p.amount), tx.paid,
          reason: 'Σ payments.amount HARUS == transactions.paid/combinedPaid '
              '— metadata baru tidak boleh menaikkan amount efektif');

      expect(payments, hasLength(2));
      expect(payments[0].amount, 30000);
      expect(payments[0].prabayarChangeTakenBeforeCheckout, null);
      expect(payments[1].amount, 30000);
      expect(payments[1].prabayarChangeTakenBeforeCheckout, 10000,
          reason: 'metadata terbaca benar dari DB sungguhan (bukan cuma di '
              'objek Companion sebelum insert)');
    });
  });
}
