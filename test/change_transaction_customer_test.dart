import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug dilaporkan user: transaksi umum diubah ke pelanggan terdaftar (dapat
/// poin), lalu diubah BALIK ke Umum lagi — poin TETAP nempel di pelanggan
/// lama, padahal transaksinya sudah tidak lagi tercatat atas namanya
/// (`voidTransaction` butuh `customerId != null` utk bisa menarik balik,
/// jadi begitu customerId di-null-kan jalur reversal lama itu tidak jalan).
///
/// `changeTransactionCustomer` (app_database.dart) dipakai `receipt_screen.dart`
/// `_saveCustomer` — menggantikan write mentah `customerId`/`customerName`.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> seedCustomer(String id, String name,
      {int loyaltyPoints = 0}) async {
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: id,
          name: name,
          loyaltyPoints: Value(loyaltyPoints),
        ));
    return id;
  }

  Future<void> seedTx({
    required String txId,
    required int total,
    String? customerId,
    int pointsEarned = 0,
  }) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: total,
          paid: total,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: Value(customerId),
          pointsEarned: Value(pointsEarned),
        ));
  }

  test(
      'pelanggan diubah balik ke Umum (id null) → poin ditarik balik dari '
      'pelanggan lama, tx.pointsEarned direset ke 0', () async {
    await seedCustomer('c1', 'Bu Siti', loyaltyPoints: 10);
    await seedTx(txId: 'tx1', total: 100000, customerId: 'c1', pointsEarned: 10);

    await db.changeTransactionCustomer(
        txId: 'tx1', newCustomerId: null, newCustomerName: null);

    final cust =
        await (db.select(db.customers)..where((t) => t.id.equals('c1')))
            .getSingle();
    expect(cust.loyaltyPoints, 0, reason: 'poin lama ditarik balik penuh');

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(tx.customerId, isNull);
    expect(tx.pointsEarned, 0);

    final ledger = await db.select(db.loyaltyPointLedger).get();
    expect(ledger, hasLength(1));
    expect(ledger.first.type, 'adjust');
    expect(ledger.first.points, -10);
    expect(ledger.first.customerId, 'c1');
  });

  test(
      'pelanggan diganti dari A ke B → poin A ditarik balik, B dihitung ulang '
      'dari 0 sesuai threshold (bukan dobel/warisan poin A)', () async {
    await db.setSetting('loyalty_point_threshold', '10000');
    await db.setSetting('loyalty_points_per', '1');
    await seedCustomer('a', 'Pelanggan A', loyaltyPoints: 10);
    await seedCustomer('b', 'Pelanggan B', loyaltyPoints: 0);
    await seedTx(txId: 'tx1', total: 100000, customerId: 'a', pointsEarned: 10);

    await db.changeTransactionCustomer(
        txId: 'tx1', newCustomerId: 'b', newCustomerName: 'Pelanggan B');

    final custA =
        await (db.select(db.customers)..where((t) => t.id.equals('a')))
            .getSingle();
    expect(custA.loyaltyPoints, 0);

    final custB =
        await (db.select(db.customers)..where((t) => t.id.equals('b')))
            .getSingle();
    expect(custB.loyaltyPoints, 10, reason: '100.000/10.000 dihitung ulang utk B');

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(tx.customerId, 'b');
    expect(tx.pointsEarned, 10);
  });

  test(
      'Umum → pelanggan terdaftar (belum pernah dapat poin) → cuma award, '
      'tidak ada clawback (customer lama tidak ada)', () async {
    await db.setSetting('loyalty_point_threshold', '10000');
    await db.setSetting('loyalty_points_per', '1');
    await seedCustomer('c1', 'Bu Siti');
    await seedTx(txId: 'tx1', total: 50000, customerId: null, pointsEarned: 0);

    await db.changeTransactionCustomer(
        txId: 'tx1', newCustomerId: 'c1', newCustomerName: 'Bu Siti');

    final cust =
        await (db.select(db.customers)..where((t) => t.id.equals('c1')))
            .getSingle();
    expect(cust.loyaltyPoints, 5);
    final ledger = await db.select(db.loyaltyPointLedger).get();
    expect(ledger, hasLength(1));
    expect(ledger.first.type, 'earn');
  });

  test(
      'id tidak berubah (cuma update lain yg tidak relevan) → tidak ada '
      'clawback/ledger baru', () async {
    await seedCustomer('c1', 'Bu Siti', loyaltyPoints: 10);
    await seedTx(txId: 'tx1', total: 100000, customerId: 'c1', pointsEarned: 10);

    await db.changeTransactionCustomer(
        txId: 'tx1', newCustomerId: 'c1', newCustomerName: 'Bu Siti');

    final cust =
        await (db.select(db.customers)..where((t) => t.id.equals('c1')))
            .getSingle();
    expect(cust.loyaltyPoints, 10, reason: 'tidak boleh ditarik balik/dobel');
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(tx.pointsEarned, 10, reason: 'tidak direset krn id sama persis');
    final ledger = await db.select(db.loyaltyPointLedger).get();
    expect(ledger, isEmpty);
  });
}
