import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/sync_state_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/pengaturan/sync_screen.dart';

/// Pola escape HttpOverrides sama seperti `lan_sync_upload_queue_test.dart`.
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

/// Item 61 — 5 temuan menengah dari audit sync sesi 6 Agustus. Satu file,
/// 5 group, masing-masing menguji fix-nya sendiri secara terpisah.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/network_info'),
          (call) async => call.method == 'wifiIPAddress' ? '127.0.0.1' : null);

  group('61.1 — resetDownloadWatermark (pasangan resetUploadWatermark)', () {
    test('reset watermark download ke epoch (string kosong)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.setSetting(
          'last_sync_download_at', DateTime(2026, 1, 1).toIso8601String());

      await LanSyncService.resetDownloadWatermark(db);

      final watermark = await db.getSetting('last_sync_download_at');
      expect(watermark, isEmpty,
          reason: 'watermark download harus direset — sebelum fix, TIDAK '
              'ADA cara reset watermark ini sama sekali dari mana pun, '
              'clock skew yang bikin watermark klien "lebih maju" dari jam '
              'host macet PERMANEN');
    });

    test(
        '"Sync Ulang Penuh" (provider) reset KEDUA watermark sekaligus, '
        'bukan cuma upload', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.setSetting('last_sync_upload_confirmed_at',
          DateTime(2026, 1, 1).toIso8601String());
      await db.setSetting(
          'last_sync_download_at', DateTime(2026, 1, 1).toIso8601String());

      final container =
          ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);
      await container.read(syncStateProvider.notifier).resetUploadWatermark();

      expect(await db.getSetting('last_sync_upload_confirmed_at'), isEmpty);
      expect(await db.getSetting('last_sync_download_at'), isEmpty,
          reason: 'disatukan jadi 1 tombol supaya user tidak perlu paham '
              'beda upload/download watermark utk pilih yang mana direset');
    });
  });

  group('61.2 — _reconcileTransactionTotals guard item kosong', () {
    test(
        'transaksi TANPA baris item sama sekali (item susulan di-skip via '
        'sync) — total LAMA dipertahankan, tidak ditimpa 0', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx1',
            localId: 'K1-1',
            status: 'lunas',
            total: 50000,
            paid: 50000,
            changeAmount: 0,
            paymentMethod: 'tunai',
          ));
      // Sengaja TIDAK insert baris transaction_items sama sekali — simulasi
      // item susulan yang di-skip permanen (parent header sempat ditolak,
      // FK gagal saat item baru datang belakangan).
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: 'tx1',
            amount: 50000,
            method: 'tunai',
          ));

      await db.reconcileTransactionsByIds({'tx1'});

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx1')))
          .getSingle();
      expect(tx.total, 50000,
          reason: 'total LAMA (50000) harus dipertahankan — sebelum fix, '
              'newTotal dihitung dari fold kosong = 0, MENIMPA total yang '
              'benar jadi 0 walau bukan genuinely nota kosong');
    });
  });

  group('61.3 — tie-break stock_after konsisten pembaca vs penulis-ulang', () {
    test(
        '2 baris stock_ledger pada DETIK YANG SAMA — _rawBaseStock & '
        'rebuildStockAfterForUnits harus sepakat baris mana yang "terakhir"',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const unitId = 'unit-1';
      final sameSecond = DateTime(2026, 1, 1, 10, 0, 0);

      // id SENGAJA dipilih terbalik dari urutan insert (row-B duluan scr
      // rowid, tapi 'row-A' < 'row-B' scr alfabet) — supaya tie-break
      // `id ASC` (lama, salah) & `rowid ASC` (baru, benar) MENGHASILKAN
      // urutan proses yang BEDA, baru test ini bisa membedakan keduanya.
      await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
            id: 'row-B',
            productUnitId: unitId,
            type: 'adjustment',
            qtyChange: 10,
            stockAfter: 10, // benar: baris PERTAMA scr insert (rowid).
            createdAt: Value(sameSecond),
          ));
      await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
            id: 'row-A',
            productUnitId: unitId,
            type: 'adjustment',
            qtyChange: 5,
            stockAfter: 15, // benar: baris KEDUA (kumulatif 10+5).
            createdAt: Value(sameSecond),
          ));

      // Pembaca (_rawBaseStock, rowid DESC) ambil 'row-A' (rowid TERAKHIR),
      // stock_after aslinya = 15 (benar).
      final beforeRebuild = await db.currentStock(unitId);
      expect(beforeRebuild, 15);

      await db.rebuildStockAfterForUnits({unitId});
      final afterRebuild = await db.currentStock(unitId);

      expect(afterRebuild, beforeRebuild,
          reason: 'pembaca (_rawBaseStock, tie-break rowid DESC) & '
              'rebuildStockAfterForUnits (skrg jg tie-break rowid, ASC) '
              'harus sepakat baris TERAKHIR yang sama — sebelum fix, '
              'rebuildStockAfterForUnits pakai tie-break id ASC (row-A duluan '
              'krn alfabet, walau row-B duluan scr insert) — cumulative row-A '
              'jadi cuma 5 (bukan 15), MENIMPA stock_after row-A yang benar '
              '(15) jadi salah, walau row-A itu juga yang dipilih pembaca');
      expect(afterRebuild, 15);
    });
  });

  group('61.4 — approval per-kategori: Stok wajib ikut Transaksi', () {
    const ownerDevice = DeviceIdentity(
        storeUuid: 's',
        storeKey: 'k',
        storeName: 'Toko',
        deviceName: 'Owner',
        deviceCode: 'O1',
        deviceRole: 'owner');

    tearDown(() {
      LanSyncService.debugHostRunningOverride = false;
    });

    testWidgets(
        'checkbox "Stok" otomatis tercentang & disabled selama "Transaksi" '
        'tercentang — tidak bisa dipisah lewat UI', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      LanSyncService.debugSetDb(db);
      LanSyncService.debugHostRunningOverride = true;

      await db.enqueueSyncUpload(
        id: 'q1',
        fromIp: '192.168.1.50',
        tablesJson: '{"transactions":[{"id":"tx1"}],'
            '"stock_ledger":[{"id":"sl1"}]}',
        since: DateTime(2026, 1, 1),
        tablesSummary: '1 transaksi, 1 stok',
      );

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider
            .overrideWith((ref) => DeviceNotifier()..state = ownerDevice),
      ]);
      addTearDown(container.dispose);

      await tester.binding.setSurfaceSize(const Size(430, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SyncScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Setuju'));
      await tester.pumpAndSettle();

      // Cari CheckboxListTile yang title-nya mengandung 'Stok'.
      final stokCheckbox = find.byWidgetPredicate((w) =>
          w is CheckboxListTile &&
          w.title is Text &&
          ((w.title as Text).data ?? '').contains('Stok'));
      expect(stokCheckbox, findsOneWidget);
      final checkboxWidget = tester.widget<CheckboxListTile>(stokCheckbox);
      expect(checkboxWidget.value, isTrue,
          reason: 'Stok harus otomatis tercentang selama Transaksi '
              'tercentang (default keduanya true)');
      expect(checkboxWidget.onChanged, isNull,
          reason: 'checkbox Stok harus DISABLED (tidak bisa di-uncheck) '
              'selama Transaksi masih tercentang — mencegah penjualan '
              'ter-approve tanpa pergerakan stoknya, PERMANEN');

      // Batal dialog supaya tidak memicu approveSync sungguhan (di luar
      // cakupan test ini, sudah dites terpisah di item 57/58).
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
    });
  });

  group('61.5 — soft-delete expenses propagate lewat sync', () {
    test('deleteExpense: UPDATE deleted_at, BUKAN hard DELETE — baris tetap '
        'ada di DB', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.addExpense(type: 'daily_expense', amount: 10000);
      final before = await db.select(db.expenses).get();
      final id = before.single.id;

      await db.deleteExpense(id);

      final after = await db.select(db.expenses).get();
      expect(after, hasLength(1),
          reason: 'baris HARUS tetap ada (soft-delete) — kalau hard DELETE, '
              'penghapusan ini tidak akan pernah propagate ke device lain '
              'yang sudah menerima expense ini (append-only, cuma kirim '
              'baris BARU)');
      expect(after.single.deletedAt, isNotNull);
    });

    test('query total/breakdown/harian MENGECUALIKAN expense yang '
        'soft-deleted', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.now();
      await db.addExpense(type: 'daily_expense', amount: 10000, createdAt: now);
      final rows = await db.select(db.expenses).get();
      await db.deleteExpense(rows.single.id);

      final total = await db.getNetProfitExpenseTotal(
          now.subtract(const Duration(days: 1)),
          now.add(const Duration(days: 1)));
      expect(total, 0);

      final breakdown = await db.getExpenseBreakdownByType(
          now.subtract(const Duration(days: 1)),
          now.add(const Duration(days: 1)));
      expect(breakdown, isEmpty);

      final daily = await db.getExpenseDailyTotals(
          now.subtract(const Duration(days: 1)),
          now.add(const Duration(days: 1)));
      expect(daily.values.every((v) => v == 0), isTrue);
    });

    test(
        'penghapusan expense yang SUDAH tersinkron ke device lain benar² '
        'propagate lewat sync berikutnya (bukan cuma UPDATE lokal yang '
        'terjebak)', () async {
      final hostDb = AppDatabase(NativeDatabase.memory());
      final clientDb = AppDatabase(NativeDatabase.memory());
      addTearDown(hostDb.close);
      addTearDown(clientDb.close);

      // Expense yang sama SUDAH ada di kedua device (spt hasil sync
      // sebelumnya) — updated_at/created_at lama, sebelum watermark.
      final oldCreatedAt = DateTime(2026, 1, 1);
      for (final db in [hostDb, clientDb]) {
        await db.into(db.expenses).insert(ExpensesCompanion.insert(
              id: 'exp-1',
              localId: 'EXP-1',
              type: 'daily_expense',
              amount: 15000,
              createdAt: Value(oldCreatedAt),
            ));
      }

      // Host hapus expense itu SEKARANG (created_at lama, deleted_at baru).
      await hostDb.deleteExpense('exp-1');

      final (_, token) = await LanSyncService.startHost(
          db: hostDb, storeKey: 'shared-store-key');
      addTearDown(LanSyncService.stopHost);

      // Client sync — watermark download client masih di epoch (belum
      // pernah sync), jadi dump host akan terambil, TAPI simulasikan kasus
      // realistis: watermark SUDAH lewat created_at lama expense ini
      // (sync sebelumnya sudah mengambilnya), cuma deleted_at yang baru.
      await clientDb.setSetting(
          'last_sync_download_at', DateTime(2026, 6, 1).toIso8601String());

      await _withRealHttp(() => LanSyncService.syncToHost(
            db: clientDb,
            storeKey: 'shared-store-key',
            hostIp: '127.0.0.1',
            syncToken: token,
          ));

      final clientExpense = await (clientDb.select(clientDb.expenses)
            ..where((t) => t.id.equals('exp-1')))
          .getSingle();
      expect(clientExpense.deletedAt, isNotNull,
          reason: 'penghapusan expense di host HARUS sampai ke client via '
              'sync berikutnya, walau created_at-nya sudah lama (lewat '
              'watermark download client) — deleted_at yang baru harus '
              'membuatnya ikut ter-dump ulang & ter-merge sbg UPDATE');
    });
  });
}
