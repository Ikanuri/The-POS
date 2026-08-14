import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Item 52 lanjutan — bukti end-to-end (bukan cuma unit
/// `filterUnchangedLaciMejaProposals`) lewat protokol HTTP sungguhan: bug
/// nyata dilaporkan user — pre-order yang sudah "Dipenuhi" TETAP terus
/// diusulkan ulang ke owner tiap sync, walau ownernya SUDAH menerapkan
/// usulan itu sebelumnya (host punya versi identik). Pola sama persis
/// dgn `proposal_unchanged_end_to_end_test.dart` (produk, Item 40).
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
      'Bug nyata dilaporkan user: pre-order sudah "Dipenuhi" & IDENTIK dgn '
      'host TIDAK LAGI membuat antrian usulan sama sekali (dulu terus '
      'diusulkan ulang)', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    // Host & klien PERSIS sama (owner sudah approve usulan "Dipenuhi" ini
    // sebelumnya) — tapi locally_modified klien masih macet true (blm
    // sempat menerima balik baris resmi host).
    final txIdHost = await seedTransaction(hostDb, 'tx1');
    await hostDb.addPreorderEntry(
        id: 'p1',
        productId: 'prod1',
        productUnitId: 'unit1',
        transactionId: txIdHost,
        customerName: 'Budi',
        qtyOrdered: 2);
    await hostDb.fulfillPreorderEntry('p1');

    final txIdClient = await seedTransaction(clientDb, 'tx1');
    await clientDb.addPreorderEntry(
        id: 'p1',
        productId: 'prod1',
        productUnitId: 'unit1',
        transactionId: txIdClient,
        customerName: 'Budi',
        qtyOrdered: 2,
        locallyModified: true);
    await clientDb.fulfillPreorderEntry('p1', locallyModified: true);

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K1',
        ));

    expect(LanSyncService.pendingLaciMejaProposals, isEmpty,
        reason: 'pre-order yang sudah dipenuhi & identik dgn host tidak '
            'perlu ditinjau ulang — jangan sampai membuat antrian usulan');
  });

  test(
      'pre-order dibatalkan di klien SEBELUM host tahu — TETAP masuk '
      'antrian usulan (genuinely perlu ditinjau owner)', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    final txIdHost = await seedTransaction(hostDb, 'tx1');
    await hostDb.addPreorderEntry(
        id: 'p1',
        productId: 'prod1',
        productUnitId: 'unit1',
        transactionId: txIdHost,
        customerName: 'Budi',
        qtyOrdered: 2);
    // Host BELUM tahu ini dibatalkan.

    final txIdClient = await seedTransaction(clientDb, 'tx1');
    await clientDb.addPreorderEntry(
        id: 'p1',
        productId: 'prod1',
        productUnitId: 'unit1',
        transactionId: txIdClient,
        customerName: 'Budi',
        qtyOrdered: 2,
        locallyModified: true);
    await clientDb.cancelPreorderEntry('p1', locallyModified: true);

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K1',
        ));

    expect(LanSyncService.pendingLaciMejaProposals, hasLength(1),
        reason: 'perubahan sungguhan (baru dibatalkan) harus tetap muncul '
            'utk ditinjau owner');
    expect(
        LanSyncService.pendingLaciMejaProposals.single.rows['preorder_entries'],
        hasLength(1));
  });
}
