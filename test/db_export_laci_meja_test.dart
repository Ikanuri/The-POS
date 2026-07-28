import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug ditemukan user (28 Juli): backup penuh (Pengaturan > Backup) dan
/// Alihkan Owner (`dumpAllTables`/`restoreFromDump`, dipakai
/// `DbExportService.exportPortable`/`exportOwnerTransfer`/`restore`) TIDAK
/// menyertakan 3 tabel Laci Meja (`left_behind_items`, `borrowed_items`,
/// `preorder_entries`) — beda dari sync LAN (`dumpSince`,
/// `dumpLaciMejaProposals`) yang sudah benar. Restore/Alihkan Owner diam-diam
/// menghapus semua catatan titip/ketinggalan, pinjaman belum kembali, dan
/// pre-order belum terpenuhi.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('dumpAllTables + restoreFromDump membawa serta 3 tabel Laci Meja '
      '(left_behind_items, borrowed_items, preorder_entries)', () async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'tx1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.addLeftBehindItem(
        id: 'l1', transactionId: 'tx1', itemName: 'Payung', jenis: 'ketinggalan');
    await db.addBorrowedItem(
        id: 'b1', transactionId: 'tx1', itemName: 'Galon Aqua', qty: 3);
    await db.addPreorderEntry(
        id: 'p1',
        productId: 'prod1',
        productUnitId: 'unit1',
        customerName: 'Budi',
        qtyOrdered: 2,
        depositQty: 1);

    final dump = await db.dumpAllTables();

    // Simulasikan restore ke DB baru yang kosong (spt device penerima
    // Alihkan Owner / restore backup).
    final freshDb = AppDatabase(NativeDatabase.memory());
    addTearDown(() => freshDb.close());
    await freshDb.restoreFromDump(dump);

    final restoredLeftBehind = await freshDb.watchLeftBehindItems().first;
    final restoredBorrowed =
        await (freshDb.select(freshDb.borrowedItems)).get();
    final restoredPreorder =
        await freshDb.watchPreorderEntries().first;

    expect(restoredLeftBehind, hasLength(1),
        reason: 'left_behind_items harus ikut ter-restore');
    expect(restoredBorrowed, hasLength(1),
        reason: 'borrowed_items harus ikut ter-restore');
    expect(restoredPreorder, hasLength(1),
        reason: 'preorder_entries harus ikut ter-restore');
  });
}
