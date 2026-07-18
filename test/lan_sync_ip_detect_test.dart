import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Item 39 — deteksi IP host lebih andal + profil timeout bisa diatur.
///
/// Konteks: laporan user "kadang di jaringan yang sama tapi tidak
/// tersambung" — salah satu kandidat penyebab adalah `NetworkInfo.
/// getWifiIP()` (API WiFi manager Android) yang tidak selalu bisa
/// diandalkan di semua ROM/versi Android. `detectHostIp()` sekarang punya
/// fallback ke `NetworkInterface.list()` (dart:io murni, TIDAK butuh izin
/// tambahan apa pun) kalau strategi utama gagal/kosong.
void main() {
  group('isPrivateIPv4', () {
    test('rentang 192.168.x.x dikenali privat', () {
      expect(LanSyncService.isPrivateIPv4('192.168.1.5'), isTrue);
    });
    test('rentang 10.x.x.x dikenali privat', () {
      expect(LanSyncService.isPrivateIPv4('10.0.0.42'), isTrue);
    });
    test('rentang 172.16-31.x.x dikenali privat, di luar itu bukan', () {
      expect(LanSyncService.isPrivateIPv4('172.20.5.1'), isTrue);
      expect(LanSyncService.isPrivateIPv4('172.15.5.1'), isFalse);
      expect(LanSyncService.isPrivateIPv4('172.32.5.1'), isFalse);
    });
    test('IP publik (mis. 8.8.8.8) TIDAK dikenali privat', () {
      expect(LanSyncService.isPrivateIPv4('8.8.8.8'), isFalse);
    });
    test('string bukan IPv4 valid → false, bukan crash', () {
      expect(LanSyncService.isPrivateIPv4('not-an-ip'), isFalse);
      expect(LanSyncService.isPrivateIPv4('192.168.1'), isFalse);
      expect(LanSyncService.isPrivateIPv4(''), isFalse);
    });
  });

  group('detectHostIp', () {
    test('pakai hasil getWifiIP() kalau valid (strategi utama)', () async {
      final ip = await LanSyncService.detectHostIp(
        getWifiIpOverride: () async => '192.168.1.99',
      );
      expect(ip, '192.168.1.99');
    });

    test('fallback ke NetworkInterface kalau getWifiIP() null', () async {
      final ip = await LanSyncService.detectHostIp(
        getWifiIpOverride: () async => null,
        listInterfacesOverride: () async => [
          _fakeInterface('wlan0', ['192.168.50.10']),
        ],
      );
      expect(ip, '192.168.50.10');
    });

    test('fallback ke NetworkInterface kalau getWifiIP() balas "0.0.0.0" '
        '(basi/tidak valid)', () async {
      final ip = await LanSyncService.detectHostIp(
        getWifiIpOverride: () async => '0.0.0.0',
        listInterfacesOverride: () async => [
          _fakeInterface('wlan0', ['10.0.0.5']),
        ],
      );
      expect(ip, '10.0.0.5');
    });

    test('fallback melewati alamat IP publik (mis. VPN/tethering) & pilih '
        'yang privat', () async {
      final ip = await LanSyncService.detectHostIp(
        getWifiIpOverride: () async => null,
        listInterfacesOverride: () async => [
          _fakeInterface('tun0', ['203.0.113.5']),
          _fakeInterface('wlan0', ['192.168.1.7']),
        ],
      );
      expect(ip, '192.168.1.7');
    });

    test('kedua strategi gagal total → "Unknown IP", TIDAK crash', () async {
      final ip = await LanSyncService.detectHostIp(
        getWifiIpOverride: () async => null,
        listInterfacesOverride: () async => [],
      );
      expect(ip, 'Unknown IP');
    });

    test('exception di strategi utama tidak menghentikan fallback',
        () async {
      final ip = await LanSyncService.detectHostIp(
        getWifiIpOverride: () async => throw Exception('WiFi API error'),
        listInterfacesOverride: () async => [
          _fakeInterface('wlan0', ['192.168.9.9']),
        ],
      );
      expect(ip, '192.168.9.9');
    });
  });

  group('startHost + refreshHostIp (integrasi service, plain test — bukan '
      'testWidgets, lihat catatan di sync_screen_timeout_ip_test.dart)', () {
    test('startHost lalu refreshHostIp keduanya berhasil tanpa hang',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await LanSyncService.stopHost();
      final (ip, token) =
          await LanSyncService.startHost(db: db, storeKey: 'k')
              .timeout(const Duration(seconds: 10));
      expect(token, isNotEmpty);
      expect(ip, isNotEmpty);

      final refreshed =
          await LanSyncService.refreshHostIp().timeout(const Duration(seconds: 10));
      expect(refreshed, isNotEmpty);

      await LanSyncService.stopHost();
      await db.close();
    });
  });

  group('SyncTimeoutProfile', () {
    test('default "normal" kalau belum pernah disimpan', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final profile = await SyncTimeoutProfile.load(db);
      expect(profile, SyncTimeoutProfile.normal);
      await db.close();
    });

    test('save/load round-trip tersimpan persisten', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await SyncTimeoutProfile.save(db, SyncTimeoutProfile.sangatLambat);
      final profile = await SyncTimeoutProfile.load(db);
      expect(profile, SyncTimeoutProfile.sangatLambat);
      await db.close();
    });

    test('profil "lambat"/"sangatLambat" punya durasi lebih besar dari '
        '"cepat"/"normal" (urutan makin longgar)', () {
      expect(SyncTimeoutProfile.cepat.responseTimeout,
          lessThan(SyncTimeoutProfile.normal.responseTimeout));
      expect(SyncTimeoutProfile.normal.responseTimeout,
          lessThan(SyncTimeoutProfile.lambat.responseTimeout));
      expect(SyncTimeoutProfile.lambat.responseTimeout,
          lessThan(SyncTimeoutProfile.sangatLambat.responseTimeout));
    });

    test('fromKey dgn key tak dikenal fallback ke normal (bukan crash)', () {
      expect(SyncTimeoutProfile.fromKey('key-aneh-tak-dikenal'),
          SyncTimeoutProfile.normal);
      expect(SyncTimeoutProfile.fromKey(null), SyncTimeoutProfile.normal);
    });
  });
}

NetworkInterface _fakeInterface(String name, List<String> addresses) {
  return _FakeNetworkInterface(name, [
    for (final a in addresses) InternetAddress(a),
  ]);
}

/// `NetworkInterface` (dart:io) abstract & cuma bisa didapat via `.list()`
/// yang hit OS sungguhan — fake ini implement 3 getter yang dipakai
/// `detectHostIp()` supaya bisa diuji tanpa interface jaringan asli.
class _FakeNetworkInterface implements NetworkInterface {
  _FakeNetworkInterface(this.name, this.addresses);
  @override
  final String name;
  @override
  final List<InternetAddress> addresses;
  @override
  int get index => 0;
}
