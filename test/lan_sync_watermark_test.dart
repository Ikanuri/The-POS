import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// flutter_test mem-fake semua HttpClient jadi selalu balas 400 (lihat
/// _MockHttpOverrides di flutter_test/src/_binding_io.dart) — perlu di-
/// override balik dengan HttpClient SUNGGUHAN supaya round-trip host<->klien
/// via 127.0.0.1 benar-benar jalan (bukan mock keduanya, test ini sengaja
/// membuktikan protokol sungguhan, bukan reimplementasi logikanya).
///
/// Escape ganda diperlukan: `Zone.root.run` melepas override zone-lokal
/// (createHttpClient ini sendiri — tanpa ini, `HttpClient()` di dalam sini
/// akan memanggil balik createHttpClient ini lagi → stack overflow), DAN
/// menonaktifkan sementara `HttpOverrides.global` (fake dari flutter_test,
/// yang tetap berlaku di Zone.root kalau tidak dinonaktifkan).
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

/// Membuktikan incremental-sync watermark (arah host→klien): sync tidak lagi
/// selalu dump SELURUH riwayat toko — memakai watermark tersimpan dari sync
/// sukses terakhir. Arah klien→host SENGAJA tetap full-dump (lihat komentar
/// di lan_sync_service.dart soal risiko antrian approval yang cuma di
/// memori) — dibuktikan juga TIDAK berubah oleh watermark ini.
///
/// Test menyambung host & klien sungguhan lewat 127.0.0.1 (server asli via
/// shelf, bukan mock) — [LanSyncService] pakai static state, jadi WAJIB
/// stopHost() di tearDown supaya tidak bentrok port antar test.
const _kWatermarkKey = 'last_sync_download_at';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // startHost() memanggil NetworkInfo().getWifiIP() cuma untuk teks display
  // (IP yang ditunjukkan ke owner) — tidak dipakai test ini (selalu connect
  // via 127.0.0.1 langsung), tapi tanpa mock method channel-nya akan throw
  // MissingPluginException di lingkungan test tanpa platform asli.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/network_info'),
          (call) async => call.method == 'wifiIPAddress' ? '127.0.0.1' : null);

  tearDown(() async {
    await LanSyncService.stopHost();
    // stopHost() sengaja tidak membersihkan _pendingQueue (antrian approval
    // dimaksudkan bertahan lintas restart host di app sungguhan) — tapi utk
    // isolasi antar-test di sini, kosongkan manual supaya test berikutnya
    // tidak mewarisi antrian dari test ini.
    for (final item in LanSyncService.pendingQueue.toList()) {
      LanSyncService.rejectSync(item.id);
    }
  });

  test(
      'download watermark tersimpan dipakai (bukan selalu epoch) — transaksi '
      'host yang lebih lama dari watermark TIDAK ikut dikirim ulang',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());

    await hostDb.into(hostDb.transactions).insert(TransactionsCompanion.insert(
          id: 'tx-lama-host',
          localId: 'H-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(DateTime(2020, 1, 1)),
        ));
    await hostDb.into(hostDb.transactions).insert(TransactionsCompanion.insert(
          id: 'tx-baru-host',
          localId: 'H-2',
          status: 'lunas',
          total: 20000,
          paid: 20000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(DateTime(2026, 1, 1)),
        ));

    // Watermark klien sudah ada dari sync SEBELUMNYA, di antara 2 transaksi
    // host di atas — jadi sync berikutnya seharusnya HANYA mengambil yang
    // "tx-baru-host" (created_at 2026 > watermark 2025).
    await clientDb.setSetting(_kWatermarkKey, DateTime(2025, 1, 1).toIso8601String());

    final (_, token) = await LanSyncService.startHost(
      db: hostDb, storeKey: 'shared-store-key');

    // Catatan: `dumpSince` host (includeMasterData:true, default) juga selalu
    // menyertakan `kasir_permissions` (di-filter by updated_at, bukan bagian
    // dari data yang menumpuk) — jadi `result.received` TIDAK hanya
    // menghitung transaksi. Fokus assert di sini pada ISI tabel transactions
    // klien secara spesifik, bukan angka agregat `received`.
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    final clientTxIds =
        (await clientDb.select(clientDb.transactions).get()).map((t) => t.id);
    expect(clientTxIds, contains('tx-baru-host'));
    expect(clientTxIds, isNot(contains('tx-lama-host')),
        reason: 'transaksi host yang lebih lama dari watermark tidak boleh '
            'ikut terkirim ulang');

    // Watermark harus MAJU setelah sync sukses (bukan tetap statis).
    final newWatermark = await clientDb.getSetting(_kWatermarkKey);
    expect(newWatermark, isNotNull);
    expect(DateTime.parse(newWatermark!).isAfter(DateTime(2025, 1, 1)), isTrue);

    await hostDb.close();
    await clientDb.close();
  });

  test(
      'watermark download TIDAK memengaruhi arah upload — transaksi lama '
      'milik klien tetap terkirim penuh ke antrian approval host',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());

    // Transaksi lama milik KLIEN sendiri — jauh lebih lama dari watermark
    // yang akan di-set di bawah.
    await clientDb.into(clientDb.transactions).insert(TransactionsCompanion.insert(
          id: 'tx-lama-klien',
          localId: 'K1-1',
          status: 'lunas',
          total: 5000,
          paid: 5000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(DateTime(2020, 1, 1)),
        ));

    // Watermark DOWNLOAD klien sudah maju jauh (baru-baru ini) — kalau arah
    // upload SALAH ikut memakai watermark ini, tx-lama-klien tidak akan
    // pernah terkirim ke host.
    await clientDb.setSetting(
        _kWatermarkKey, DateTime.now().toIso8601String());

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    // Data klien masuk antrian approval host (bukan auto-merge) — cek isinya.
    expect(LanSyncService.pendingQueue, hasLength(1));
    final queuedTxIds = LanSyncService.pendingQueue.single.tables['transactions']
            ?.map((r) => r['id']) ??
        const [];
    expect(queuedTxIds, contains('tx-lama-klien'),
        reason: 'arah upload harus tetap full-dump, TIDAK boleh ikut '
            'terpotong oleh watermark download');

    await hostDb.close();
    await clientDb.close();
  });
}
