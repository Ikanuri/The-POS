import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// PLAN.md Item 54 — log kejadian Laci Meja (ambil/kembali/penuhi/batal)
/// sebagai SUMBER KEBENARAN sisa, menggantikan "kurangi kolom qty".
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedTx(String id) => db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          localId: id,
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ),
      );

  group('Titip/Ketinggalan — ambil parsial', () {
    test('ambil 3 dari 5 -> BELUM selesai, sisa tercatat di log', () async {
      await seedTx('tx1');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Gas LPG 3kg',
          jenis: 'titip',
          qty: 5);

      await db.collectLeftBehindQty('l1', 3, total: 5);

      final row = await (db.select(db.leftBehindItems)
            ..where((t) => t.id.equals('l1')))
          .getSingle();
      expect(row.collectedAt, isNull,
          reason: 'baru 3 dari 5 — entri belum boleh ditutup');
      expect((await db.getLaciMejaTakenQty(['l1']))['l1'], 3);
    });

    test('ambil 3 lalu 2 -> total 5, entri ditutup, log 2 baris', () async {
      await seedTx('tx1');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Gas LPG 3kg',
          jenis: 'titip',
          qty: 5);

      await db.collectLeftBehindQty('l1', 3, total: 5, eventId: 'e1');
      await db.collectLeftBehindQty('l1', 2, total: 5, eventId: 'e2');

      final row = await (db.select(db.leftBehindItems)
            ..where((t) => t.id.equals('l1')))
          .getSingle();
      expect(row.collectedAt, isNotNull);
      expect((await db.getLaciMejaTakenQty(['l1']))['l1'], 5);
      final events = (await db.getLaciMejaEventsForEntries(['l1']))['l1']!;
      expect(events, hasLength(2),
          reason: 'tiap momen ambil = 1 baris log sendiri');
      expect(events.map((e) => e.qty).toList(), [3, 2],
          reason: 'urut terlama dulu, spt Riwayat Pembayaran');
    });

    test('entri lama tanpa qty (total null) -> sekali ambil langsung tutup',
        () async {
      await seedTx('tx1');
      await db.addLeftBehindItem(
          id: 'l1', transactionId: 'tx1', itemName: 'Payung', jenis: 'titip');

      await db.collectLeftBehindQty('l1', 0, total: null);

      final row = await (db.select(db.leftBehindItems)
            ..where((t) => t.id.equals('l1')))
          .getSingle();
      expect(row.collectedAt, isNotNull,
          reason: 'tanpa angka acuan, perilaku lama (tutup langsung) dipakai');
    });

    test('markLeftBehindCollected tetap mencatat baris log', () async {
      await seedTx('tx1');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Payung',
          jenis: 'titip',
          qty: 2);

      await db.markLeftBehindCollected('l1', sisaQty: 2);

      final events = (await db.getLaciMejaEventsForEntries(['l1']))['l1']!;
      expect(events, hasLength(1));
      expect(events.single.aksi, 'ambil');
      expect(events.single.qty, 2);
    });
  });

  group('Pinjaman — qtyReturned jadi cache dari log', () {
    test('kembali bertahap 3 lalu 1 dari 4 -> lunas, 2 baris log', () async {
      await seedTx('tx1');
      await db.addBorrowedItem(
          id: 'b1', transactionId: 'tx1', itemName: 'Krat botol', qty: 4);

      await db.returnBorrowedItemQty('b1', 3, eventId: 'e1');
      var row = await (db.select(db.borrowedItems)
            ..where((t) => t.id.equals('b1')))
          .getSingle();
      expect(row.qtyReturned, 3);
      expect(row.fullyReturnedAt, isNull);

      await db.returnBorrowedItemQty('b1', 1, eventId: 'e2');
      row = await (db.select(db.borrowedItems)..where((t) => t.id.equals('b1')))
          .getSingle();
      expect(row.qtyReturned, 4);
      expect(row.fullyReturnedAt, isNotNull);

      final events = (await db.getLaciMejaEventsForEntries(['b1']))['b1']!;
      expect(events.map((e) => e.qty).toList(), [3, 1]);
    });

    test('qtyReturned DIHITUNG ULANG dari log, bukan += delta — baris log '
        'yang datang dari device lain ikut terhitung', () async {
      await seedTx('tx1');
      await db.addBorrowedItem(
          id: 'b1', transactionId: 'tx1', itemName: 'Krat botol', qty: 5);

      // Seolah baris log dari device lain sudah lebih dulu masuk lewat sync,
      // TANPA sempat memperbarui kolom cache-nya.
      await db.recordLaciMejaEvent(
          id: 'dari-device-lain',
          entityType: 'pinjaman',
          entryId: 'b1',
          aksi: 'kembali',
          qty: 2);

      await db.returnBorrowedItemQty('b1', 1, eventId: 'e-lokal');

      final row = await (db.select(db.borrowedItems)
            ..where((t) => t.id.equals('b1')))
          .getSingle();
      expect(row.qtyReturned, 3,
          reason: '2 (device lain) + 1 (lokal) — kalau masih "+= delta" '
              'hasilnya cuma 1 dan pengembalian device lain hilang');
    });
  });

  group('Pre-order — penuhi parsial & batal', () {
    test('penuhi 3 dari 5 -> belum selesai; sisa 2 -> selesai', () async {
      await seedTx('tx1');
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Warung Sari',
          qtyOrdered: 5,
          transactionId: 'tx1');

      await db.fulfillPreorderQty('p1', 3, eventId: 'e1');
      var row = await (db.select(db.preorderEntries)
            ..where((t) => t.id.equals('p1')))
          .getSingle();
      expect(row.fulfilledAt, isNull);

      await db.fulfillPreorderQty('p1', 2, eventId: 'e2');
      row = await (db.select(db.preorderEntries)
            ..where((t) => t.id.equals('p1')))
          .getSingle();
      expect(row.fulfilledAt, isNotNull);
    });

    test('fulfillPreorderEntry (penuhi semua) mencatat SISA-nya saja, '
        'tidak menggandakan yang sudah dipenuhi', () async {
      await seedTx('tx1');
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Warung Sari',
          qtyOrdered: 5,
          transactionId: 'tx1');

      await db.fulfillPreorderQty('p1', 3, eventId: 'e1');
      await db.fulfillPreorderEntry('p1', eventId: 'e2');

      expect((await db.getLaciMejaTakenQty(['p1']))['p1'], 5,
          reason: '3 + sisa 2, bukan 3 + 5');
    });

    test('batal dicatat sbg baris log qty 0 dan TIDAK dihitung sbg dipenuhi',
        () async {
      await seedTx('tx1');
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Sari',
          qtyOrdered: 5,
          transactionId: 'tx1');

      await db.fulfillPreorderQty('p1', 2, eventId: 'e1');
      await db.cancelPreorderEntry('p1', eventId: 'e2');

      expect((await db.getLaciMejaTakenQty(['p1']))['p1'], 2,
          reason: 'pembatalan menutup sisa tanpa barang berpindah');
      final events = (await db.getLaciMejaEventsForEntries(['p1']))['p1']!;
      expect(events.last.aksi, 'batal');
      expect(events.last.qty, 0);
    });
  });

  group('Log gabungan (layar Riwayat)', () {
    test('ketiga kategori tampil urut TERBARU dulu, dgn nama barang & '
        'pelanggan', () async {
      await seedTx('tx1');
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: 'P1', name: 'Gas LPG 3kg'));
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Payung',
          jenis: 'titip',
          customerNameText: 'Bu Rina',
          qty: 1);
      await db.addBorrowedItem(
          id: 'b1',
          transactionId: 'tx1',
          itemName: 'Krat botol',
          qty: 2,
          customerNameText: 'Pak Budi');
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Warung Sari',
          qtyOrdered: 5,
          transactionId: 'tx1');

      await db.collectLeftBehindQty('l1', 1, total: 1, eventId: 'e1');
      await db.returnBorrowedItemQty('b1', 2, eventId: 'e2');
      await db.fulfillPreorderQty('p1', 3, eventId: 'e3');

      final log = await db.watchLaciMejaEventLog().first;
      expect(log, hasLength(3));
      expect(log.map((e) => e.entityType).toSet(),
          {'titip', 'pinjaman', 'preorder'});

      final pre = log.firstWhere((e) => e.entityType == 'preorder');
      expect(pre.itemName, 'Gas LPG 3kg',
          reason: 'pre-order menyimpan productId, nama produk di-join');
      expect(pre.qty, 3);

      final titip = log.firstWhere((e) => e.entityType == 'titip');
      expect(titip.itemName, 'Payung');
      expect(titip.transactionId, 'tx1');
    });

    test('nama pelanggan di log ikut nota TERKINI, bukan salinan beku',
        () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx1',
            localId: 'tx1',
            status: 'lunas',
            total: 1000,
            paid: 1000,
            changeAmount: 0,
            paymentMethod: 'tunai',
            customerName: const Value('Pelanggan Umum'),
          ));
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Payung',
          jenis: 'titip',
          customerNameText: 'Pelanggan Umum',
          qty: 1);
      await db.collectLeftBehindQty('l1', 1, total: 1, eventId: 'e1');

      await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'c1', name: 'Warung Sari'));
      await (db.update(db.transactions)..where((t) => t.id.equals('tx1')))
          .write(const TransactionsCompanion(customerId: Value('c1')));

      final log = await db.watchLaciMejaEventLog().first;
      expect(log.single.customerName, 'Warung Sari');
    });
  });
}
