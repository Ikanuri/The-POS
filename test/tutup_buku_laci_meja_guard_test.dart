import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/tutup_buku_service.dart';

/// Audit efisiensi storage — ditemukan: `left_behind_items`/`borrowed_items`/
/// `preorder_entries` (Laci Meja) TIDAK PERNAH diarsipkan/dibersihkan Tutup
/// Buku sama sekali, padahal kolom `transaction_id`-nya FK ke
/// `transactions.id` (TANPA `ON DELETE CASCADE`) dan `PRAGMA foreign_keys =
/// ON` aktif. Kalau ADA nota dalam periode yang diarsipkan yang masih punya
/// baris Laci Meja (apalagi yang BELUM SELESAI — titip belum diambil,
/// pinjaman belum kembali, pre-order belum dipenuhi), `DELETE FROM
/// transactions` akan menabrak "FOREIGN KEY constraint failed" dan SELURUH
/// Tutup Buku gagal/rollback. Fix: (1) blokir dulu kalau ada yang BELUM
/// SELESAI (jangan diam-diam buang tugas operasional aktif), (2) hapus yang
/// SUDAH SELESAI bersama notanya (riwayatnya tetap ada di file arsip).
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.docsPath);
  final String docsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

Future<void> _insertTx(AppDatabase db,
    {required String id,
    required String localId,
    required int createdAtSec}) async {
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id,
        localId: localId,
        status: 'lunas',
        total: 10000,
        paid: 10000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt:
            Value(DateTime.fromMillisecondsSinceEpoch(createdAtSec * 1000)),
      ));
}

void main() {
  late Directory tempDir;
  late PathProviderPlatform originalPlatform;
  final periodStart = DateTime(2025, 1, 1);
  final periodEnd = DateTime(2025, 12, 31);
  final inRangeSec = DateTime(2025, 6, 1).millisecondsSinceEpoch ~/ 1000;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pos_tutup_buku_laci_');
    originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPlatform;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  AppDatabase openDb() =>
      AppDatabase(NativeDatabase(File('${tempDir.path}/the_pos.db')));

  test(
      'titip/ketinggalan BELUM diambil di periode -> execute() DITOLAK, '
      'transaksi TIDAK jadi terhapus (bukan FK crash diam-diam)', () async {
    final db = openDb();
    await _insertTx(db, id: 'tx1', localId: 'K1-A', createdAtSec: inRangeSec);
    await db.into(db.leftBehindItems).insert(LeftBehindItemsCompanion.insert(
          id: 'lbi1',
          transactionId: 'tx1',
          itemName: 'Payung',
          jenis: 'ketinggalan',
        ));

    await expectLater(
      TutupBukuService.execute(
          db: db, periodStart: periodStart, periodEnd: periodEnd),
      throwsA(isA<TutupBukuException>()),
    );

    final txs = await db.select(db.transactions).get();
    expect(txs, hasLength(1),
        reason: 'ditolak sebelum menghapus apa pun — bukan rollback '
            'setengah-jalan');
    await db.close();
  });

  test(
      'pinjaman BELUM kembali penuh di periode -> execute() DITOLAK',
      () async {
    final db = openDb();
    await _insertTx(db, id: 'tx1', localId: 'K1-A', createdAtSec: inRangeSec);
    await db.into(db.borrowedItems).insert(BorrowedItemsCompanion.insert(
          id: 'bi1',
          transactionId: 'tx1',
          itemName: 'Galon',
          qty: 2,
        ));

    await expectLater(
      TutupBukuService.execute(
          db: db, periodStart: periodStart, periodEnd: periodEnd),
      throwsA(isA<TutupBukuException>()),
    );
    await db.close();
  });

  test('pre-order BELUM dipenuhi/dibatalkan di periode -> execute() DITOLAK',
      () async {
    final db = openDb();
    await _insertTx(db, id: 'tx1', localId: 'K1-A', createdAtSec: inRangeSec);
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
          id: 'pe1',
          productId: 'p1',
          productUnitId: 'u1',
          transactionId: const Value('tx1'),
          customerName: 'Budi',
          qtyOrdered: 1,
        ));

    await expectLater(
      TutupBukuService.execute(
          db: db, periodStart: periodStart, periodEnd: periodEnd),
      throwsA(isA<TutupBukuException>()),
    );
    await db.close();
  });

  test(
      'titip SUDAH diambil (collectedAt terisi) di periode -> execute() '
      'BERHASIL, baris Laci Meja ikut terhapus bersama notanya', () async {
    final db = openDb();
    await _insertTx(db, id: 'tx1', localId: 'K1-A', createdAtSec: inRangeSec);
    await db.into(db.leftBehindItems).insert(LeftBehindItemsCompanion.insert(
          id: 'lbi1',
          transactionId: 'tx1',
          itemName: 'Payung',
          jenis: 'ketinggalan',
          collectedAt: Value(DateTime(2025, 6, 2)),
        ));

    final result = await TutupBukuService.execute(
        db: db, periodStart: periodStart, periodEnd: periodEnd);
    expect(result.txArchived, 1);

    final txs = await db.select(db.transactions).get();
    expect(txs, isEmpty);
    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, isEmpty,
        reason: 'baris yg sudah selesai ikut terhapus (riwayat tetap ada '
            'di file arsip)');
    await db.close();
  });

  test(
      'baris Laci Meja BELUM selesai untuk transaksi DI LUAR periode -> '
      'tidak menghalangi Tutup Buku sama sekali', () async {
    final db = openDb();
    final outsideSec =
        periodEnd.add(const Duration(days: 5)).millisecondsSinceEpoch ~/ 1000;
    await _insertTx(db,
        id: 'tx-in', localId: 'K1-A', createdAtSec: inRangeSec);
    await _insertTx(db,
        id: 'tx-out', localId: 'K1-B', createdAtSec: outsideSec);
    await db.into(db.leftBehindItems).insert(LeftBehindItemsCompanion.insert(
          id: 'lbi1',
          transactionId: 'tx-out',
          itemName: 'Payung',
          jenis: 'ketinggalan',
        ));

    final result = await TutupBukuService.execute(
        db: db, periodStart: periodStart, periodEnd: periodEnd);
    expect(result.txArchived, 1);

    final txs = await db.select(db.transactions).get();
    expect(txs.map((t) => t.id).toSet(), {'tx-out'});
    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1),
        reason: 'baris di luar periode tidak tersentuh sama sekali');
    await db.close();
  });
}
