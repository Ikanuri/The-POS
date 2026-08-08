import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Item 60 — poin loyalti (`customers.loyalty_points`) ditulis via UPDATE
/// RELATIF mentah di device asal, TIDAK menyentuh `updated_at` — begitu 2
/// device mencatat poin ke pelanggan yang SAMA scr independen lalu sync,
/// `customers` (master data, LWW berdasar `updated_at`) bisa MENIMPA BALIK
/// poin yang baru saja diterima dari device lain, walau `loyalty_point_
/// ledger`-nya sendiri (append-only) sudah ter-merge benar. Fix:
/// `rebuildLoyaltyPointsForCustomers` (pola sama `rebuildStockAfterForUnits`)
/// dipanggil setelah merge, di host (`approveSync`) & client (`syncToHost`).
///
/// Pola escape HttpOverrides & seam PathProvider sama seperti
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

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.docsPath);
  final String docsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

Future<int> _loyaltyPoints(AppDatabase db, String customerId) async {
  final row = await (db.select(db.customers)
        ..where((t) => t.id.equals(customerId)))
      .getSingle();
  return row.loyaltyPoints;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/network_info'),
          (call) async => call.method == 'wifiIPAddress' ? '127.0.0.1' : null);

  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pos_sync_loyalty_');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    await LanSyncService.stopHost();
    PathProviderPlatform.instance = originalPathProvider;
    tempDir.deleteSync(recursive: true);
  });

  test(
      '2 device beri poin ke pelanggan yang SAMA scr independen sebelum '
      'sync — SETELAH merge kedua device sepakat ke SUM ledger, bukan salah '
      'satu menang scr kebetulan lewat LWW customers', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    // Pelanggan yang sama sudah ada di kedua device (spt hasil sync
    // sebelumnya) — updated_at LAMA sengaja disamakan supaya perbandingan
    // LWW TIDAK bisa "kebetulan benar"; satu-satunya cara benar adalah
    // rebuild dari SUM ledger.
    final baseUpdatedAt = DateTime(2026, 1, 1);
    for (final db in [hostDb, clientDb]) {
      await db.into(db.customers).insert(CustomersCompanion.insert(
            id: 'cust-1',
            name: 'Budi',
            updatedAt: Value(baseUpdatedAt),
          ));
    }

    // Host mencatat +30 poin sendiri (atomik dgn ledger, spt transaksi
    // lokal sungguhan) — TIDAK menyentuh updated_at customers (Item 60).
    await hostDb.into(hostDb.loyaltyPointLedger).insert(
        LoyaltyPointLedgerCompanion.insert(
            id: 'lpl-host', customerId: 'cust-1', type: 'earn', points: 30));
    await hostDb.customUpdate(
      'UPDATE customers SET loyalty_points = loyalty_points + 30 WHERE id = ?',
      variables: [Variable.withString('cust-1')],
      updates: {hostDb.customers},
    );

    // Client mencatat +50 poin sendiri, independen, SEBELUM sync apa pun.
    await clientDb.into(clientDb.loyaltyPointLedger).insert(
        LoyaltyPointLedgerCompanion.insert(
            id: 'lpl-client',
            customerId: 'cust-1',
            type: 'earn',
            points: 50));
    await clientDb.customUpdate(
      'UPDATE customers SET loyalty_points = loyalty_points + 50 WHERE id = ?',
      variables: [Variable.withString('cust-1')],
      updates: {clientDb.customers},
    );

    expect(await _loyaltyPoints(hostDb, 'cust-1'), 30);
    expect(await _loyaltyPoints(clientDb, 'cust-1'), 50);

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    // Sync #1: client upload -> host queue -> owner approve (merge +
    // rebuild loyalti host).
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));
    final queue = await hostDb.listSyncUploadQueue();
    await LanSyncService.approveSync(queue.single.id);

    expect(await _loyaltyPoints(hostDb, 'cust-1'), 80,
        reason: 'host HARUS SUM ledger (30+50=80) setelah merge, bukan '
            'tetap 30 (kalau customers LWW yg dipakai, bukan rebuild)');

    // Sync #2: client tarik balik data host (ledger host + customers host)
    // dan gabungkan.
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    expect(await _loyaltyPoints(clientDb, 'cust-1'), 80,
        reason: 'client jg HARUS SUM ledger gabungan (30+50=80), sepakat '
            'dgn host — sebelum fix, bisa macet di salah satu angka lama '
            'krn customers cuma LWW, tidak pernah direkonstruksi dari ledger');
  });
}
