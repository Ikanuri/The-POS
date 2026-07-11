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
}
