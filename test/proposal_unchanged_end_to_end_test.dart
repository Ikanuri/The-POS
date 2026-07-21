import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Item 40 lanjutan — bukti end-to-end (bukan cuma unit `filterUnchangedProposals`)
/// lewat protokol HTTP sungguhan: produk yang `locally_modified`-nya
/// "macet" true di klien PADAHAL isinya sudah identik dgn data owner
/// TIDAK LAGI membuat antrian usulan sama sekali — laporan nyata user
/// "menumpuk". Pola escape HttpOverrides sama seperti
/// `lan_sync_upload_queue_test.dart`.
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
  });

  Future<void> seedIdenticalProduct(AppDatabase db,
      {required bool markLocallyModified}) async {
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'p1',
          name: 'Gula Pasir',
          locallyModified: Value(markLocallyModified),
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u1',
          productId: 'p1',
          isBaseUnit: const Value(true),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'u1-t',
          productUnitId: 'u1',
          price: 15000,
        ));
  }

  test(
      'produk locally_modified=true di klien TAPI isinya identik dgn owner '
      '— TIDAK membuat antrian usulan sama sekali (dulu terus menumpuk)',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    // Host & klien punya PERSIS produk yang sama — tapi di klien flag
    // locally_modified masih true (simulasi "macet", mis. form disimpan
    // ulang tanpa perubahan nilai).
    await seedIdenticalProduct(hostDb, markLocallyModified: false);
    await seedIdenticalProduct(clientDb, markLocallyModified: true);

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    expect(LanSyncService.pendingProposals, isEmpty,
        reason: 'produk yang isinya sudah identik dgn owner tidak perlu '
            'ditinjau — jangan sampai membuat antrian usulan sama sekali');
  });

  test(
      'produk locally_modified=true di klien DENGAN harga benar-benar beda '
      '— TETAP masuk antrian usulan (genuinely perlu ditinjau owner)',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await seedIdenticalProduct(hostDb, markLocallyModified: false);
    await clientDb.into(clientDb.products).insert(ProductsCompanion.insert(
          id: 'p1',
          name: 'Gula Pasir',
          locallyModified: const Value(true),
        ));
    await clientDb.into(clientDb.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u1',
          productId: 'p1',
          isBaseUnit: const Value(true),
        ));
    await clientDb.into(clientDb.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'u1-t',
          productUnitId: 'u1',
          price: 17000, // beda dari harga host (15000).
        ));

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    expect(LanSyncService.pendingProposals, hasLength(1),
        reason: 'harga benar-benar beda — harus tetap muncul di antrian '
            'utk ditinjau owner');
    expect(LanSyncService.pendingProposals.single.productCount, 1);
  });
}
