import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Diminta user saat diskusi laci-meja: begitu transaksi induknya di-void,
/// atribut Laci Meja (titip/pinjaman/pre-order) yang menempel padanya HARUS
/// tidak ikut tersinkron ke host lagi — kewajibannya sudah tidak relevan
/// begitu notanya dibatalkan. `voidTransaction` SENGAJA tidak menghapus baris
/// lokal (jejak audit, pola soft-delete konsisten di seluruh app) — jadi
/// filternya di titik keluar data (`dumpSince`), bukan hapus data lokal
/// (Opsi B, dipilih user krn lebih aman/reversibel drpd hapus permanen).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedTx(String id, {required String status}) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: id,
          status: status,
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
  }

  test(
      'preorder_entries/left_behind_items/borrowed_items milik transaksi '
      'VOID TIDAK ikut dumpSince, milik transaksi NON-void tetap ikut',
      () async {
    await seedTx('tx-void', status: 'void');
    await seedTx('tx-lunas', status: 'lunas');

    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
          id: 'po-void',
          productId: 'p1',
          productUnitId: 'u1',
          transactionId: const Value('tx-void'),
          customerName: 'Budi',
          qtyOrdered: 2.0,
        ));
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
          id: 'po-ok',
          productId: 'p1',
          productUnitId: 'u1',
          transactionId: const Value('tx-lunas'),
          customerName: 'Ani',
          qtyOrdered: 1.0,
        ));
    await db.into(db.leftBehindItems).insert(LeftBehindItemsCompanion.insert(
          id: 'lb-void',
          transactionId: 'tx-void',
          itemName: 'Sedap Soto',
          jenis: 'ketinggalan',
          customerNameText: const Value('Budi'),
          qty: const Value(1.0),
        ));
    await db.into(db.borrowedItems).insert(BorrowedItemsCompanion.insert(
          id: 'bo-void',
          transactionId: 'tx-void',
          itemName: 'Krat botol',
          qty: 1.0,
        ));

    final dump = await db.dumpSince(DateTime(2000));

    final preorderIds =
        (dump['preorder_entries'] ?? []).map((r) => r['id']).toSet();
    expect(preorderIds, contains('po-ok'));
    expect(preorderIds, isNot(contains('po-void')),
        reason: 'pre-order milik nota VOID tidak boleh ikut tersinkron');

    final leftBehindIds =
        (dump['left_behind_items'] ?? []).map((r) => r['id']).toSet();
    expect(leftBehindIds, isNot(contains('lb-void')));

    final borrowedIds =
        (dump['borrowed_items'] ?? []).map((r) => r['id']).toSet();
    expect(borrowedIds, isNot(contains('bo-void')));
  });

  test(
      'preorder_entries dgn transaction_id NULL (titip wadah tanpa beli '
      'apa pun) TIDAK ikut kefilter, tetap tersinkron', () async {
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
          id: 'po-null',
          productId: 'p1',
          productUnitId: 'u1',
          customerName: 'Budi',
          qtyOrdered: 1.0,
        ));

    final dump = await db.dumpSince(DateTime(2000));
    final preorderIds =
        (dump['preorder_entries'] ?? []).map((r) => r['id']).toSet();
    expect(preorderIds, contains('po-null'),
        reason: 'transaction_id NULL tidak pernah "milik" nota void apa pun');
  });

  test(
      'laci_meja_events milik entri pre-order/titip/pinjaman yang notanya '
      'VOID TIDAK ikut dumpSince (jangan jadi log yatim di host)', () async {
    await seedTx('tx-void', status: 'void');
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
          id: 'po-void',
          productId: 'p1',
          productUnitId: 'u1',
          transactionId: const Value('tx-void'),
          customerName: 'Budi',
          qtyOrdered: 2.0,
        ));
    await db.into(db.laciMejaEvents).insert(LaciMejaEventsCompanion.insert(
          id: 'ev-void',
          entityType: 'preorder',
          entryId: 'po-void',
          aksi: 'ambil',
          qty: const Value(1.0),
        ));

    final dump = await db.dumpSince(DateTime(2000));
    final eventIds =
        (dump['laci_meja_events'] ?? []).map((r) => r['id']).toSet();
    expect(eventIds, isNot(contains('ev-void')),
        reason: 'log kejadian milik entri yg induknya void tidak boleh '
            'ikut, kalau tidak jadi yatim menunjuk entri yg tidak sampai '
            'ke host');
  });
}
