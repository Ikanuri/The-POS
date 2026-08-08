import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/tutup_buku_service.dart';

/// Item 59 — Tutup Buku menghapus baris `stock_ledger` dalam periode yang
/// diarsipkan, TAPI baris carry-forward-nya cuma dibuat kalau SELURUH
/// riwayat satuan itu ikut terhapus (`remain == null`). Kalau satuan itu
/// PUNYA baris SEBELUM dan/atau SESUDAH periode (riwayat "campuran"),
/// carry-forward dilewati sepenuhnya — pembaca (`_rawBaseStock`, ambil baris
/// TERAKHIR apa adanya) kebetulan tetap benar, tapi `rebuildStockAfterForUnits`
/// (dipanggil sync host/client setelah merge `stock_ledger`, lihat dok di
/// `app_database.dart`) menjumlah ulang qty_change dari NOL memakai baris
/// yang TERSISA saja — kontribusi baris yang terhapus HILANG dari total,
/// saldo rusak permanen begitu perangkat lain sync.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.docsPath);
  final String docsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

Future<void> _insertLedger(
  AppDatabase db, {
  required String id,
  required String unitId,
  required double qtyChange,
  required double stockAfter,
  required DateTime createdAt,
}) =>
    db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
          id: id,
          productUnitId: unitId,
          type: 'adjustment',
          qtyChange: qtyChange,
          stockAfter: stockAfter,
          createdAt: Value(createdAt),
        ));

void main() {
  late Directory tempDir;
  late PathProviderPlatform originalPlatform;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pos_tutup_buku_stock_');
    originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPlatform;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
      'satuan dgn riwayat CAMPURAN (baris sebelum & sesudah periode) — '
      'stock_after tetap invarian setelah Tutup Buku + rebuildStockAfterForUnits',
      () async {
    final dbFile = File('${tempDir.path}/the_pos.db');
    final db = AppDatabase(NativeDatabase(dbFile));
    const unitId = 'unit-campuran';
    final periodStart = DateTime(2025, 4, 12);
    final periodEnd = DateTime(2026, 3, 30);

    // Sebelum periode: stok masuk 10.
    await _insertLedger(db,
        id: 'sl-before',
        unitId: unitId,
        qtyChange: 10,
        stockAfter: 10,
        createdAt: periodStart.subtract(const Duration(days: 5)));
    // Dalam periode (akan diarsipkan): jual 3, lalu masuk lagi 2.
    await _insertLedger(db,
        id: 'sl-in-1',
        unitId: unitId,
        qtyChange: -3,
        stockAfter: 7,
        createdAt: periodStart.add(const Duration(days: 1)));
    await _insertLedger(db,
        id: 'sl-in-2',
        unitId: unitId,
        qtyChange: 2,
        stockAfter: 9,
        createdAt: periodStart.add(const Duration(days: 2)));
    // Setelah periode: jual 4 lagi.
    await _insertLedger(db,
        id: 'sl-after',
        unitId: unitId,
        qtyChange: -4,
        stockAfter: 5,
        createdAt: periodEnd.add(const Duration(days: 3)));

    const expectedFinalStock = 5.0;

    await TutupBukuService.execute(
      db: db,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );

    // Baris dalam periode sudah terhapus, tapi carry-forward HARUS dibuat
    // supaya rebuild tidak kehilangan kontribusi -3+2 = -1.
    final remainingBefore = await (db.select(db.stockLedger)
          ..where((t) => t.productUnitId.equals(unitId)))
        .get();
    expect(remainingBefore.map((r) => r.id), isNot(contains('sl-in-1')));
    expect(remainingBefore.map((r) => r.id), isNot(contains('sl-in-2')));

    // Simulasikan yang terjadi saat sync (host/client) merge stock_ledger
    // dari device lain menyentuh satuan ini — rebuild dipanggil.
    await db.rebuildStockAfterForUnits({unitId});

    final latest = await (db.select(db.stockLedger)
          ..where((t) => t.productUnitId.equals(unitId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    expect(latest, isNotNull);
    expect(latest!.stockAfter, expectedFinalStock,
        reason: 'saldo akhir HARUS tetap invarian (5) setelah Tutup Buku '
            'lalu rebuildStockAfterForUnits — sebelum fix, kontribusi baris '
            'yang diarsipkan (-3+2=-1) hilang dari penjumlahan ulang, saldo '
            'jadi salah (6, bukan 5)');
    await db.close();
  });

  test(
      'satuan yang SELURUH riwayatnya berada di periode yang diarsipkan — '
      'tetap dapat carry-forward (perilaku lama tetap benar)', () async {
    final dbFile = File('${tempDir.path}/the_pos.db');
    final db = AppDatabase(NativeDatabase(dbFile));
    const unitId = 'unit-habis';
    final periodStart = DateTime(2025, 4, 12);
    final periodEnd = DateTime(2026, 3, 30);

    await _insertLedger(db,
        id: 'sl-1',
        unitId: unitId,
        qtyChange: 20,
        stockAfter: 20,
        createdAt: periodStart.add(const Duration(days: 1)));
    await _insertLedger(db,
        id: 'sl-2',
        unitId: unitId,
        qtyChange: -6,
        stockAfter: 14,
        createdAt: periodStart.add(const Duration(days: 2)));

    await TutupBukuService.execute(
      db: db,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );

    final remaining = await (db.select(db.stockLedger)
          ..where((t) => t.productUnitId.equals(unitId)))
        .get();
    expect(remaining, hasLength(1),
        reason: 'carry-forward tetap harus dibuat spt sebelumnya kalau '
            'seluruh riwayat satuan itu ikut terarsip');
    expect(remaining.single.stockAfter, 14);
    await db.close();
  });
}
