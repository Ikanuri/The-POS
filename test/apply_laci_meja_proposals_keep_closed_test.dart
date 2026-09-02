import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Audit sync pre-order (sesi 2 Sep 2026, permintaan user "deep debug sync
/// pre-order"): `applyLaciMejaProposals` memakai `INSERT OR REPLACE` — SELURUH
/// baris host ditimpa versi klien. Skenario regresi nyata: klien mengedit
/// entri (locally_modified=1, versi TERBUKA), lalu owner MEMENUHI/menutup
/// entri itu di host SEBELUM menyetujui usulan klien. Begitu owner approve,
/// `fulfilled_at` host ditimpa null → entri yang sudah selesai TERBUKA LAGI
/// (event 'penuhi'-nya tetap ada, jadi sisa 0 tapi status terbuka).
/// `filterUnchangedLaciMejaProposals` TIDAK melindungi (barisnya memang beda).
/// Fix: kolom status-tutup (satu arah) dipertahankan dari host kalau usulan
/// masih null; `qty_returned` ambil yang terbesar.
void main() {
  late AppDatabase host;
  late AppDatabase client;

  Future<void> seedTx(AppDatabase db) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'A1-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
  }

  setUp(() async {
    host = AppDatabase(NativeDatabase.memory());
    client = AppDatabase(NativeDatabase.memory());
    await seedTx(host);
    await seedTx(client);
  });
  tearDown(() async {
    await host.close();
    await client.close();
  });

  Future<void> approveAll(Map<String, List<Map<String, Object?>>> proposals) =>
      host.applyLaciMejaProposals(proposals, {
        for (final e in proposals.entries)
          e.key: e.value.map((r) => r['id'] as String).toSet(),
      });

  test(
      'pre-order: owner memenuhi di host, lalu approve usulan edit klien '
      '(versi terbuka) -> edit masuk TAPI fulfilled_at TIDAK dikosongkan',
      () async {
    for (final db in [host, client]) {
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'prod1',
          productUnitId: 'unit1',
          transactionId: 'tx1',
          customerName: 'Ari',
          qtyOrdered: 1,
          depositQty: 1);
    }
    // Klien mengedit jaminan (belum tahu host sudah memenuhi).
    await client.editPreorderEntry('p1',
        depositQty: 2,
        changeSummary: 'jaminan 1 -> 2',
        locallyModified: true,
        eventId: 'ev-edit',
        deviceCode: 'A1');
    // Owner memenuhi penuh di host.
    await host.fulfillPreorderQty('p1', 1, eventId: 'ev-full', deviceCode: 'O1');

    final proposals = await client.dumpLaciMejaProposals();
    expect(proposals['preorder_entries'], hasLength(1));
    await approveAll(proposals);

    final row = await (host.select(host.preorderEntries)
          ..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(row.depositQty, 2, reason: 'edit klien yang disetujui tetap masuk');
    expect(row.fulfilledAt, isNotNull,
        reason: 'status selesai host TIDAK boleh dibuka lagi oleh approve');
  });

  test(
      'pinjaman: host sudah terima kembali sebagian (qty_returned 3) -> approve '
      'usulan klien yang masih 0 tidak memundurkan cache', () async {
    for (final db in [host, client]) {
      await db.addBorrowedItem(
          id: 'b1', transactionId: 'tx1', itemName: 'Krat', qty: 4);
    }
    await client.editBorrowedItem('b1',
        note: 'krat merah', locallyModified: true, eventId: 'ev-edit');
    await host.returnBorrowedItemQty('b1', 3, eventId: 'ev-ret');

    await approveAll(await client.dumpLaciMejaProposals());

    final row = await (host.select(host.borrowedItems)
          ..where((t) => t.id.equals('b1')))
        .getSingle();
    expect(row.note, 'krat merah');
    expect(row.qtyReturned, 3);
  });

  test(
      'titip/ketinggalan: sudah diambil di host -> approve usulan edit klien '
      'tidak menghapus collected_at', () async {
    for (final db in [host, client]) {
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Payung',
          jenis: 'titip',
          qty: 1);
    }
    await client.editLeftBehindItem('l1',
        note: 'payung biru', locallyModified: true, eventId: 'ev-edit');
    await host.collectLeftBehindQty('l1', 1, total: 1, eventId: 'ev-take');

    await approveAll(await client.dumpLaciMejaProposals());

    final row = await (host.select(host.leftBehindItems)
          ..where((t) => t.id.equals('l1')))
        .getSingle();
    expect(row.note, 'payung biru');
    expect(row.collectedAt, isNotNull);
  });

  test('usulan klien yang MENUTUP entri (cancelled_at terisi) tetap diterapkan',
      () async {
    for (final db in [host, client]) {
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'prod1',
          productUnitId: 'unit1',
          transactionId: 'tx1',
          customerName: 'Ari',
          qtyOrdered: 1);
    }
    await client.cancelPreorderEntry('p1',
        locallyModified: true, eventId: 'ev-cancel');

    await approveAll(await client.dumpLaciMejaProposals());

    final row = await (host.select(host.preorderEntries)
          ..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(row.cancelledAt, isNotNull);
  });
}
