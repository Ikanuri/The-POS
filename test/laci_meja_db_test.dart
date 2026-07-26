import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 52 ("Laci Meja") — test DB murni utk CRUD dasar 3 kategori: Titip/
/// Ketinggalan, Pinjaman Barang, Pre-order. Rancangan lengkap: PLAN.md
/// Item 52.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> seedTransaction(String id) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: id,
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    return id;
  }

  group('Titip/Ketinggalan', () {
    test('tersimpan & tampil di watch, hilang dari daftar aktif setelah '
        'ditandai diambil (tapi tetap ada kalau includeCollected)', () async {
      final txId = await seedTransaction('tx1');
      await db.addLeftBehindItem(
          id: 'l1', transactionId: txId, itemName: 'Payung', jenis: 'ketinggalan');
      await db.addLeftBehindItem(
          id: 'l2', transactionId: txId, itemName: 'Galon titip', jenis: 'titip');

      var active = await db.watchLeftBehindItems().first;
      expect(active, hasLength(2));

      await db.markLeftBehindCollected('l1');
      active = await db.watchLeftBehindItems().first;
      expect(active, hasLength(1));
      expect(active.single.id, 'l2');

      final all = await db.watchLeftBehindItems(includeCollected: true).first;
      expect(all, hasLength(2));
    });

    test('diurut FIFO (paling lama menunggu dulu)', () async {
      final txId = await seedTransaction('tx1');
      await db.addLeftBehindItem(
          id: 'l-baru',
          transactionId: txId,
          itemName: 'Baru',
          jenis: 'titip');
      // Paksa createdAt lebih lama scr eksplisit (insert cepat -> timestamp
      // presisi detik bisa sama).
      await (db.update(db.leftBehindItems)
            ..where((t) => t.id.equals('l-baru')))
          .write(LeftBehindItemsCompanion(
              createdAt: Value(DateTime.now().add(const Duration(minutes: 5)))));
      await db.addLeftBehindItem(
          id: 'l-lama', transactionId: txId, itemName: 'Lama', jenis: 'titip');

      final list = await db.watchLeftBehindItems().first;
      expect(list.map((e) => e.id).toList(), ['l-lama', 'l-baru']);
    });
  });

  group('Pinjaman Barang', () {
    test('kembali sebagian tidak menandai selesai, kembali penuh menandai '
        'fullyReturnedAt', () async {
      final txId = await seedTransaction('tx1');
      await db.addBorrowedItem(
          id: 'b1', transactionId: txId, itemName: 'Galon Aqua', qty: 3);

      await db.returnBorrowedItemQty('b1', 2);
      var row =
          await (db.select(db.borrowedItems)..where((t) => t.id.equals('b1')))
              .getSingle();
      expect(row.qtyReturned, 2);
      expect(row.fullyReturnedAt, isNull);

      var active = await db.watchBorrowedItems().first;
      expect(active, hasLength(1), reason: 'belum kembali penuh, masih aktif');

      await db.returnBorrowedItemQty('b1', 1);
      row = await (db.select(db.borrowedItems)..where((t) => t.id.equals('b1')))
          .getSingle();
      expect(row.qtyReturned, 3);
      expect(row.fullyReturnedAt, isNotNull);

      active = await db.watchBorrowedItems().first;
      expect(active, isEmpty, reason: 'sudah kembali penuh, hilang dari aktif');
    });
  });

  group('Pre-order', () {
    test('FIFO murni berdasar createdAt — paid TIDAK mempengaruhi urutan',
        () async {
      await db.addPreorderEntry(
          id: 'p-bayar',
          productId: 'prod1',
          productUnitId: 'unit1',
          customerName: 'Budi (bayar duluan)',
          qtyOrdered: 1,
          paid: true);
      // Paksa lebih baru scr eksplisit spy independen dari kecepatan test.
      await (db.update(db.preorderEntries)..where((t) => t.id.equals('p-bayar')))
          .write(PreorderEntriesCompanion(
              createdAt: Value(DateTime.now().add(const Duration(minutes: 5)))));
      await db.addPreorderEntry(
          id: 'p-titip-saja',
          productId: 'prod1',
          productUnitId: 'unit1',
          customerName: 'Ani (titip tabung saja, blm bayar)',
          qtyOrdered: 1,
          depositQty: 1,
          paid: false);

      final list = await db.watchPreorderEntries(productId: 'prod1').first;
      expect(list.map((e) => e.id).toList(), ['p-titip-saja', 'p-bayar'],
          reason: 'yang titip duluan harus di depan walau belum bayar — '
              'paid tidak boleh ikut menentukan urutan');
    });

    test('fulfill & cancel keduanya mengeluarkan entri dari antrian aktif',
        () async {
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'prod1',
          productUnitId: 'unit1',
          customerName: 'A',
          qtyOrdered: 1);
      await db.addPreorderEntry(
          id: 'p2',
          productId: 'prod1',
          productUnitId: 'unit1',
          customerName: 'B',
          qtyOrdered: 1);

      await db.fulfillPreorderEntry('p1');
      await db.cancelPreorderEntry('p2');

      final active =
          await db.watchPreorderEntries(productId: 'prod1').first;
      expect(active, isEmpty);

      final all = await db
          .watchPreorderEntries(productId: 'prod1', includeClosed: true)
          .first;
      expect(all, hasLength(2));
    });
  });

  group('Badge gabungan', () {
    test('watchLaciMejaOpenCount menjumlahkan 3 kategori & reaktif', () async {
      final txId = await seedTransaction('tx1');
      expect(await db.watchLaciMejaOpenCount().first, 0);

      await db.addLeftBehindItem(
          id: 'l1', transactionId: txId, itemName: 'A', jenis: 'titip');
      await db.addBorrowedItem(
          id: 'b1', transactionId: txId, itemName: 'B', qty: 1);
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'prod1',
          productUnitId: 'unit1',
          customerName: 'C',
          qtyOrdered: 1);

      expect(await db.watchLaciMejaOpenCount().first, 3);

      await db.markLeftBehindCollected('l1');
      expect(await db.watchLaciMejaOpenCount().first, 2);
    });
  });

  group('Proposal (client -> host, pola Item 40 paralel)', () {
    test('dumpLaciMejaProposals hanya membawa baris locallyModified=true',
        () async {
      final txId = await seedTransaction('tx1');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: txId,
          itemName: 'A',
          jenis: 'titip',
          locallyModified: true);
      await db.addLeftBehindItem(
          id: 'l2',
          transactionId: txId,
          itemName: 'B',
          jenis: 'titip',
          locallyModified: false);

      final dump = await db.dumpLaciMejaProposals();
      expect(dump['left_behind_items'], hasLength(1));
      expect(dump['left_behind_items']!.single['id'], 'l1');
    });

    test('applyLaciMejaProposals menulis hanya id yang di-approve, '
        'locallyModified dipaksa false', () async {
      final txId = await seedTransaction('tx1');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: txId,
          itemName: 'A',
          jenis: 'titip',
          locallyModified: true);
      await db.addLeftBehindItem(
          id: 'l2',
          transactionId: txId,
          itemName: 'B',
          jenis: 'titip',
          locallyModified: true);

      final dump = await db.dumpLaciMejaProposals();
      final count = await db.applyLaciMejaProposals(
          dump, {'left_behind_items': {'l1'}});
      expect(count, 1);

      final l1 =
          await (db.select(db.leftBehindItems)..where((t) => t.id.equals('l1')))
              .getSingle();
      expect(l1.locallyModified, isFalse);
    });
  });
}
