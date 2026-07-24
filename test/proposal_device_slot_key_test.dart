import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Bug nyata dilaporkan user: produk baru yang diusulkan asisten kadang
/// hilang dari antrian owner tanpa jejak, bahkan tanpa owner pindah layar.
/// Akar masalah: `_pendingProposals` (dan `sync_upload_queue`) dikunci
/// "satu slot per alamat IP pengirim" (`lan_sync_service.dart`) — kalau DUA
/// DEVICE BERBEDA kebetulan tersambung dari IP yang SAMA (lazim di hotspot
/// HP dgn pool DHCP kecil, setup umum toko kecil) sebelum owner sempat
/// meninjau, sync device kedua MENIMPA slot device pertama walau usulannya
/// belum ditinjau sama sekali. Fix: kunci slot sekarang preferensi
/// `deviceCode` (dikirim klien via `syncToHost(deviceCode: ...)`) drpd `ip`
/// mentah — device berbeda TIDAK PERNAH berbagi kunci yang sama lagi
/// walau kebetulan IP-nya sama.
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

  Future<AppDatabase> seedNewProduct(String productId, String name, int price) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: productId,
          name: name,
          locallyModified: const Value(true),
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: '$productId-u',
          productId: productId,
          isBaseUnit: const Value(true),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: '$productId-t',
          productUnitId: '$productId-u',
          price: price,
        ));
    return db;
  }

  test(
      'device A (deviceCode K1) sync produk baru, LALU device B (deviceCode '
      'K2, IP SAMA -- simulasi hotspot HP) sync produk barunya sendiri '
      'SEBELUM owner review A -- usulan A TIDAK BOLEH hilang', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientA = await seedNewProduct('p-A', 'Produk dari Asisten A', 5000);
    final clientB = await seedNewProduct('p-B', 'Produk dari Pegawai B', 3000);
    addTearDown(hostDb.close);
    addTearDown(clientA.close);
    addTearDown(clientB.close);

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientA,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K1',
        ));
    expect(LanSyncService.pendingProposals, hasLength(1));

    // Owner BELUM sempat review usulan A. Device B (device BEDA, deviceCode
    // beda, tapi IP sama persis di 127.0.0.1) sync.
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientB,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K2',
        ));

    final allProposedProductIds = LanSyncService.pendingProposals
        .expand((p) => p.rows['products'] ?? const [])
        .map((r) => r['id'])
        .toSet();

    expect(allProposedProductIds, containsAll(['p-A', 'p-B']),
        reason: 'usulan dari device A TIDAK BOLEH hilang cuma karena '
            'device B (device BEDA) sync dari IP yang sama');
    expect(LanSyncService.pendingProposals, hasLength(2),
        reason: 'device beda harus dapat slot antrian masing-masing');
  });

  test(
      'sync ULANG dari device YANG SAMA (deviceCode sama) tetap menimpa '
      'slotnya sendiri (perilaku lama tetap terjaga, bukan menumpuk)',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientA = await seedNewProduct('p-A', 'Produk A', 5000);
    addTearDown(hostDb.close);
    addTearDown(clientA.close);

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientA,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K1',
        ));
    expect(LanSyncService.pendingProposals, hasLength(1));

    // Tambah produk KEDUA di device yang SAMA, sync lagi.
    await clientA.into(clientA.products).insert(ProductsCompanion.insert(
          id: 'p-A2',
          name: 'Produk A2',
          locallyModified: const Value(true),
        ));
    await clientA.into(clientA.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'p-A2-u',
          productId: 'p-A2',
          isBaseUnit: const Value(true),
        ));
    await clientA.into(clientA.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'p-A2-t',
          productUnitId: 'p-A2-u',
          price: 9000,
        ));
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientA,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K1',
        ));

    expect(LanSyncService.pendingProposals, hasLength(1),
        reason: 'device yang sama tetap satu slot (dumpLocalProposals paket '
            'penuh, superset dari sebelumnya)');
    final ids = LanSyncService.pendingProposals.single.rows['products']
        ?.map((r) => r['id'])
        .toSet();
    expect(ids, {'p-A', 'p-A2'});
  });
}
