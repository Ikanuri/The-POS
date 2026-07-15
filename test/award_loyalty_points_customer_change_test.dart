import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug dilaporkan user: ubah pelanggan dari "Umum" ke pelanggan terdaftar DI
/// STRUK (`receipt_screen.dart` `_saveCustomer`, bukan saat checkout) tidak
/// pernah memberi poin loyalitas — poin cuma dihitung sekali saat checkout
/// (`payment_screen.dart` `_confirm()`), waktu itu `customerId` masih null
/// (pelanggan "Umum") sehingga `pointsEarned` tersimpan 0 selamanya.
///
/// `awardLoyaltyPointsIfEligible` (app_database.dart) diekstrak supaya
/// testable Tier 1 (DB murni) tanpa perlu widget tree `receipt_screen.dart`.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> seedTxUmum({required int total}) async {
    const txId = 'tx1';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'tempo',
          total: total,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tempo',
          pointsEarned: const Value(0),
        ));
    return txId;
  }

  Future<String> seedCustomer({int loyaltyPoints = 0}) async {
    const custId = 'c1';
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: custId,
          name: 'Bu Siti',
          loyaltyPoints: Value(loyaltyPoints),
        ));
    return custId;
  }

  test(
      'total melebihi threshold → poin dihitung & masuk ke transaksi + '
      'customer + ledger, walau transaksi awalnya "Umum" (tempo)', () async {
    await db.setSetting('loyalty_point_threshold', '10000');
    await db.setSetting('loyalty_points_per', '1');
    final txId = await seedTxUmum(total: 100000);
    final custId = await seedCustomer();

    await db.awardLoyaltyPointsIfEligible(txId: txId, customerId: custId);

    final tx =
        await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
            .getSingle();
    expect(tx.pointsEarned, 10, reason: '100.000 / 10.000 = 10 kelipatan');

    final cust =
        await (db.select(db.customers)..where((t) => t.id.equals(custId)))
            .getSingle();
    expect(cust.loyaltyPoints, 10);

    final ledger = await db.select(db.loyaltyPointLedger).get();
    expect(ledger, hasLength(1));
    expect(ledger.first.type, 'earn');
    expect(ledger.first.points, 10);
    expect(ledger.first.customerId, custId);
  });

  test('total DI BAWAH threshold → tidak ada poin ditambahkan (no-op aman)',
      () async {
    await db.setSetting('loyalty_point_threshold', '10000');
    await db.setSetting('loyalty_points_per', '1');
    final txId = await seedTxUmum(total: 5000);
    final custId = await seedCustomer();

    await db.awardLoyaltyPointsIfEligible(txId: txId, customerId: custId);

    final tx =
        await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
            .getSingle();
    expect(tx.pointsEarned, 0);
    final cust =
        await (db.select(db.customers)..where((t) => t.id.equals(custId)))
            .getSingle();
    expect(cust.loyaltyPoints, 0);
  });

  test(
      'transaksi yang SUDAH pernah dapat poin (pointsEarned > 0) → no-op, '
      'TIDAK menambah dobel walau dipanggil lagi (mis. ganti nama tampilan '
      'pelanggan yang sama)', () async {
    await db.setSetting('loyalty_point_threshold', '10000');
    await db.setSetting('loyalty_points_per', '1');
    const txId = 'tx1';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 100000,
          paid: 100000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          pointsEarned: const Value(10), // sudah pernah dapat poin
        ));
    final custId = await seedCustomer(loyaltyPoints: 10);

    await db.awardLoyaltyPointsIfEligible(txId: txId, customerId: custId);

    final cust =
        await (db.select(db.customers)..where((t) => t.id.equals(custId)))
            .getSingle();
    expect(cust.loyaltyPoints, 10, reason: 'tidak boleh dobel jadi 20');
    final ledger = await db.select(db.loyaltyPointLedger).get();
    expect(ledger, isEmpty, reason: 'tidak ada entri ledger baru ditulis');
  });

  test('threshold belum dikonfigurasi (0/kosong) → tidak ada poin, tidak crash',
      () async {
    final txId = await seedTxUmum(total: 100000);
    final custId = await seedCustomer();

    await db.awardLoyaltyPointsIfEligible(txId: txId, customerId: custId);

    final tx =
        await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
            .getSingle();
    expect(tx.pointsEarned, 0);
  });
}
