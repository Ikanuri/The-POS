import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Reproduksi laporan user: setelah sync asisten -> owner, transaksi yang
/// diterima tampil TANPA daftar item (struk cuma stempel Lunas/Tempo +
/// Total, kosong di antaranya) walau `transactions` & `transaction_payments`
/// tampak normal. Test ini pakai `PRAGMA foreign_keys = ON` (production
/// SEBENARNYA mengaktifkan ini di `_openConnection`, tapi `NativeDatabase.
/// memory()` polos di test lain TIDAK — jadi bug FK-related bisa lolos dari
/// suite yang ada).
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

Future<AppDatabase> _openWithForeignKeys() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.customStatement('PRAGMA foreign_keys = ON;');
  return db;
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
    tempDir = Directory.systemTemp.createTempSync('pos_sync_items_repro_');
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

  test(
      'transaksi + item + pembayaran dari klien (asisten) muncul UTUH di '
      'host (owner) setelah approveSync — bukan cuma header+pembayaran',
      () async {
    final hostDb = await _openWithForeignKeys();
    final clientDb = await _openWithForeignKeys();
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    final createdAt = DateTime(2026, 7, 20, 14, 52, 0);

    await clientDb.into(clientDb.transactions).insert(TransactionsCompanion.insert(
          id: 'tx-1',
          localId: 'A1-20260720-0040',
          status: 'tempo',
          total: 381250,
          paid: 382000,
          changeAmount: 750,
          paymentMethod: 'tempo',
          createdAt: Value(createdAt),
        ));
    await clientDb.into(clientDb.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'item-1',
          transactionId: 'tx-1',
          productId: 'prod-1',
          productUnitId: 'unit-1',
          qty: 2,
          priceAtSale: 150000,
          originalPrice: 150000,
          subtotal: 381250,
        ));
    await clientDb.into(clientDb.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
          id: 'pay-1',
          transactionId: 'tx-1',
          amount: 382000,
          method: 'tempo',
          paidAt: Value(createdAt),
          changeGiven: const Value(750),
        ));

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-store-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-store-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    final pending = LanSyncService.pendingQueue.single;
    await LanSyncService.approveSync(pending.id);

    final hostTx = await (hostDb.select(hostDb.transactions)
          ..where((t) => t.id.equals('tx-1')))
        .getSingleOrNull();
    expect(hostTx, isNotNull, reason: 'header transaksi harus ter-merge');

    final hostItems = await (hostDb.select(hostDb.transactionItems)
          ..where((t) => t.transactionId.equals('tx-1')))
        .get();
    expect(hostItems, hasLength(1),
        reason:
            'item transaksi HARUS ikut ter-merge — inilah bug yang dilaporkan '
            'user (struk owner tampil kosong tanpa daftar barang)');

    final hostPayments = await (hostDb.select(hostDb.transactionPayments)
          ..where((t) => t.transactionId.equals('tx-1')))
        .get();
    expect(hostPayments, hasLength(1),
        reason: 'pembayaran ikut ter-merge (sisi ini SUDAH benar per laporan user)');
  });

  test(
      'satu baris transaction_items dari klien yang MELANGGAR FK '
      '(transaction_id yatim — mis. dari bug/state korup device lain) TIDAK '
      'BOLEH menggagalkan merge item transaksi LAIN yang valid dalam batch '
      'sync yang sama', () async {
    final hostDb = await _openWithForeignKeys();
    addTearDown(hostDb.close);

    // Transaksi valid SUDAH ada di host (header-nya benar) — item-nya
    // datang lewat sync ini.
    await hostDb.into(hostDb.transactions).insert(TransactionsCompanion.insert(
          id: 'tx-good',
          localId: 'A1-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));

    final rows = <Map<String, Object?>>[
      {
        'id': 'item-good',
        'transaction_id': 'tx-good',
        'product_id': 'p1',
        'product_unit_id': 'u1',
        'qty': 1.0,
        'price_at_sale': 10000,
        'original_price': 10000,
        'price_overridden': 0,
        'cost_at_sale': 0,
        'subtotal': 10000,
      },
      {
        // Baris yatim: transaction_id TIDAK ADA sama sekali di host —
        // simulasi state korup/parsial di device pengirim.
        'id': 'item-orphan',
        'transaction_id': 'tx-does-not-exist',
        'product_id': 'p2',
        'product_unit_id': 'u2',
        'qty': 1.0,
        'price_at_sale': 5000,
        'original_price': 5000,
        'price_overridden': 0,
        'cost_at_sale': 0,
        'subtotal': 5000,
      },
    ];

    await hostDb.mergeRows('transaction_items', rows, true);

    final goodItem = await (hostDb.select(hostDb.transactionItems)
          ..where((t) => t.transactionId.equals('tx-good')))
        .getSingleOrNull();
    expect(goodItem, isNotNull,
        reason: 'item transaksi VALID dalam batch yang sama tidak boleh ikut '
            'hilang gara-gara SATU baris lain melanggar FK — SQLite '
            '"INSERT OR IGNORE" TIDAK menekan pelanggaran FOREIGN KEY (beda '
            'dari pelanggaran UNIQUE/PK), jadi baris itu tetap throw dan '
            'me-rollback SELURUH transaction() yang membungkus loop baris — '
            'inilah mekanisme "semua riwayat kosong" yang dilaporkan user');
  });
}
