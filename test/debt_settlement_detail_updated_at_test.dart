import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Kelas bug SAMA dgn dok CLAUDE.md "Soft-delete/ubah master-data ...
/// WAJIB cap ulang `updated_at`" (sudah kejadian 2x sebelumnya di
/// `applyProductProposals`/`deactivateProduct`) — kali ini di
/// `saveTransactionWithDebtSettlements`: penulisan `debtSettlementDetail`
/// ke nota (`transactions`) TIDAK ikut mencap `updatedAt`, padahal
/// `dumpSince` (sync host->klien) memfilter transaksi dgn
/// `WHERE created_at >= ? OR updated_at >= ?` (Item 62 — nota bukan
/// append-only murni). Tanpa cap ulang, update pada nota LAMA (created_at
/// sudah lewat watermark device lain) tidak pernah lolos filter & tidak
/// pernah sampai ke perangkat lain.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test(
      'saveTransactionWithDebtSettlements mencap updatedAt nota BARU saat '
      'menulis debtSettlementDetail (bukan null/stale)', () async {
    final now = DateTime.now();
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Sari'));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'old1',
          localId: 'old1',
          status: 'kurang_bayar',
          total: 50000,
          paid: 20000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: const Value('c1'),
          createdAt: Value(now.subtract(const Duration(days: 5))),
        ));

    const txId = 'newtx1';
    final before = DateTime.now();
    await db.saveTransactionWithDebtSettlements(
      tx: TransactionsCompanion.insert(
        id: txId,
        localId: 'NEW-$txId',
        status: 'lunas',
        total: 30000,
        paid: 30000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt: Value(now),
      ),
      items: const [],
      payments: const [],
      stockItems: const [],
      debtSettlements: [
        (
          customerName: 'Sari',
          amount: 30000,
          targets: [
            (invoiceId: 'old1', invoiceLocalId: 'old1', invoiceDate: now, amount: 30000)
          ],
          method: 'tunai',
          methodName: null,
        ),
      ],
      kasirId: 'K1',
    );

    final newTx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    expect(newTx.debtSettlementDetail, isNotNull,
        reason: 'prasyarat: debtSettlementDetail harus tertulis');
    expect(newTx.updatedAt, isNotNull,
        reason: 'updatedAt HARUS dicap saat debtSettlementDetail ditulis — '
            'kalau null, baris ini tidak akan pernah lolos filter '
            'dumpSince (WHERE created_at >= ? OR updated_at >= ?) begitu '
            'watermark device lain lewat dari created_at aslinya.');
    expect(
        newTx.updatedAt!
            .isAfter(before.subtract(const Duration(seconds: 5))),
        isTrue,
        reason: 'updatedAt harus SETARA "sekarang" (baru saja ditulis), '
            'bukan stale/lama.');
  });
}
