import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/tutup_buku_service.dart';

/// Item 31 — Tutup Buku dgn periode custom (bukan selalu 1 Jan–31 Des):
/// suggestPeriodStart() otomatis nyambung dari tutup buku terakhir/transaksi
/// tertua, execute() menerima periodStart/periodEnd eksplisit, manifest
/// menyimpan tanggal presisi utk ditampilkan di UI, arsip lama tetap terbaca.
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

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pos_tutup_buku_custom_');
    originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPlatform;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('suggestPeriodStart: belum pernah tutup buku → pakai tanggal '
      'transaksi PALING LAMA (bukan 1 Jan/tanggal setup)', () async {
    final dbFile = File('${tempDir.path}/the_pos.db');
    final db = AppDatabase(NativeDatabase(dbFile));
    await _insertTx(db,
        id: 'tx1',
        localId: 'K1-A',
        createdAtSec: DateTime(2025, 4, 12).millisecondsSinceEpoch ~/ 1000);
    await _insertTx(db,
        id: 'tx2',
        localId: 'K1-B',
        createdAtSec: DateTime(2025, 6, 1).millisecondsSinceEpoch ~/ 1000);

    final start = await TutupBukuService.suggestPeriodStart(db);
    expect(start, DateTime(2025, 4, 12));
    await db.close();
  });

  test('suggestPeriodStart: tidak ada transaksi sama sekali → null', () async {
    final dbFile = File('${tempDir.path}/the_pos.db');
    final db = AppDatabase(NativeDatabase(dbFile));
    final start = await TutupBukuService.suggestPeriodStart(db);
    expect(start, isNull);
    await db.close();
  });

  test('suggestPeriodStart: SUDAH pernah tutup buku → hari SETELAH '
      'periodEnd terakhir (last_archive_date), bukan transaksi tertua lagi',
      () async {
    final dbFile = File('${tempDir.path}/the_pos.db');
    final db = AppDatabase(NativeDatabase(dbFile));
    await _insertTx(db,
        id: 'tx1',
        localId: 'K1-A',
        createdAtSec: DateTime(2025, 4, 12).millisecondsSinceEpoch ~/ 1000);
    await _insertTx(db,
        id: 'tx2',
        localId: 'K1-B',
        createdAtSec: DateTime(2026, 3, 20).millisecondsSinceEpoch ~/ 1000);

    // Tutup buku periode pertama: 12 Apr 2025 s/d 30 Mar 2026 (Hari Raya).
    await TutupBukuService.execute(
      db: db,
      periodStart: DateTime(2025, 4, 12),
      periodEnd: DateTime(2026, 3, 30),
    );

    final nextStart = await TutupBukuService.suggestPeriodStart(db);
    expect(nextStart, DateTime(2026, 3, 31),
        reason: 'periode berikutnya harus nyambung PAS, tanpa celah/tumpang '
            'tindih dari periodEnd terakhir');
    await db.close();
  });

  test('execute: periode custom (bukan kalender penuh) menghapus HANYA '
      'transaksi dalam rentang [periodStart, periodEnd] INKLUSIF', () async {
    final dbFile = File('${tempDir.path}/the_pos.db');
    final db = AppDatabase(NativeDatabase(dbFile));
    final periodStart = DateTime(2025, 4, 12);
    final periodEnd = DateTime(2026, 3, 30);

    await _insertTx(db,
        id: 'tx-before',
        localId: 'K1-A',
        createdAtSec:
            periodStart.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/
                1000);
    await _insertTx(db,
        id: 'tx-in-range-start',
        localId: 'K1-B',
        createdAtSec: periodStart.millisecondsSinceEpoch ~/ 1000);
    await _insertTx(db,
        id: 'tx-in-range-end',
        localId: 'K1-C',
        // Jam 23:00 di hari periodEnd — harus TETAP terhitung (inklusif).
        createdAtSec: periodEnd.add(const Duration(hours: 23)).millisecondsSinceEpoch ~/
            1000);
    await _insertTx(db,
        id: 'tx-after',
        localId: 'K1-D',
        createdAtSec:
            periodEnd.add(const Duration(days: 1)).millisecondsSinceEpoch ~/
                1000);

    final result = await TutupBukuService.execute(
      db: db,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );

    expect(result.txArchived, 2,
        reason: 'hanya 2 tx dalam rentang inklusif [periodStart, periodEnd]');
    expect(result.archivedYear, 2026, reason: 'label tahun = tahun periodEnd');

    final remaining = await db.select(db.transactions).get();
    expect(remaining.map((t) => t.id).toSet(),
        {'tx-before', 'tx-after'});
    await db.close();
  });

  test('execute: manifest menyimpan tanggal presisi & txCount, terbaca via '
      'listArchiveEntries()', () async {
    final dbFile = File('${tempDir.path}/the_pos.db');
    final db = AppDatabase(NativeDatabase(dbFile));
    await _insertTx(db,
        id: 'tx1',
        localId: 'K1-A',
        createdAtSec: DateTime(2025, 5, 1).millisecondsSinceEpoch ~/ 1000);

    await TutupBukuService.execute(
      db: db,
      periodStart: DateTime(2025, 4, 12),
      periodEnd: DateTime(2026, 3, 30),
    );

    final entries = await TutupBukuService.listArchiveEntries(db);
    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.year, 2026);
    expect(entry.periodStart, DateTime(2025, 4, 12));
    expect(entry.periodEnd, DateTime(2026, 3, 30));
    expect(entry.txCount, 1);
    expect(entry.isLegacyFallback, isFalse);
    await db.close();
  });

  test('listArchiveEntries: arsip LAMA (file archive_YYYY.db tanpa entri '
      'manifest) TETAP tampil, ditandai isLegacyFallback', () async {
    final dbFile = File('${tempDir.path}/the_pos.db');
    final db = AppDatabase(NativeDatabase(dbFile));
    // Simulasikan arsip lama: file ada, TAPI tidak pernah tercatat di
    // manifest (skenario sebelum Item 31 ada).
    await File('${tempDir.path}/archive_2023.db').writeAsBytes([0]);

    final entries = await TutupBukuService.listArchiveEntries(db);
    expect(entries, hasLength(1));
    expect(entries.single.year, 2023);
    expect(entries.single.isLegacyFallback, isTrue);
    expect(entries.single.txCount, isNull);
    await db.close();
  });

  test('execute: periodEnd tidak setelah periodStart → ditolak', () async {
    final dbFile = File('${tempDir.path}/the_pos.db');
    final db = AppDatabase(NativeDatabase(dbFile));

    expect(
      () => TutupBukuService.execute(
        db: db,
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 1),
      ),
      throwsA(isA<TutupBukuException>()),
    );
    await db.close();
  });
}
