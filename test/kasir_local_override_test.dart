import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/kasir_sticker_service.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Lihat catatan di lan_sync_watermark_test.dart soal escape ganda HttpOverrides.
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

/// Stiker & teks landing Kasir di perangkat NON-owner: boleh diubah, tapi
/// hanya SEMENTARA — setelah sync berhasil dgn host, kembali ke nilai host
/// (owner = sumber kebenaran).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/network_info'),
          (call) async => call.method == 'wifiIPAddress' ? '127.0.0.1' : null);

  tearDown(() async {
    await LanSyncService.stopHost();
  });

  test('key override lokal TIDAK termasuk key yang disinkronkan', () {
    for (final k in KasirLocalOverrides.allKeys) {
      expect(AppDatabase.syncableSettingKeys.contains(k), isFalse, reason: k);
      expect(k, startsWith('local_'));
    }
    // ... sedangkan nilai resmi host memang disinkronkan.
    for (final s in KasirStickerSlot.values) {
      expect(AppDatabase.syncableSettingKeys.contains(s.settingKey), isTrue);
    }
  });

  test(
      'prioritas: override lokal > nilai host > bawaan; reset lokal = ikut host',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final tgs = File('assets/stickers/closed.tgs').readAsBytesSync();

    // Host menetapkan teks & stiker (tersinkron ke key aslinya).
    await db.setSetting('kasir_landing_title', 'Dari Owner');
    await KasirStickerService.setCustom(db, KasirStickerSlot.landing, tgs);
    expect((await KasirLandingText.load(db)).title, 'Dari Owner');

    // Non-owner mengubah SEMENTARA.
    await KasirLandingText.save(db,
        title: 'Dari Kasir', subtitle: '', local: true);
    await KasirStickerService.setCustom(db, KasirStickerSlot.notFound, tgs,
        local: true);
    expect((await KasirLandingText.load(db)).title, 'Dari Kasir');
    expect(await db.getSetting('kasir_landing_title'), 'Dari Owner',
        reason: 'nilai host utuh');
    expect(
        await KasirStickerService.isLocalOverride(
            db, KasirStickerSlot.notFound),
        isTrue);
    expect(
        await KasirStickerService.loadJson(db, KasirStickerSlot.notFound,
            loadAsset: (_) async => tgs),
        isNotNull);

    // Teks kosong (lokal) = buang override -> kembali ke host.
    await KasirLandingText.save(db, title: '', subtitle: '', local: true);
    expect((await KasirLandingText.load(db)).title, 'Dari Owner');
    // Reset stiker lokal -> override hilang, unggahan host tetap.
    await KasirStickerService.resetToDefault(db, KasirStickerSlot.notFound,
        local: true);
    expect(
        await KasirStickerService.isLocalOverride(
            db, KasirStickerSlot.notFound),
        isFalse);
    expect(await KasirStickerService.isCustom(db, KasirStickerSlot.landing),
        isTrue);
  });

  test(
      'sync LAN sungguhan: override lokal klien DIBUANG setelah sync berhasil '
      '-> teks & stiker kembali ke nilai host', () async {
    final ownerDb = AppDatabase(NativeDatabase.memory());
    final kasirDb = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await ownerDb.close();
      await kasirDb.close();
    });
    final tgs = File('assets/stickers/closed.tgs').readAsBytesSync();

    // Owner menetapkan teks & stiker; klien sudah punya nilai itu dari sync lalu.
    for (final db in [ownerDb, kasirDb]) {
      await db.setSetting('kasir_landing_title', 'Judul Owner');
      await db.setSetting('kasir_landing_subtitle', 'Keterangan Owner');
    }
    await KasirStickerService.setCustom(ownerDb, KasirStickerSlot.landing, tgs);
    await KasirStickerService.setCustom(kasirDb, KasirStickerSlot.landing, tgs);
    await kasirDb.setSetting('last_sync_download_at',
        DateTime.now().subtract(const Duration(hours: 1)).toIso8601String());

    // Klien (kasir) mengubah SEMENTARA, teks + stiker.
    await KasirLandingText.save(kasirDb,
        title: 'Judul Kasir', subtitle: 'Ket Kasir', local: true);
    await KasirStickerService.setCustom(kasirDb, KasirStickerSlot.empty, tgs,
        local: true);
    expect((await KasirLandingText.load(kasirDb)).title, 'Judul Kasir');
    expect(await KasirLocalOverrides.any(kasirDb), isTrue);

    final (_, token) = await LanSyncService.startHost(
        db: ownerDb, storeKey: 'shared-store-key');
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: kasirDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    // Setelah sync: override lokal hilang -> tampilan = nilai host.
    expect(await KasirLocalOverrides.any(kasirDb), isFalse);
    final t = await KasirLandingText.load(kasirDb);
    expect(t.title, 'Judul Owner');
    expect(t.subtitle, 'Keterangan Owner');
    expect(
        await KasirStickerService.isLocalOverride(
            kasirDb, KasirStickerSlot.empty),
        isFalse);
    // Nilai host di klien tetap utuh.
    expect(
        await KasirStickerService.isCustom(kasirDb, KasirStickerSlot.landing),
        isTrue);
  });

  test('sync GAGAL (token salah): override lokal TETAP ada', () async {
    final ownerDb = AppDatabase(NativeDatabase.memory());
    final kasirDb = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await ownerDb.close();
      await kasirDb.close();
    });
    await kasirDb.setSetting('kasir_landing_title', 'Judul Owner');
    await KasirLandingText.save(kasirDb,
        title: 'Judul Kasir', subtitle: '', local: true);

    await LanSyncService.startHost(db: ownerDb, storeKey: 'shared-store-key');
    Object? error;
    try {
      await _withRealHttp(() => LanSyncService.syncToHost(
            db: kasirDb,
            storeKey: 'shared-store-key',
            hostIp: '127.0.0.1',
            syncToken: 'token-salah',
          ));
    } catch (e) {
      error = e;
    }
    expect(error, isNotNull, reason: 'prasyarat: sync memang gagal');
    expect((await KasirLandingText.load(kasirDb)).title, 'Judul Kasir');
  });
}
