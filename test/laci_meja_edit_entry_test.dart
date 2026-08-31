import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Fitur baru (permintaan user): "semua atribut laci meja itu buat editable.
/// Ini mencegah supaya atribut yang salah tidak perlu dipenuhi lalu buat
/// ulang, agar tidak merusak audit history."
///
/// Dua hal yang dijaga di sini:
///  1. `lastEditedAt` HANYA terisi karena edit — bukan karena aksi
///     operasional biasa (ambil/kembali/penuhi) yang juga menyentuh
///     `updatedAt`. Kalau tidak, baris "Terakhir diedit" di struk bakal
///     muncul untuk entri yang tidak pernah diedit sama sekali.
///  2. Tiap edit meninggalkan jejak di `laci_meja_events` (aksi 'edit'),
///     supaya riwayat bisa menjelaskan kenapa angkanya berubah.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedTx(String id) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: id,
            localId: id,
            status: 'lunas',
            total: 10000,
            paid: 10000,
            changeAmount: 0,
            paymentMethod: 'tunai',
          ));

  test('edit pinjaman: qty/nama/catatan tersimpan + lastEditedAt distempel',
      () async {
    await seedTx('tx1');
    await db.addBorrowedItem(
        id: 'b1',
        transactionId: 'tx1',
        itemName: 'Galon',
        qty: 3,
        customerNameText: 'Bu Ani');

    final sebelum = await (db.select(db.borrowedItems)
          ..where((t) => t.id.equals('b1')))
        .getSingle();
    expect(sebelum.lastEditedAt, isNull,
        reason: 'entri baru belum pernah diedit');

    await db.editBorrowedItem('b1',
        customerNameText: 'Bu Ani Wijaya',
        qty: 5,
        note: 'salah input, harusnya 5',
        changeSummary: 'jumlah 3 -> 5');

    final sesudah = await (db.select(db.borrowedItems)
          ..where((t) => t.id.equals('b1')))
        .getSingle();
    expect(sesudah.qty, 5);
    expect(sesudah.customerNameText, 'Bu Ani Wijaya');
    expect(sesudah.note, 'salah input, harusnya 5');
    expect(sesudah.lastEditedAt, isNotNull);

    final events = await (db.select(db.laciMejaEvents)
          ..where((t) => t.entryId.equals('b1')))
        .get();
    expect(events, hasLength(1));
    expect(events.single.aksi, 'edit');
    expect(events.single.qty, 0,
        reason: 'edit tidak memindahkan barang fisik apa pun');
    expect(events.single.note, contains('3 -> 5'));
  });

  test(
      'aksi operasional (kembali sebagian) TIDAK menstempel lastEditedAt '
      'walau menyentuh updatedAt', () async {
    await seedTx('tx1');
    await db.addBorrowedItem(
        id: 'b1', transactionId: 'tx1', itemName: 'Galon', qty: 3);

    await db.returnBorrowedItemQty('b1', 1);

    final row = await (db.select(db.borrowedItems)
          ..where((t) => t.id.equals('b1')))
        .getSingle();
    expect(row.qtyReturned, 1);
    expect(row.lastEditedAt, isNull,
        reason: 'pengembalian bukan "edit isi entri" — kalau ikut distempel, '
            'struk akan menampilkan "Terakhir diedit" untuk entri yang tidak '
            'pernah diedit');
  });

  test('menurunkan qty pinjaman sampai <= yang sudah kembali -> status lunas',
      () async {
    await seedTx('tx1');
    await db.addBorrowedItem(
        id: 'b1', transactionId: 'tx1', itemName: 'Galon', qty: 5);
    await db.returnBorrowedItemQty('b1', 2);

    // Ternyata yang dipinjam memang cuma 2, bukan 5 (salah input).
    await db.editBorrowedItem('b1', qty: 2);

    final row = await (db.select(db.borrowedItems)
          ..where((t) => t.id.equals('b1')))
        .getSingle();
    expect(row.fullyReturnedAt, isNotNull,
        reason: 'qty turun jadi 2 & yang kembali sudah 2 -> pinjaman selesai');
  });

  test('edit titip/ketinggalan & pre-order juga mencatat log + lastEditedAt',
      () async {
    await seedTx('tx1');
    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: 'tx1',
        itemName: 'Payung',
        jenis: 'ketinggalan',
        qty: 1);
    await db.addPreorderEntry(
        id: 'po1',
        productId: 'P1',
        productUnitId: 'U1',
        customerName: 'Pak Budi',
        qtyOrdered: 2,
        transactionId: 'tx1');

    await db.editLeftBehindItem('l1', qty: 2, changeSummary: 'jumlah 1 -> 2');
    await db.editPreorderEntry('po1',
        qtyOrdered: 4,
        depositQty: 4,
        phone: '0812',
        changeSummary: 'jumlah 2 -> 4');

    final l = await (db.select(db.leftBehindItems)
          ..where((t) => t.id.equals('l1')))
        .getSingle();
    expect(l.qty, 2);
    expect(l.lastEditedAt, isNotNull);

    final p = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(p.qtyOrdered, 4);
    expect(p.depositQty, 4);
    expect(p.phone, '0812');
    expect(p.lastEditedAt, isNotNull);

    final aksi = (await db.select(db.laciMejaEvents).get())
        .map((e) => e.aksi)
        .toList();
    expect(aksi, ['edit', 'edit']);
  });

  test('pin pinjaman: kartu tersemat naik ke atas walau dibuat paling akhir',
      () async {
    await seedTx('tx1');
    await db.into(db.borrowedItems).insert(BorrowedItemsCompanion.insert(
          id: 'lama',
          transactionId: 'tx1',
          itemName: 'Galon',
          qty: 1,
          createdAt: Value(DateTime(2026, 1, 1)),
        ));
    await db.into(db.borrowedItems).insert(BorrowedItemsCompanion.insert(
          id: 'baru',
          transactionId: 'tx1',
          itemName: 'Tabung',
          qty: 1,
          createdAt: Value(DateTime(2026, 6, 1)),
        ));

    var urutan = (await db.watchBorrowedItems().first).map((e) => e.id).toList();
    expect(urutan, ['lama', 'baru'], reason: 'default FIFO createdAt');

    await db.setBorrowedPinned(['baru'], true);
    urutan = (await db.watchBorrowedItems().first).map((e) => e.id).toList();
    expect(urutan, ['baru', 'lama'],
        reason: 'yang disematkan naik ke atas, mengabaikan urutan createdAt');

    // Pin TIDAK boleh dianggap "edit isi entri".
    final row = await (db.select(db.borrowedItems)
          ..where((t) => t.id.equals('baru')))
        .getSingle();
    expect(row.lastEditedAt, isNull);

    await db.setBorrowedPinned(['baru'], false);
    urutan = (await db.watchBorrowedItems().first).map((e) => e.id).toList();
    expect(urutan, ['lama', 'baru']);
  });
}
