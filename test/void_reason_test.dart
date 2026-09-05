import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Log void (permintaan user) — `voidTransaction` sekarang mencatat siapa
/// yang membatalkan (`voidedBy`) & alasan opsional (`voidReason`).
/// `watchTransactions` juga dapat parameter `includeVoid` supaya Laporan ->
/// Transaksi bisa menampilkan nota void (dulu difilter hilang total).
void main() {
  Future<AppDatabase> seedWithOneTransaction() async {
    final db = AppDatabase(NativeDatabase.memory());
    final createdAt = DateTime.now();
    await db.saveTransaction(
      tx: TransactionsCompanion.insert(
        id: 'tx1',
        localId: 'K1-1',
        status: 'lunas',
        total: 10000,
        paid: 10000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt: Value(createdAt),
      ),
      items: [
        TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 10000,
          originalPrice: 10000,
          subtotal: 10000,
        ),
      ],
      payments: [
        TransactionPaymentsCompanion.insert(
          id: 'p1',
          transactionId: 'tx1',
          amount: 10000,
          method: 'tunai',
          paidAt: Value(createdAt),
        ),
      ],
      stockItems: const [],
      now: createdAt,
    );
    return db;
  }

  test('voidTransaction dengan reason menyimpan voidedBy & voidReason',
      () async {
    final db = await seedWithOneTransaction();
    addTearDown(db.close);

    await db.voidTransaction('tx1', 'K1', reason: 'Salah input harga');

    final row = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(row.status, 'void');
    expect(row.voidedBy, 'K1');
    expect(row.voidReason, 'Salah input harga');
  });

  test('voidTransaction TANPA reason tetap jalan, reason null (backward '
      'compatible dgn semua pemanggil lama)', () async {
    final db = await seedWithOneTransaction();
    addTearDown(db.close);

    await db.voidTransaction('tx1', 'K1');

    final row = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(row.status, 'void');
    expect(row.voidedBy, 'K1');
    expect(row.voidReason, isNull);
  });

  test('watchTransactions(includeVoid: false) default TETAP mengecualikan '
      'void (perilaku lama)', () async {
    final db = await seedWithOneTransaction();
    addTearDown(db.close);
    await db.voidTransaction('tx1', 'K1', reason: 'Batal');

    final from = DateTime.now().subtract(const Duration(days: 1));
    final to = DateTime.now().add(const Duration(days: 1));
    final list = await db.watchTransactions(from: from, to: to).first;
    expect(list, isEmpty,
        reason: 'default includeVoid=false harus tetap mengecualikan void, '
            'SEMUA pemanggil existing (ekspor dll) tidak boleh berubah');
  });

  test('watchTransactions(includeVoid: true) mengikutsertakan void',
      () async {
    final db = await seedWithOneTransaction();
    addTearDown(db.close);
    await db.voidTransaction('tx1', 'K1', reason: 'Batal');

    final from = DateTime.now().subtract(const Duration(days: 1));
    final to = DateTime.now().add(const Duration(days: 1));
    final list =
        await db.watchTransactions(from: from, to: to, includeVoid: true).first;
    expect(list, hasLength(1));
    expect(list.single.status, 'void');
    expect(list.single.voidReason, 'Batal');
  });
}
