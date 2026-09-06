import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Fitur "Lunasi Hutang" dari keranjang — `saveTransactionWithDebtSettlements`
/// harus: (1) menyimpan nota baru normal, (2) mengalokasikan FIFO nominal
/// pelunasan ke nota lama pelanggan lewat `settleMergedDebt`, (3) menulis
/// ringkasan `debtSettlementDetail` ke nota baru, (4) TIDAK PERNAH overpay
/// hutang aktual (cap ke sisa, kelebihan jadi kembalian di nota lama, bukan
/// ditambahkan ke hutang yang sudah lunas).
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> addCustomer(String id, String name) =>
      db.into(db.customers).insert(
          CustomersCompanion.insert(id: id, name: name));

  Future<void> addOldTx({
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

  TransactionsCompanion newSaleCompanion(String txId) =>
      TransactionsCompanion.insert(
        id: txId,
        localId: 'NEW-$txId',
        status: 'lunas',
        total: 25000,
        paid: 25000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt: Value(DateTime.now()),
      );

  test('alokasi FIFO ke satu nota lama + ringkasan tersimpan di nota baru',
      () async {
    final now = DateTime.now();
    await addCustomer('c1', 'Sari');
    await addOldTx(
        id: 'old1',
        customerId: 'c1',
        total: 50000,
        paid: 20000, // sisa 30000
        status: 'kurang_bayar',
        createdAt: now.subtract(const Duration(days: 5)));

    const txId = 'newtx1';
    await db.saveTransactionWithDebtSettlements(
      tx: newSaleCompanion(txId),
      items: const [],
      payments: const [],
      stockItems: const [],
      debtSettlements: [
        (
          customerName: 'Sari',
          amount: 30000,
          targets: [(invoiceId: 'old1', invoiceLocalId: 'old1', amount: 30000)],
          method: 'tunai',
          methodName: null,
        ),
      ],
      kasirId: 'K1',
    );

    final old = await (db.select(db.transactions)
          ..where((t) => t.id.equals('old1')))
        .getSingle();
    expect(old.paid, 50000);
    expect(old.status, 'lunas');

    final newTx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    expect(newTx.debtSettlementDetail, isNotNull);
    expect(newTx.debtSettlementDetail, contains('old1'));
    expect(newTx.debtSettlementDetail, contains('30000'));
  });

  test('partial: nominal lebih kecil dari sisa nota → nota tetap kurang_bayar',
      () async {
    final now = DateTime.now();
    await addCustomer('c2', 'Budi');
    await addOldTx(
        id: 'old2',
        customerId: 'c2',
        total: 100000,
        paid: 0,
        status: 'tempo',
        createdAt: now.subtract(const Duration(days: 3)));

    const txId = 'newtx2';
    await db.saveTransactionWithDebtSettlements(
      tx: newSaleCompanion(txId),
      items: const [],
      payments: const [],
      stockItems: const [],
      debtSettlements: [
        (
          customerName: 'Budi',
          amount: 40000,
          targets: [(invoiceId: 'old2', invoiceLocalId: 'old2', amount: 40000)],
          method: 'tunai',
          methodName: null,
        ),
      ],
      kasirId: 'K1',
    );

    final old = await (db.select(db.transactions)
          ..where((t) => t.id.equals('old2')))
        .getSingle();
    expect(old.paid, 40000);
    expect(old.status, 'kurang_bayar');
  });

  test(
      'tidak overpay: nominal lebih besar dari sisa hutang aktual -> paid dicap, TIDAK melebihi total',
      () async {
    final now = DateTime.now();
    await addCustomer('c3', 'Dedi');
    await addOldTx(
        id: 'old3',
        customerId: 'c3',
        total: 20000,
        paid: 5000, // sisa 15000
        status: 'kurang_bayar',
        createdAt: now.subtract(const Duration(days: 1)));

    const txId = 'newtx3';
    // Kasir "keliru" memasukkan target amount 50000 (lebih besar dari sisa
    // 15000 nota ini) — settleMergedDebt WAJIB men-cap paid ke total nota,
    // bukan menjadikan `paid` melebihi `total`.
    await db.saveTransactionWithDebtSettlements(
      tx: newSaleCompanion(txId),
      items: const [],
      payments: const [],
      stockItems: const [],
      debtSettlements: [
        (
          customerName: 'Dedi',
          amount: 50000,
          targets: [(invoiceId: 'old3', invoiceLocalId: 'old3', amount: 50000)],
          method: 'tunai',
          methodName: null,
        ),
      ],
      kasirId: 'K1',
    );

    final old = await (db.select(db.transactions)
          ..where((t) => t.id.equals('old3')))
        .getSingle();
    expect(old.paid, lessThanOrEqualTo(old.total));
    expect(old.paid, 20000); // dicap ke total, bukan 5000+50000=55000
    expect(old.status, 'lunas');

    // Kelebihan (50000 - 15000 sisa = 35000) muncul sbg changeGiven pada
    // baris pembayaran pelunasan nota lama ini (uang fisik melebihi
    // hutangnya, bukan overpay ke hutang) — dibuktikan lewat
    // getPaymentsForTxs, bukan asumsi.
    final payments = await db.getPaymentsForTxs(['old3']);
    final sumChange =
        (payments['old3'] ?? const []).fold<int>(0, (s, p) => s + p.changeGiven);
    expect(sumChange, 35000);
  });

  test('dua entri (dua pelanggan berbeda) tergabung dalam satu ringkasan',
      () async {
    final now = DateTime.now();
    await addCustomer('c4', 'Andi');
    await addCustomer('c5', 'Wati');
    await addOldTx(
        id: 'old4',
        customerId: 'c4',
        total: 10000,
        paid: 0,
        status: 'tempo',
        createdAt: now.subtract(const Duration(days: 2)));
    await addOldTx(
        id: 'old5',
        customerId: 'c5',
        total: 20000,
        paid: 0,
        status: 'tempo',
        createdAt: now.subtract(const Duration(days: 2)));

    const txId = 'newtx4';
    await db.saveTransactionWithDebtSettlements(
      tx: newSaleCompanion(txId),
      items: const [],
      payments: const [],
      stockItems: const [],
      debtSettlements: [
        (
          customerName: 'Andi',
          amount: 10000,
          targets: [(invoiceId: 'old4', invoiceLocalId: 'old4', amount: 10000)],
          method: 'tunai',
          methodName: null,
        ),
        (
          customerName: 'Wati',
          amount: 20000,
          targets: [(invoiceId: 'old5', invoiceLocalId: 'old5', amount: 20000)],
          method: 'tunai',
          methodName: null,
        ),
      ],
      kasirId: 'K1',
    );

    final old4 = await (db.select(db.transactions)
          ..where((t) => t.id.equals('old4')))
        .getSingle();
    final old5 = await (db.select(db.transactions)
          ..where((t) => t.id.equals('old5')))
        .getSingle();
    expect(old4.status, 'lunas');
    expect(old5.status, 'lunas');

    final newTx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    expect(newTx.debtSettlementDetail, contains('old4'));
    expect(newTx.debtSettlementDetail, contains('old5'));

    final parsed = parseDebtSettlementDetail(newTx.debtSettlementDetail);
    expect(parsed.length, 2);
    expect(parsed.map((l) => l.invoiceLocalId), containsAll(['old4', 'old5']));
    expect(parsed.map((l) => l.amount), containsAll([10000, 20000]));
  });

  test('parseDebtSettlementDetail: null/kosong/rusak -> list kosong (aman)',
      () async {
    expect(parseDebtSettlementDetail(null), isEmpty);
    expect(parseDebtSettlementDetail(''), isEmpty);
    expect(parseDebtSettlementDetail('bukan json valid {{{'), isEmpty);
    expect(parseDebtSettlementDetail('{"bukan":"list"}'), isEmpty);
  });

  test('parseDebtSettlementDetail: parse normal', () async {
    const raw =
        '[{"invoiceId":"i1","invoiceLocalId":"A1-1","amount":15000,"customerName":"Sari"}]';
    final parsed = parseDebtSettlementDetail(raw);
    expect(parsed.length, 1);
    expect(parsed.first.invoiceLocalId, 'A1-1');
    expect(parsed.first.amount, 15000);
    expect(parsed.first.customerName, 'Sari');
  });
}
