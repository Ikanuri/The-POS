import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Item 52 ("Laci Meja") — sinkronisasi end-to-end asli (real HTTP loopback,
/// bukan simulasi payload manual, sesuai standar test Networking di
/// CLAUDE.md): (1) host->klien AUTO-MERGE (pola sama persis dgn
/// products/customers), (2) klien->host lewat antrian USULAN terpisah
/// (pola sama persis dgn Item 40, tapi PARALEL — tidak menyentuh
/// `_pendingProposals` produk sama sekali).
Future<T> _withRealHttp<T>(Future<T> Function() body) => HttpOverrides.runZoned(
      body,
      createHttpClient: (context) => Zone.root.run(() {
        final prevGlobal = HttpOverrides.current;
        HttpOverrides.global = null;
        try {
          return HttpClient(context: context);
        } finally {
          HttpOverrides.global = prevGlobal;
        }
      }),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/network_info'),
          (call) async => call.method == 'wifiIPAddress' ? '127.0.0.1' : null);

  tearDown(() async {
    await LanSyncService.stopHost();
    LanSyncService.debugClearProposals();
    LanSyncService.debugClearLaciMejaProposals();
  });

  Future<String> seedTransaction(AppDatabase db, String id) async {
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

  test(
      'host -> klien: entri Laci Meja dibuat OWNER (locallyModified=false) '
      'AUTO-MERGE ke klien tanpa perlu review', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    final txId = await seedTransaction(hostDb, 'tx1');
    await hostDb.addLeftBehindItem(
        id: 'l1', transactionId: txId, itemName: 'Payung', jenis: 'titip');
    await hostDb.addBorrowedItem(
        id: 'b1', transactionId: txId, itemName: 'Galon', qty: 2);
    await hostDb.addPreorderEntry(
        id: 'p1',
        productId: 'prod1',
        productUnitId: 'unit1',
        customerName: 'Budi',
        qtyOrdered: 1);

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    expect(await clientDb.watchLeftBehindItems().first, hasLength(1));
    expect(await clientDb.watchBorrowedItems().first, hasLength(1));
    expect(
        await clientDb
            .watchPreorderEntries(productId: 'prod1')
            .first,
        hasLength(1));
  });

  test(
      'klien -> host: entri dibuat device NON-OWNER (locallyModified=true) '
      'TIDAK auto-merge, masuk antrian usulan terpisah menunggu approve',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    final txId = await seedTransaction(clientDb, 'tx1');
    // Transaksi ini JUGA sudah ada di host (disinkron duluan lewat jalur
    // "Transaksi" — lihat test terpisah di bawah utk skenario BELUM ada).
    await seedTransaction(hostDb, 'tx1');
    await clientDb.addLeftBehindItem(
        id: 'l1',
        transactionId: txId,
        itemName: 'Payung ketinggalan',
        jenis: 'ketinggalan',
        locallyModified: true);

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K1',
        ));

    // TIDAK auto-merge ke tabel host: harus menunggu review, sama seperti
    // usulan produk (Item 40).
    expect(await hostDb.watchLeftBehindItems().first, isEmpty,
        reason: 'usulan client->host wajib lewat review dulu, bukan langsung '
            'masuk tabel host');

    expect(LanSyncService.pendingLaciMejaProposals, hasLength(1));
    final proposal = LanSyncService.pendingLaciMejaProposals.single;
    expect(proposal.entryCount, 1);
    expect(proposal.rows['left_behind_items']!.single['id'], 'l1');

    final result = await LanSyncService.applyLaciMejaProposal(
        proposal.id, {'left_behind_items': {'l1'}});
    expect(result.applied, 1);
    expect(result.skippedReasons, isEmpty);
    expect(LanSyncService.pendingLaciMejaProposals, isEmpty);

    final hostRows = await hostDb.watchLeftBehindItems().first;
    expect(hostRows, hasLength(1));
    expect(hostRows.single.locallyModified, isFalse,
        reason: 'setelah owner approve, flag usulan dilepas (host adalah '
            'sumber kebenaran sekarang)');
  });

  test(
      'Bug nyata dilaporkan user (screenshot "SqliteException 787 FOREIGN '
      'KEY constraint failed"): terapkan usulan Pre-order SEBELUM transaksi '
      'terkaitnya sendiri tersinkron ke host -> TIDAK throw, baris DILEWATI',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    // Koneksi produksi sungguhan mengaktifkan FK enforcement (lihat
    // `_openConnection`) — tanpa baris ini, bug FK ini tidak akan pernah
    // tertangkap test walau skema tabelnya benar.
    await hostDb.customStatement('PRAGMA foreign_keys = ON;');
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    // Transaksi HANYA ada di client — device kasir baru saja membuat
    // pre-order & transaksinya sendiri, TAPI belum sempat/belum di-approve
    // kategori sync "Transaksi" terpisah ke host (dua antrian yg TIDAK
    // saling menunggu urutan — akar bug sesungguhnya).
    final txId = await seedTransaction(clientDb, 'tx1');
    await clientDb.addPreorderEntry(
        id: 'pre1',
        productId: 'p1',
        productUnitId: 'u1',
        transactionId: txId,
        customerName: 'Bu Diah',
        qtyOrdered: 4,
        paid: true,
        locallyModified: true);

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K1',
        ));

    final proposal = LanSyncService.pendingLaciMejaProposals.single;

    // TIDAK BOLEH throw SqliteException — dulu inilah bug-nya persis.
    final result = await LanSyncService.applyLaciMejaProposal(
        proposal.id, {'preorder_entries': {'pre1'}});

    expect(result.applied, 0,
        reason: 'baris ini HARUS dilewati, bukan diterapkan paksa');
    expect(result.skippedReasons, hasLength(1));
    expect(result.skippedReasons.single, contains('Bu Diah'));
    expect(result.skippedReasons.single, contains('belum tersinkron'));

    // Tidak ada apa pun yang masuk ke tabel host — bukan setengah-jalan.
    expect(await hostDb.watchPreorderEntries().first, isEmpty);
  });

  test(
      'usulan produk (Item 40) dan usulan Laci Meja BENAR-BENAR independen — '
      'satu ada isinya, satunya kosong, tidak saling mengganggu', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await clientDb.into(clientDb.products).insert(ProductsCompanion.insert(
          id: 'p-new',
          name: 'Produk Baru',
          locallyModified: const Value(true),
        ));
    await clientDb.into(clientDb.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'p-new-u',
          productId: 'p-new',
          isBaseUnit: const Value(true),
        ));

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    expect(LanSyncService.pendingProposals, hasLength(1),
        reason: 'usulan produk tetap berjalan normal');
    expect(LanSyncService.pendingLaciMejaProposals, isEmpty,
        reason: 'tidak ada entri Laci Meja yang diusulkan, antrian itu '
            'harus tetap kosong (bukan ikut terisi/error)');
  });
}
