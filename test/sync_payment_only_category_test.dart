import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/pengaturan/sync_screen.dart';

/// Item 57 — pelunasan/cicilan/item susulan ("Tambah Belanjaan") ke
/// transaksi yang HEADER-nya (`transactions`) sudah lebih dulu tersinkron
/// TIDAK PERNAH kirim ulang header itu (`dumpSince` filter `created_at`,
/// tidak berubah saat melunasi) — payload sync bisa HANYA berisi
/// `transaction_payments` baru dgn `transactions` KOSONG.
/// `_approve()` (`sync_screen.dart`) dulu hitung jumlah kategori "Transaksi"
/// cuma dari tabel PERTAMA (`tables.first` = `transactions`) — kalau itu
/// kosong, kategori dianggap tidak ada data sama sekali walau
/// `transaction_payments`-nya berisi, dan payload yang HANYA berisi itu
/// otomatis di-reject PERMANEN dgn pesan salah "tidak ada data baru".
///
/// Test level 1 (logic murni, lihat CLAUDE.md §Metode Test): hitungan
/// kategori dites langsung sbg fungsi murni (`computeAvailableSyncCategories`,
/// diekstrak dari `_approve()` khusus supaya testable tanpa widget — widget
/// test utk alur approve penuh terbukti rawan hang krn `approveSync`
/// melakukan banyak round-trip async NativeDatabase yg tidak selalu
/// ter-drain benar oleh `pumpAndSettle` biasa). Merge sungguhan (baris
/// pembayaran benar-benar sampai ke DB) dites terpisah di level DB murni,
/// via `LanSyncService.approveSync` langsung.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.docsPath);
  final String docsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

PendingSyncItem _item(Map<String, List<Map<String, Object?>>> tables) =>
    PendingSyncItem(
      id: 'q1',
      fromIp: '192.168.1.50',
      arrivedAt: DateTime(2026, 1, 1),
      tables: tables,
      since: DateTime(2026, 1, 1),
      tablesSummary: '',
    );

void main() {
  group('computeAvailableSyncCategories (logic murni)', () {
    test(
        'payload HANYA berisi transaction_payments (header transactions '
        'kosong) — kategori "Transaksi" TETAP terhitung, bukan dianggap '
        'kosong', () {
      final available = computeAvailableSyncCategories(_item({
        'transactions': const [],
        'transaction_items': const [],
        'transaction_payments': [
          {'id': 'pay1', 'transaction_id': 'tx1'}
        ],
      }));

      expect(available.containsKey('Transaksi'), isTrue,
          reason: 'sebelum fix, count cuma dihitung dari tables.first '
              '(transactions, kosong) -> kategori Transaksi hilang total dari '
              '"available", walau transaction_payments ada isi');
      expect(available['Transaksi']!.count, 1);
    });

    test('payload benar-benar kosong SEMUA tabel -> tidak ada kategori tersedia',
        () {
      final available = computeAvailableSyncCategories(_item({
        'transactions': const [],
        'transaction_items': const [],
        'transaction_payments': const [],
      }));
      expect(available, isEmpty);
    });

    test('payload dgn header transactions BERISI -> tetap terhitung normal',
        () {
      final available = computeAvailableSyncCategories(_item({
        'transactions': [
          {'id': 'tx1'}
        ],
        'transaction_items': const [],
        'transaction_payments': const [],
      }));
      expect(available['Transaksi']!.count, 1);
    });
  });

  group('merge sungguhan (DB murni)', () {
    late Directory tempDir;
    late PathProviderPlatform originalPathProvider;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('pos_payment_only_merge_');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      tempDir.deleteSync(recursive: true);
    });

    test(
        'allowedTables (dari kategori yg benar terhitung) benar² membawa '
        'baris transaction_payments sampai merge ke host', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      LanSyncService.debugSetDb(db);

      // Header transaksi SUDAH ada di host (dari sync sebelumnya).
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx1',
            localId: 'K1-1',
            status: 'tempo',
            total: 50000,
            paid: 0,
            changeAmount: 0,
            paymentMethod: 'tempo',
          ));

      final tablesJson = jsonEncode({
        'transactions': [],
        'transaction_items': [],
        'transaction_payments': [
          {
            'id': 'pay1',
            'transaction_id': 'tx1',
            'amount': 20000,
            'method': 'tunai',
            'paid_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'change_given': 0,
          }
        ],
        'stock_ledger': [],
        'loyalty_point_ledger': [],
        'expenses': [],
      });
      await db.enqueueSyncUpload(
        id: 'q1',
        fromIp: '192.168.1.50',
        tablesJson: tablesJson,
        since: DateTime(2026, 1, 1),
        tablesSummary: '1 pembayaran',
      );

      final row = await db.getSyncUploadQueueItem('q1');
      final item = PendingSyncItem(
        id: row!.id,
        fromIp: row.fromIp,
        arrivedAt: row.arrivedAt,
        tables: (jsonDecode(row.tablesJson) as Map<String, dynamic>).map(
          (k, v) => MapEntry(
              k,
              (v as List)
                  .cast<Map<String, dynamic>>()
                  .map((r) => r.map<String, Object?>((rk, rv) => MapEntry(rk, rv)))
                  .toList()),
        ),
        since: row.since,
        tablesSummary: row.tablesSummary,
      );

      // Ini persis apa yang dilakukan `_approve()` yang sudah diperbaiki:
      // hitung available via computeAvailableSyncCategories, lalu bangun
      // `allowed` dari SEMUA kategori yang terdeteksi.
      final available = computeAvailableSyncCategories(item);
      expect(available, isNotEmpty,
          reason: 'kalau ini kosong, alur UI akan auto-reject item ini '
              'PERMANEN sebelum sempat sampai ke approveSync sama sekali');
      final allowed = <String>{
        for (final v in available.values) ...v.tables
      };

      final received =
          await LanSyncService.approveSync('q1', allowedTables: allowed);
      expect(received, 1);

      final payments = await db.getPaymentsForTx('tx1');
      expect(payments, hasLength(1),
          reason: 'baris pembayaran susulan harus benar-benar ter-merge ke '
              'host');
      expect(payments.single.amount, 20000);
      expect(await db.listSyncUploadQueue(), isEmpty);
    });
  });
}
