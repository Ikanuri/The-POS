import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// Lihat catatan sama di lan_sync_watermark_test.dart soal kenapa perlu
/// escape ganda HttpOverrides di sini.
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

const _kWatermarkKey = 'last_sync_download_at';

/// Bug dilaporkan user: owner nyalakan izin "Izinkan Stok Minus" utk asisten
/// di device OWNER — tapi di device ASISTEN (DB terpisah, terhubung via sync
/// LAN sungguhan) perubahan itu tidak pernah nyampe / tidak berlaku.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/network_info'),
          (call) async => call.method == 'wifiIPAddress' ? '127.0.0.1' : null);

  tearDown(() async {
    await LanSyncService.stopHost();
  });

  test(
      'owner nyalakan asisten_stok_minus di host -> ikut ke-sync ke DB '
      'asisten via LAN sungguhan -> resolveAllowNegativeStock true di sana',
      () async {
    final ownerDb = AppDatabase(NativeDatabase.memory());
    final asistenDb = AppDatabase(NativeDatabase.memory());

    // Watermark klien (asisten) sudah ada dari sync sebelumnya, SEBELUM
    // owner menyalakan izin di bawah.
    await asistenDb.setSetting(
        _kWatermarkKey, DateTime.now().subtract(const Duration(hours: 1)).toIso8601String());
    await asistenDb.setSetting('allow_negative_stock', '0');
    await ownerDb.setSetting('allow_negative_stock', '0');

    // Owner menyalakan izin — persis aksi yang dilakukan AsistenPermissionsScreen.
    await (ownerDb.update(ownerDb.kasirPermissions)
          ..where((t) => t.permissionKey.equals('asisten_stok_minus')))
        .write(KasirPermissionsCompanion(
      isEnabled: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));

    final (_, token) =
        await LanSyncService.startHost(db: ownerDb, storeKey: 'shared-store-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: asistenDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    final row = await (asistenDb.select(asistenDb.kasirPermissions)
          ..where((t) => t.permissionKey.equals('asisten_stok_minus')))
        .getSingle();
    expect(row.isEnabled, isTrue,
        reason: 'izin yang dinyalakan owner harus ter-sync ke DB asisten');

    const asisten = DeviceIdentity(deviceRole: 'asisten');
    expect(await resolveAllowNegativeStock(asistenDb, asisten), isTrue);

    await ownerDb.close();
    await asistenDb.close();
  });
}
