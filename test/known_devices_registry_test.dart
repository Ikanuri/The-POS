import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Registri perangkat (kode -> nama + role): dipelajari host dari payload sync
/// klien (protokol HTTP sungguhan), dipakai riwayat Laci Meja ("oleh <nama>
/// (<role>)").
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

  test('rememberKnownDevice: simpan, perbarui, abaikan kosong; key ikut sync',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(await db.getKnownDevices(), isEmpty);

    await db.rememberKnownDevice(
        code: 'K2', name: 'Pegawai Budi', role: 'kasir');
    await db.rememberKnownDevice(code: '', name: 'x', role: 'kasir');
    await db.rememberKnownDevice(code: 'K3', name: '', role: '');
    var m = await db.getKnownDevices();
    expect(m.keys, ['K2']);
    expect(m['K2']!.name, 'Pegawai Budi');
    expect(m['K2']!.role, 'kasir');

    await db.rememberKnownDevice(code: 'K2', name: 'Budi', role: 'asisten');
    m = await db.getKnownDevices();
    expect(m['K2']!.name, 'Budi');
    expect(m['K2']!.role, 'asisten');
    expect(
        AppDatabase.syncableSettingKeys, contains(AppDatabase.knownDevicesKey));
  });

  test('sync klien -> host: host mencatat nama & role perangkat klien',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    final (_, token) = await LanSyncService.startHost(
        db: hostDb, storeKey: 'shared-store-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K2',
          deviceName: 'Pegawai Budi',
          deviceRole: 'kasir',
        ));

    final m = await hostDb.getKnownDevices();
    expect(m['K2']?.name, 'Pegawai Budi');
    expect(m['K2']?.role, 'kasir');
  });
}
