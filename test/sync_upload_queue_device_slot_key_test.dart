import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Bug nyata dilaporkan user (sama persis dgn `_pendingProposals` yang
/// sudah diperbaiki 25 Juli, sekarang giliran `sync_upload_queue`): antrian
/// sync data biasa (transaksi/stok/dll) dikunci "satu slot per alamat IP" —
/// kalau DUA DEVICE BERBEDA kebetulan tersambung dari IP yang SAMA (lazim
/// di hotspot HP dgn pool DHCP kecil, setup umum toko kecil), sync device
/// kedua MENIMPA antrian device pertama yang belum sempat di-approve owner.
/// Fix: kunci slot sekarang preferensi `deviceCode` (dikirim via
/// `syncToHost`) drpd `ip` mentah.
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

  Future<void> addExpense(AppDatabase db, String id, String note) =>
      db.into(db.expenses).insert(ExpensesCompanion.insert(
            id: id,
            localId: id,
            type: 'daily_expense',
            amount: 10000,
            note: Value(note),
          ));

  test(
      'device A sync data, LALU device B (deviceCode beda, IP SAMA) sync '
      'data lain SEBELUM owner approve -- antrian A TIDAK BOLEH hilang',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientA = AppDatabase(NativeDatabase.memory());
    final clientB = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientA.close);
    addTearDown(clientB.close);

    await addExpense(clientA, 'exp-A', 'Belanja dari Asisten A');
    await addExpense(clientB, 'exp-B', 'Belanja dari Pegawai B');

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    // Device A sync duluan -- antrian A masuk.
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientA,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K1',
        ));
    var queue = await hostDb.listSyncUploadQueue();
    expect(queue, hasLength(1));

    // Owner BELUM sempat approve. Device B (device BEDA, deviceCode beda,
    // tapi kebetulan IP sama persis 127.0.0.1) sync.
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientB,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K2',
        ));

    queue = await hostDb.listSyncUploadQueue();
    expect(queue, hasLength(2),
        reason: 'device A dan device B harus dapat slot antrian '
            'masing-masing, bukan device B menimpa antrian A');
    expect(queue.map((q) => q.deviceCode), containsAll(['K1', 'K2']));
  });

  test(
      'sync ULANG dari device YANG SAMA (deviceCode sama) tetap menimpa '
      'slotnya sendiri (perilaku lama tetap terjaga, bukan menumpuk)',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientA = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientA.close);

    await addExpense(clientA, 'exp-A1', 'Belanja 1');

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientA,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K1',
        ));
    expect(await hostDb.listSyncUploadQueue(), hasLength(1));

    await addExpense(clientA, 'exp-A2', 'Belanja 2');
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientA,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K1',
        ));

    final queue = await hostDb.listSyncUploadQueue();
    expect(queue, hasLength(1),
        reason: 'device yang sama tetap satu slot (upload klien selalu '
            'superset dari sync sebelumnya)');
  });
}
