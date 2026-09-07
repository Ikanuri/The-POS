import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Bug nyata (audit manual): tabel `price_categories` (master "Kategori
/// Harga", Fase B) ADA di skema tapi TIDAK ADA di `_allTables`
/// (`dumpAllTables`/`restoreFromDump`, backup penuh/"Alihkan Owner") maupun
/// di `masterData` (`dumpSince`, sync LAN harian host->klien) DAN tidak ada
/// di `LanSyncService.clientMergeableTables` (allowlist merge sisi klien).
/// Akibatnya kategori yang owner buat TIDAK PERNAH sampai ke device kasir
/// lain sama sekali — `alt_prices.priceCategoryId` (yang SUDAH ikut sync)
/// jadi rujukan ke kategori yang tidak pernah ada di klien.
///
/// Test ini membuktikan lewat protokol HTTP sungguhan (bukan cuma unit
/// `dumpSince`), pola sama seperti `product_group_sync_test.dart`.
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

  tearDown(() async => LanSyncService.stopHost());

  test(
      'kategori harga BARU dibuat owner ikut tersinkron ke device asisten '
      'via LAN sungguhan', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await hostDb.addPriceCategory('Grosir');

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    final clientCats = await clientDb.getAllPriceCategories();
    expect(clientCats.map((c) => c.name), contains('Grosir'),
        reason: 'kategori harga baru dari owner harus ikut tersinkron ke '
            'klien — sebelumnya tidak pernah sampai sama sekali');
  });

  test(
      'kategori harga yang DIHAPUS owner (tombstone name=null) ikut '
      'tersinkron ke asisten, tidak nyangkut selamanya', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    final catId = await hostDb.addPriceCategory('Rokok');

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    // Sync pertama: klien terima kategori "Rokok".
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));
    expect((await clientDb.getAllPriceCategories()).map((c) => c.name),
        contains('Rokok'));

    // Owner hapus kategori (tombstone name -> null).
    await hostDb.deletePriceCategory(catId);

    // Sync kedua: klien harus ikut lihat kategori itu sudah hilang dari UI.
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    expect(await clientDb.getAllPriceCategories(), isEmpty,
        reason: 'penghapusan kategori di owner harus ikut tersinkron, '
            'bukan tetap "Rokok" selamanya di klien');
    // Baris fisiknya tetap ada (tombstone), bukan hilang total.
    final raw = await clientDb.select(clientDb.priceCategories).get();
    expect(raw.map((c) => c.id), contains(catId));
    expect(raw.singleWhere((c) => c.id == catId).name, isNull);
  });

  test('rename kategori harga di owner ikut tersinkron ke asisten', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    final catId = await hostDb.addPriceCategory('Snack');

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    await hostDb.renamePriceCategory(catId, 'Cemilan');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    final clientCat = (await clientDb.getAllPriceCategories())
        .singleWhere((c) => c.id == catId);
    expect(clientCat.name, 'Cemilan');
  });
}
