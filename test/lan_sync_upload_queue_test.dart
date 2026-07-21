import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Item 17 Fase 2 — antrian approval sync sisi host dipindah dari in-memory
/// (`_pendingQueue`, hilang total kalau app owner di-restart sebelum sempat
/// approve) ke tabel DB `sync_upload_queue` (persisten). Klien beralih dari
/// SELALU full-dump sejak epoch ke watermark upload incremental (aman
/// dilakukan sekarang justru KARENA antrian host durable — lihat dok
/// `_kUploadWatermarkKey` di `lan_sync_service.dart`).
///
/// Pola escape HttpOverrides & seam PathProvider sama seperti
/// `lan_sync_item41_test.dart`/`lan_sync_watermark_test.dart`.
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

TransactionsCompanion _tx(String id, String localId, DateTime createdAt) =>
    TransactionsCompanion.insert(
      id: id,
      localId: localId,
      status: 'lunas',
      total: 10000,
      paid: 10000,
      changeAmount: 0,
      paymentMethod: 'tunai',
      createdAt: Value(createdAt),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/network_info'),
          (call) async => call.method == 'wifiIPAddress' ? '127.0.0.1' : null);

  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pos_sync_upload_queue_');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    await LanSyncService.stopHost();
    PathProviderPlatform.instance = originalPathProvider;
    tempDir.deleteSync(recursive: true);
  });

  test(
      'antrian bertahan lintas "restart" host (tutup & buka ulang koneksi ke '
      'file DB yang sama) — TIDAK hilang seperti _pendingQueue in-memory lama',
      () async {
    final dbPath = '${tempDir.path}/host_restart.db';
    var hostDb = AppDatabase(NativeDatabase(File(dbPath)));
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(clientDb.close);

    await clientDb.into(clientDb.transactions).insert(
        _tx('tx-1', 'A1-1', DateTime(2026, 1, 1)));

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    // "Restart" host: matikan server & tutup KONEKSI DB (bukan file-nya) —
    // simulasi app owner di-kill sebelum sempat approve.
    await LanSyncService.stopHost();
    await hostDb.close();

    // Buka lagi koneksi BARU ke file YANG SAMA (persis app dibuka ulang).
    hostDb = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(hostDb.close);

    final queue = await hostDb.listSyncUploadQueue();
    expect(queue, hasLength(1),
        reason: 'antrian approval harus tetap ada setelah "restart" — '
            'inilah manfaat inti Item 17 (dulu _pendingQueue in-memory '
            'hilang total dalam skenario yang sama)');
    expect(queue.single.fromIp, '127.0.0.1');
  });

  test(
      'sync kedua dari klien yang sama HANYA kirim data BARU (delta), bukan '
      'full-dump ulang — setelah watermark upload maju dari sync pertama',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await clientDb.into(clientDb.transactions).insert(
        _tx('tx-1', 'A1-1', DateTime(2026, 1, 1)));

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    // Sync #1: full-dump (watermark upload klien masih epoch).
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));
    final queue1 = await hostDb.listSyncUploadQueue();
    expect(queue1.single.tablesJson, contains('tx-1'));
    await LanSyncService.approveSync(queue1.single.id);

    // Owner sudah approve — data tx-1 sudah resmi masuk. Sync #2 TANPA data
    // baru apa pun dari klien.
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));
    final queue2 = await hostDb.listSyncUploadQueue();
    // "1 slot per IP" — item lama sudah dihapus approveSync, item baru dari
    // sync #2 masuk lagi TAPI kosong (tidak ada transaksi baru).
    expect(queue2, hasLength(1));
    expect(queue2.single.tablesJson, isNot(contains('tx-1')),
        reason: 'sync kedua tidak boleh kirim ulang tx-1 — watermark upload '
            'klien sudah maju melewati transaksi itu, ini yang bikin sync '
            'makin ringan seiring waktu (beda dari full-dump lama)');
  });

  test(
      'Tolak (reject) PERMANEN — data yang ditolak TIDAK otomatis muncul '
      'lagi di sync berikutnya, walau device pengirim masih punya datanya',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await clientDb.into(clientDb.transactions).insert(
        _tx('tx-ditolak', 'A1-1', DateTime(2026, 1, 1)));

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));
    final pending = (await hostDb.listSyncUploadQueue()).single;
    await LanSyncService.rejectSync(pending.id);
    expect(await hostDb.listSyncUploadQueue(), isEmpty);

    // Sync lagi — klien MASIH punya tx-ditolak secara lokal, tapi
    // watermark upload-nya sudah maju melewati itu di sync sebelumnya.
    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));
    final queueAfterReject = await hostDb.listSyncUploadQueue();
    final stillHasRejectedTx = queueAfterReject.isNotEmpty &&
        queueAfterReject.single.tablesJson.contains('tx-ditolak');
    expect(stillHasRejectedTx, isFalse,
        reason: 'data yang sudah ditolak TIDAK BOLEH otomatis muncul lagi '
            '— beda dari perilaku full-dump lama');
  });

  test(
      '"Sync Ulang Penuh" (resetUploadWatermark) memaksa full-dump lagi, '
      'termasuk data yang tadinya ditolak', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await clientDb.into(clientDb.transactions).insert(
        _tx('tx-ditolak', 'A1-1', DateTime(2026, 1, 1)));

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));
    final pending = (await hostDb.listSyncUploadQueue()).single;
    await LanSyncService.rejectSync(pending.id);

    // Owner minta klien "Sync Ulang Penuh".
    await LanSyncService.resetUploadWatermark(clientDb);

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));
    final queueAfterReset = await hostDb.listSyncUploadQueue();
    expect(queueAfterReset.single.tablesJson, contains('tx-ditolak'),
        reason: 'Sync Ulang Penuh harus kirim ulang SEMUA data dari awal, '
            'termasuk yang sebelumnya sudah ditolak');
  });

  test(
      'watermark upload klien TIDAK maju kalau request gagal (host tidak '
      'bisa dihubungi) — sync berikutnya otomatis retry data yang sama',
      () async {
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(clientDb.close);

    await clientDb.into(clientDb.transactions).insert(
        _tx('tx-1', 'A1-1', DateTime(2026, 1, 1)));

    // Host TIDAK dijalankan — hostIp valid tapi tidak ada yang listen.
    await _withRealHttp(() => expectLater(
          LanSyncService.syncToHost(
            db: clientDb,
            storeKey: 'shared-store-key',
            hostIp: '127.0.0.1',
            syncToken: 'FAKE-TOKEN',
            connectTimeout: const Duration(milliseconds: 500),
            responseTimeout: const Duration(milliseconds: 500),
          ),
          throwsA(anything),
        ));

    final watermark =
        await clientDb.getSetting('last_sync_upload_confirmed_at');
    expect(watermark, isNull,
        reason: 'gagal terhubung ke host TIDAK BOLEH memajukan watermark '
            'upload — data harus otomatis dicoba lagi di sync berikutnya');
  });
}
