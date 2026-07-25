import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Bug nyata dilaporkan user: kategori produk (create/rename/delete/reorder
/// KATEGORI ITU SENDIRI — beda dari penugasan produk ke kategori yang sudah
/// benar via `products.productGroupId`/`product_group_tags`) tidak pernah
/// tersinkron ke device kasir/asisten sama sekali — `product_groups` lupa
/// dimasukkan ke `dumpSince`'s `masterData` list & `clientMergeableTables`.
/// Test ini membuktikan lewat protokol HTTP sungguhan (bukan cuma unit
/// `dumpSince`), pola sama seperti `proposal_unchanged_end_to_end_test.dart`.
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
      'kategori BARU dibuat owner (product_groups) ikut tersinkron ke '
      'device asisten via LAN sungguhan', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await hostDb.addProductGroup('Sembako');

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    final clientGroups = await clientDb.select(clientDb.productGroups).get();
    expect(clientGroups.map((g) => g.name), contains('Sembako'),
        reason: 'kategori baru dari owner harus ikut tersinkron ke klien');
  });

  test(
      'kategori yang DIHAPUS owner (name di-null-kan) ikut tersinkron ke '
      'asisten, bukan tetap menetap dgn nama lama', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await hostDb.addProductGroup('Minuman');
    final group = (await (hostDb.select(hostDb.productGroups)
          ..where((t) => t.name.equals('Minuman')))
        .get())
        .single;

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    // Sync pertama: klien terima kategori "Minuman".
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));
    expect(
        (await clientDb.select(clientDb.productGroups).get())
            .map((g) => g.name),
        contains('Minuman'));

    // Owner hapus kategori (name -> null, slot id dipakai ulang).
    await hostDb.deleteProductGroup(group.id);

    // Sync kedua: klien harus ikut lihat kategori itu sudah "kosong".
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    final clientGroup = await (clientDb.select(clientDb.productGroups)
          ..where((t) => t.id.equals(group.id)))
        .getSingle();
    expect(clientGroup.name, isNull,
        reason: 'penghapusan kategori di owner harus ikut tersinkron, '
            'bukan tetap "Minuman" selamanya di klien');
  });

  test(
      'rename kategori di owner ikut tersinkron ke asisten', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await hostDb.addProductGroup('Snack');
    final group = (await (hostDb.select(hostDb.productGroups)
          ..where((t) => t.name.equals('Snack')))
        .get())
        .single;

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    await hostDb.renameProductGroup(group.id, 'Cemilan');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    final clientGroup = await (clientDb.select(clientDb.productGroups)
          ..where((t) => t.id.equals(group.id)))
        .getSingle();
    expect(clientGroup.name, 'Cemilan');
  });
}
