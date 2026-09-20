import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 12 — getDebtBook: pelanggan berhutang, diurut dari yang paling lama
/// menunggak (nota tertua yang belum lunas), total & jumlah nota benar,
/// nota lunas dikecualikan.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> addCustomer(String id, String name) =>
      db.into(db.customers).insert(
          CustomersCompanion.insert(id: id, name: name));

  Future<void> addTx({
    required String id,
    required String customerId,
    required int total,
    required int paid,
    required String status,
    required DateTime createdAt,
  }) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: id,
            localId: id,
            status: status,
            total: total,
            paid: paid,
            changeAmount: 0,
            paymentMethod: 'tunai',
            customerId: Value(customerId),
            createdAt: Value(createdAt),
          ));

  test(
      'diurut nota tertua dulu; total & count benar; nota lunas dikecualikan',
      () async {
    final now = DateTime.now();
    await addCustomer('c-andi', 'Andi');
    await addCustomer('c-budi', 'Budi');

    // Andi: 1 nota belum lunas, PALING LAMA (40 hari), debt 70k.
    await addTx(
        id: 't1',
        customerId: 'c-andi',
        total: 100000,
        paid: 30000,
        status: 'kurang_bayar',
        createdAt: now.subtract(const Duration(days: 40)));
    // Andi juga punya nota LUNAS → harus dikecualikan.
    await addTx(
        id: 't2',
        customerId: 'c-andi',
        total: 50000,
        paid: 50000,
        status: 'lunas',
        createdAt: now.subtract(const Duration(days: 2)));

    // Budi: 2 nota belum lunas (10 & 5 hari), debt 50k + 20k = 70k.
    await addTx(
        id: 't3',
        customerId: 'c-budi',
        total: 50000,
        paid: 0,
        status: 'tempo',
        createdAt: now.subtract(const Duration(days: 10)));
    await addTx(
        id: 't4',
        customerId: 'c-budi',
        total: 20000,
        paid: 0,
        status: 'tempo',
        createdAt: now.subtract(const Duration(days: 5)));

    final book = await db.getDebtBook();

    expect(book.length, 2);
    // Andi menunggak paling lama (40 hari) → paling atas.
    expect(book[0].name, 'Andi');
    expect(book[0].debt, 70000);
    expect(book[0].count, 1); // nota lunas tidak dihitung
    expect(book[0].daysOverdue, greaterThanOrEqualTo(39));

    expect(book[1].name, 'Budi');
    expect(book[1].debt, 70000);
    expect(book[1].count, 2);
    // Umur menunggak Budi dari nota TERTUA-nya (10 hari), bukan yang 5 hari.
    expect(book[1].daysOverdue, inInclusiveRange(9, 11));
  });

  test('tanpa hutang → daftar kosong', () async {
    await addCustomer('c-a', 'A');
    await addTx(
        id: 'x',
        customerId: 'c-a',
        total: 10000,
        paid: 10000,
        status: 'lunas',
        createdAt: DateTime.now());
    expect(await db.getDebtBook(), isEmpty);
  });

  test('getUnpaidTxIds terlama dulu (untuk pelunasan FIFO)', () async {
    final now = DateTime.now();
    await addCustomer('c-b', 'B');
    await addTx(
        id: 'baru',
        customerId: 'c-b',
        total: 10000,
        paid: 0,
        status: 'tempo',
        createdAt: now.subtract(const Duration(days: 1)));
    await addTx(
        id: 'lama',
        customerId: 'c-b',
        total: 20000,
        paid: 0,
        status: 'tempo',
        createdAt: now.subtract(const Duration(days: 9)));
    final ids = await db.getUnpaidTxIds('c-b');
    expect(ids, ['lama', 'baru']); // terlama dulu
  });

  Future<void> addAdhocTx({
    required String id,
    String? customerName,
    required int total,
    required int paid,
    required String status,
    required DateTime createdAt,
  }) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: id,
            localId: id,
            status: status,
            total: total,
            paid: paid,
            changeAmount: 0,
            paymentMethod: 'tunai',
            customerName: Value(customerName),
            createdAt: Value(createdAt),
          ));

  group('Item 83 — pembeli AD-HOC ikut masuk Buku Hutang', () {
    test(
        'nota tempo/kurang_bayar milik pembeli ad-hoc (customer_id null) '
        'MUNCUL di getDebtBook, dikelompokkan per customer_name', () async {
      final now = DateTime.now();
      await addAdhocTx(
          id: 'ad1',
          customerName: 'Budi (warung sebelah)',
          total: 50000,
          paid: 20000,
          status: 'kurang_bayar',
          createdAt: now.subtract(const Duration(days: 5)));
      // Nota ad-hoc KEDUA milik nama yang SAMA -> harus tergabung 1 baris.
      await addAdhocTx(
          id: 'ad2',
          customerName: 'Budi (warung sebelah)',
          total: 10000,
          paid: 0,
          status: 'tempo',
          createdAt: now.subtract(const Duration(days: 2)));

      final book = await db.getDebtBook();
      expect(book, hasLength(1));
      final e = book.single;
      expect(e.customerId, isNull);
      expect(e.isAdhoc, isTrue);
      expect(e.name, 'Budi (warung sebelah)');
      expect(e.debt, 40000); // (50000-20000) + 10000
      expect(e.count, 2);
    });

    test(
        'nota ad-hoc TANPA nama sama sekali (Umum) juga ikut masuk, '
        'dikelompokkan terpisah dari yang bernama', () async {
      await addAdhocTx(
          id: 'ad-umum',
          customerName: null,
          total: 15000,
          paid: 0,
          status: 'tempo',
          createdAt: DateTime.now());
      final book = await db.getDebtBook();
      expect(book, hasLength(1));
      expect(book.single.name, 'Umum');
      expect(book.single.adhocCustomerName, isNull);
      expect(book.single.debt, 15000);
    });

    test(
        'pelanggan TERDAFTAR & pembeli ad-hoc SAMA-SAMA muncul bersamaan, '
        'tidak saling menghilangkan', () async {
      await addCustomer('c-andi', 'Andi');
      await addTx(
          id: 't-andi',
          customerId: 'c-andi',
          total: 30000,
          paid: 0,
          status: 'tempo',
          createdAt: DateTime.now().subtract(const Duration(days: 3)));
      await addAdhocTx(
          id: 'ad-x',
          customerName: 'Bu Siti',
          total: 25000,
          paid: 0,
          status: 'tempo',
          createdAt: DateTime.now().subtract(const Duration(days: 1)));

      final book = await db.getDebtBook();
      expect(book, hasLength(2));
      expect(book.where((e) => !e.isAdhoc).single.name, 'Andi');
      expect(book.where((e) => e.isAdhoc).single.name, 'Bu Siti');
    });

    test(
        'getUnpaidTxIdsByCustomerName/getUnpaidTxDetailsByCustomerName '
        'mencocokkan PERSIS nama, tidak ikut ambil nota pelanggan '
        'terdaftar/nama lain', () async {
      await addCustomer('c-lain', 'Nama Sama Persis');
      await addTx(
          id: 't-terdaftar',
          customerId: 'c-lain',
          total: 99000,
          paid: 0,
          status: 'tempo',
          createdAt: DateTime.now());
      await addAdhocTx(
          id: 'ad-match',
          customerName: 'Nama Sama Persis',
          total: 12000,
          paid: 0,
          status: 'tempo',
          createdAt: DateTime.now().subtract(const Duration(days: 1)));
      await addAdhocTx(
          id: 'ad-other',
          customerName: 'Nama Lain',
          total: 5000,
          paid: 0,
          status: 'tempo',
          createdAt: DateTime.now());

      final ids =
          await db.getUnpaidTxIdsByCustomerName('Nama Sama Persis');
      expect(ids, ['ad-match'],
          reason: 'HANYA nota ad-hoc dgn nama persis sama, bukan nota '
              'pelanggan terdaftar walau namanya kebetulan identik, '
              'bukan pula nota ad-hoc nama lain');

      final details =
          await db.getUnpaidTxDetailsByCustomerName('Nama Sama Persis');
      expect(details, hasLength(1));
      expect(details.single.id, 'ad-match');
      expect(details.single.sisa, 12000);
    });

    test(
        'getUnpaidTxIdsByCustomerName(null) HANYA ambil nota "Umum" murni, '
        'tidak ikut ambil nota ad-hoc yang punya nama', () async {
      await addAdhocTx(
          id: 'ad-umum2',
          customerName: null,
          total: 8000,
          paid: 0,
          status: 'tempo',
          createdAt: DateTime.now());
      await addAdhocTx(
          id: 'ad-bernama',
          customerName: 'Ada Namanya',
          total: 3000,
          paid: 0,
          status: 'tempo',
          createdAt: DateTime.now());

      final ids = await db.getUnpaidTxIdsByCustomerName(null);
      expect(ids, ['ad-umum2']);
    });
  });
}
