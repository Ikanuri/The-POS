import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Bug dilaporkan user: "hutang/pre-order sudah dilunasi oleh host, di client
/// masih belum terlunasi/terpenuhi — meskipun itu sudah disync".
///
/// Akar masalah (terbukti reproduksi, BUKAN dugaan): usulan Laci Meja dari
/// klien memuat SELURUH baris apa adanya & `applyLaciMejaProposals`
/// meng-`INSERT OR REPLACE` bulat-bulat. Kasir yang cuma mengubah field LAIN
/// (mis. catatan) ikut membawa `preorder_entries.paid` miliknya yang sudah
/// BASI — begitu owner menekan "Terapkan", pelunasan DP yang sudah tercatat
/// di host DIKEMBALIKAN jadi "belum lunas", lalu status basi itu tersebar
/// balik ke klien lewat sync master data. `fulfilled_at`/`cancelled_at`/
/// `qty_returned` sudah lebih dulu dijaga di fungsi yang sama (audit sesi 2
/// Sep 2026), `paid` TERLEWAT.
///
/// Efeknya permanen & tidak bisa diperbaiki lewat app: baris notanya sendiri
/// TETAP terlanjur naik ke harga asli, jadi `getPreorderDepositOwed` sudah 0
/// → tombol "Lunasi" no-op & entri tidak pernah jadi kandidat "Pelunasi
/// Pre-order" di keranjang (disaring `owed <= 0`).
void main() {
  late AppDatabase host;
  late AppDatabase client;

  setUp(() {
    host = AppDatabase(NativeDatabase.memory());
    client = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await host.close();
    await client.close();
  });

  /// Nota pre-order: satu baris item yang harganya DIKUNCI Rp 0 saat checkout
  /// (`originalPrice` 50.000) — pola persis `item_entry_sheet.dart` utk
  /// pre-order tanpa DP, lihat dok `PreorderEntries.transactionItemId`.
  Future<void> seed(AppDatabase db, {String? transactionItemId = 'ti2'}) async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P1', name: 'Gula Pasir'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx2',
          localId: 'K1-2',
          status: 'lunas',
          total: 0,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(
        TransactionItemsCompanion.insert(
            id: 'ti2',
            transactionId: 'tx2',
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: 0,
            originalPrice: 50000,
            subtotal: 0));
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
        id: 'po1',
        customerName: 'Budi',
        productId: 'P1',
        productUnitId: 'U1',
        qtyOrdered: 1,
        transactionId: const Value('tx2'),
        transactionItemId: Value(transactionItemId)));
  }

  /// Owner menekan "Terapkan" atas SEMUA usulan yang lolos filter host.
  Future<void> ownerApprovesAll(AppDatabase h, AppDatabase c) async {
    final proposals = await c.dumpLaciMejaProposals();
    final filtered = await h.filterUnchangedLaciMejaProposals(proposals);
    await h.applyLaciMejaProposals(filtered, {
      for (final e in filtered.entries)
        e.key: e.value.map((r) => r['id'] as String).toSet(),
    });
  }

  /// Sync host → klien, jalur & urutan sama dgn `LanSyncService.syncToHost`.
  Future<void> syncDown(AppDatabase h, AppDatabase c, DateTime since) async {
    final dump = await h.dumpSince(since);
    final touched = <String>{};
    for (final entry in dump.entries) {
      if (!LanSyncService.clientMergeableTables.contains(entry.key)) continue;
      await c.mergeRows(entry.key, entry.value,
          LanSyncService.appendOnlyTables.contains(entry.key));
      for (final r in entry.value) {
        final txId = entry.key == 'transactions' ? r['id'] : r['transaction_id'];
        if (txId is String) touched.add(txId);
      }
    }
    await c.reconcileTransactionsByIds(touched);
  }

  /// Sync klien → host utk tabel append-only (jalur unggah `syncToHost`,
  /// dijalankan host SEBELUM owner meninjau antrian usulan Laci Meja).
  Future<void> syncUpAppendOnly(
      AppDatabase c, AppDatabase h, DateTime since) async {
    final dump = await c.dumpSince(since, includeMasterData: false);
    final touched = <String>{};
    for (final entry in dump.entries) {
      if (!LanSyncService.appendOnlyTables.contains(entry.key)) continue;
      await h.mergeRows(entry.key, entry.value, true);
      for (final r in entry.value) {
        final txId = entry.key == 'transactions' ? r['id'] : r['transaction_id'];
        if (txId is String) touched.add(txId);
      }
    }
    await h.reconcileTransactionsByIds(touched);
  }

  test(
      'usulan BASI klien TIDAK boleh mengembalikan DP pre-order yang sudah '
      'dilunasi di host jadi belum lunas', () async {
    await seed(host);
    await seed(client);

    // Kasir mengubah CATATAN saja (field lain sama sekali tidak disentuh) —
    // cukup utk menandai baris ini masuk antrian usulan.
    await (client.update(client.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .write(PreorderEntriesCompanion(
      note: const Value('catatan dari kasir'),
      locallyModified: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));

    // Owner melunasi DP di HOST.
    final owed = await host.collectPreorderDeposit(
        preorderEntryId: 'po1',
        amount: 50000,
        method: 'tunai',
        kasirId: 'OWNER');
    expect(owed, 50000, reason: 'prakondisi: DP Rp50.000 terkumpul di host');

    await ownerApprovesAll(host, client);

    final hPo = await (host.select(host.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(hPo.paid, isTrue,
        reason: 'tanpa fix: INSERT OR REPLACE usulan klien menimpa paid=true '
            'host dgn paid=false yang basi — pelunasan hilang di HOST sendiri');
    // Catatan kasir TETAP diterapkan — usulannya memang sah, yang dijaga
    // hanya kolom status pelunasan.
    expect(hPo.note, 'catatan dari kasir');

    await syncDown(host, client, DateTime(2000));
    final cPo = await (client.select(client.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(cPo.paid, isTrue,
        reason: 'klien harus akhirnya ikut melihat DP sudah lunas');
  });

  test(
      'pembatalan DP SUNGGUHAN dari klien (voidPayment) TETAP sampai ke host '
      '— fix tidak boleh mengunci paid=true selamanya', () async {
    await seed(host);

    // Host melunasi DP lalu klien menerima keadaan itu lewat sync.
    await host.collectPreorderDeposit(
        preorderEntryId: 'po1',
        amount: 50000,
        method: 'tunai',
        kasirId: 'OWNER');
    await syncDown(host, client, DateTime(2000));
    var cPo = await (client.select(client.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(cPo.paid, isTrue, reason: 'prakondisi: klien sudah tahu DP lunas');

    final clientUploadWatermark = DateTime.now();
    // `updated_at` disimpan dalam DETIK — beri jarak supaya last-write-wins
    // `transaction_items` (Item 63) benar-benar melihat versi klien lebih baru.
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // Kasir membatalkan pembayaran DP itu di device-nya sendiri.
    final cPay = await (client.select(client.transactionPayments)
          ..where((t) => t.transactionId.equals('tx2')))
        .getSingle();
    await client.voidPayment(cPay.id, locallyModified: true, deviceCode: 'K1');
    cPo = await (client.select(client.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(cPo.paid, isFalse, reason: 'prakondisi: klien membatalkan DP');

    // Unggah append-only dulu (baris nota kembali ke Rp 0), baru owner
    // meninjau antrian usulan Laci Meja — urutan persis seperti di app.
    await syncUpAppendOnly(client, host, clientUploadWatermark);
    await ownerApprovesAll(host, client);

    final hPo = await (host.select(host.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(hPo.paid, isFalse,
        reason: 'pembatalan DP yang SUNGGUHAN (baris notanya ikut balik ke '
            'Rp 0) harus tetap diterima host — bukan dikunci paid=true');
  });

  test(
      'usulan BASI klien TIDAK boleh menghidupkan kembali DP yang sudah '
      'dibatalkan di host (arah sebaliknya)', () async {
    await seed(host);
    await seed(client);

    // Kedua device sempat melihat DP lunas.
    await host.collectPreorderDeposit(
        preorderEntryId: 'po1',
        amount: 50000,
        method: 'tunai',
        kasirId: 'OWNER');
    await client.collectPreorderDeposit(
        preorderEntryId: 'po1',
        amount: 50000,
        method: 'tunai',
        kasirId: 'K1');

    // Owner membatalkan DP itu di host.
    final hPay = await (host.select(host.transactionPayments)
          ..where((t) => t.transactionId.equals('tx2')))
        .getSingle();
    await host.voidPayment(hPay.id);
    var hPo = await (host.select(host.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(hPo.paid, isFalse, reason: 'prakondisi: host sudah membatalkan DP');

    // Klien (belum tahu pembatalan itu) mengusulkan edit catatan — bawa
    // serta paid=true miliknya yang sudah basi.
    await (client.update(client.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .write(PreorderEntriesCompanion(
      note: const Value('catatan dari kasir'),
      locallyModified: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));
    await ownerApprovesAll(host, client);

    hPo = await (host.select(host.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(hPo.paid, isFalse,
        reason: 'baris nota host masih Rp 0 (DP belum tertagih) — usulan basi '
            'tidak boleh menandainya lunas');
  });

  test(
      'entri tanpa baris nota tertaut (transactionItemId null) — nilai host '
      'dipertahankan, tidak error', () async {
    await seed(host, transactionItemId: null);
    await seed(client, transactionItemId: null);

    // Entri "Jadikan Pre-order" dari struk dibuat dgn paid=true & tanpa
    // baris nota tertaut (lihat `receipt_screen.dart`).
    await (host.update(host.preorderEntries)..where((t) => t.id.equals('po1')))
        .write(const PreorderEntriesCompanion(paid: Value(true)));
    await (client.update(client.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .write(PreorderEntriesCompanion(
      note: const Value('catatan dari kasir'),
      paid: const Value(false),
      locallyModified: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));

    await ownerApprovesAll(host, client);

    final hPo = await (host.select(host.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(hPo.paid, isTrue,
        reason: 'tidak ada fakta pembanding & tidak ada jalur app yang '
            'mengubah paid utk entri tanpa baris nota — nilai host dipertahankan');
    expect(hPo.note, 'catatan dari kasir');
  });
}
