import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Item 41 (audit 18 Juli) — regresi sync LAN, round-trip host<->klien
/// SUNGGUHAN via 127.0.0.1 (server shelf asli, bukan mock):
///  A.1  saldo stok direkonsiliasi ulang setelah merge (kedua arah) —
///       baris ledger device lain membawa `stock_after` hitungan lokalnya
///       sendiri, tanpa rebuild saldo diam-diam melompat ke pandangan
///       device lain.
///  A.2  watermark download disimpan sbg UTC eksplisit (suffix 'Z') —
///       string waktu-lokal tanpa offset ditafsirkan ulang di zona waktu
///       pembaca (host bisa beda zona: WIB/WITA/WIT).
///  A.3  antrian approval host: SATU slot per IP klien — sync berulang
///       sebelum owner approve tidak menumpuk salinan full-dump di RAM.
///  B.2  respons host kini ber-HMAC dan klien memverifikasinya — sync
///       sukses di test ini sekaligus membuktikan hitungan kedua sisi
///       cocok (mismatch = syncToHost throw dan test gagal).
///
/// Pola escape HttpOverrides sama dgn lan_sync_watermark_test.dart.
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

/// approveSync memanggil TutupBukuService.listArchivedYears →
/// getApplicationDocumentsDirectory; arahkan ke temp dir kosong (tidak ada
/// arsip → filter tahun-arsip jadi pass-through).
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.docsPath);
  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
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
    tempDir = Directory.systemTemp.createTempSync('pos_item41_sync_');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    await LanSyncService.stopHost();
    for (final item in LanSyncService.pendingQueue.toList()) {
      LanSyncService.rejectSync(item.id);
    }
    PathProviderPlatform.instance = originalPathProvider;
    tempDir.deleteSync(recursive: true);
  });

  StockLedgerCompanion ledgerRow({
    required String id,
    required double qtyChange,
    required double stockAfter,
    required DateTime at,
    String type = 'adjustment',
  }) =>
      StockLedgerCompanion.insert(
        id: id,
        productUnitId: 'u1',
        type: type,
        qtyChange: qtyChange,
        stockAfter: stockAfter,
        createdAt: Value(at),
      );

  test(
      'A.1+A.2+B.2 — saldo stok host & klien direkonsiliasi setelah merge '
      '(bukan menelan stock_after device lain); watermark tersimpan UTC',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    final t1 = DateTime(2026, 7, 1, 10, 0, 0);
    final t2 = DateTime(2026, 7, 1, 10, 0, 10);
    final t3 = DateTime(2026, 7, 1, 10, 0, 20);

    // Host: stok masuk +10, lalu jual 2 → pandangan host = 8.
    await hostDb.into(hostDb.stockLedger).insert(
        ledgerRow(id: 'h-in', qtyChange: 10, stockAfter: 10, at: t1));
    await hostDb.into(hostDb.stockLedger).insert(ledgerRow(
        id: 'h-sale', qtyChange: -2, stockAfter: 8, at: t2, type: 'sale'));

    // Klien: hanya tahu stok 5 (belum pernah sync), jual 2 → baris ledger
    // klien membawa stock_after=3 hasil hitungan LOKAL klien.
    await clientDb.into(clientDb.stockLedger).insert(ledgerRow(
        id: 'c-sale', qtyChange: -2, stockAfter: 3, at: t3, type: 'sale'));

    final (_, token) = await LanSyncService.startHost(
        db: hostDb, storeKey: 'shared-store-key');

    final result = await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));
    expect(result.pendingApproval, isTrue);

    // ── Sisi KLIEN: menerima baris host (+10@t1, -2@t2) yang langsung
    // di-merge; rebuild membuat saldo = 10-2-2 = 6, BUKAN 3 (baris klien
    // sendiri @t3 yang "terbaru" tapi stock_after-nya pandangan lama).
    expect(await clientDb.currentStock('u1'), 6,
        reason: 'saldo klien harus gabungan kronologis (10-2-2), bukan '
            'stock_after baris lokal terakhir');

    // A.2 — watermark tersimpan HARUS UTC eksplisit (suffix Z).
    final watermark = await clientDb.getSetting('last_sync_download_at');
    expect(watermark, isNotNull);
    expect(watermark!.endsWith('Z'), isTrue,
        reason: 'watermark tanpa offset ditafsirkan ulang pada zona waktu '
            'pembaca — wajib UTC eksplisit');

    // ── Sisi HOST: baris klien menunggu approval; setelah di-approve,
    // saldo host juga 6 — TANPA rebuild akan menelan stock_after=3 klien.
    expect(await hostDb.currentStock('u1'), 8,
        reason: 'sebelum approve, saldo host belum berubah');
    final pending = LanSyncService.pendingQueue.single;
    await LanSyncService.approveSync(pending.id);
    expect(await hostDb.currentStock('u1'), 6,
        reason: 'saldo host harus gabungan kronologis (10-2-2), bukan '
            'menelan stock_after=3 milik klien');
  });

  test(
      'A.3 — sync berulang dari klien yang sama menempati SATU slot antrian '
      '(full-dump terbaru superset dari yang lama), bukan menumpuk', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await clientDb.into(clientDb.stockLedger).insert(ledgerRow(
        id: 'c-1',
        qtyChange: 1,
        stockAfter: 1,
        at: DateTime(2026, 7, 1, 9)));

    final (_, token) = await LanSyncService.startHost(
        db: hostDb, storeKey: 'shared-store-key');

    for (var i = 0; i < 3; i++) {
      await _withRealHttp(() => LanSyncService.syncToHost(
            db: clientDb,
            storeKey: 'shared-store-key',
            hostIp: '127.0.0.1',
            syncToken: token,
          ));
    }

    expect(LanSyncService.pendingQueue.length, 1,
        reason: '3x sync dari IP yang sama harus menyisakan 1 item antrian '
            '(payload full-dump 50 MB x N = OOM di HP RAM kecil)');
  });
}
