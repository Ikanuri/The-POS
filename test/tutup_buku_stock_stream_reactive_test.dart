import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/tutup_buku_service.dart';

/// Follow-up dari `product_deactivate_sync_reactive_test.dart` — kelas bug
/// yang SAMA (raw SQL tanpa `updates:`), lokasi BERBEDA: `TutupBukuService.
/// execute()` menghapus 10 tabel + insert 1 baris carry-forward lewat
/// `customUpdate`/`customInsert` TANPA parameter `updates:`. Data di DB
/// SUDAH BENAR setelah tutup buku (dibuktikan `tutup_buku_stock_carry_
/// forward_test.dart` dkk, semua one-shot query), tapi `StreamProvider`/
/// `.watch()` (mis. `watchStockOverview()`, dipakai layar Ringkasan) TIDAK
/// tahu tabel `stock_ledger`/`transactions`/dst berubah — jadi tidak
/// auto-refresh, layar yang sedang terbuka menampilkan angka STALE sampai
/// di-restart manual. Test ini membuktikan reaktivitas via `.listen()`
/// sungguhan ke `watchStockOverview()`, bukan cuma query ulang.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.docsPath);
  final String docsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

void main() {
  late Directory tempDir;
  late PathProviderPlatform originalPlatform;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pos_tutup_buku_stream_');
    originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPlatform;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
      'watchStockOverview() (Stream live) ikut ter-refresh otomatis setelah '
      'TutupBukuService.execute() — bukan cuma query one-shot', () async {
    final dbFile = File('${tempDir.path}/the_pos.db');
    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db.close);

    const unitId = 'unit-stream';
    final periodStart = DateTime(2025, 4, 12);
    final periodEnd = DateTime(2026, 3, 30);

    // Seed produk + satuan dasar (dibutuhkan watchStockOverview: JOIN
    // product_units x products, is_base_unit=1, is_active=1).
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Beras 5kg'),
      units: [
        ProductUnitsCompanion.insert(
            id: unitId, productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        unitId: [
          PriceTiersCompanion.insert(
              id: 't1', productUnitId: unitId, price: 65000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    // Seed stok dalam periode yang nanti diarsipkan (pola sama
    // `tutup_buku_stock_carry_forward_test.dart`).
    await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
          id: 'sl-1',
          productUnitId: unitId,
          type: 'adjustment',
          qtyChange: 20,
          stockAfter: 20,
          createdAt: Value(periodStart.add(const Duration(days: 1))),
        ));
    await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
          id: 'sl-2',
          productUnitId: unitId,
          type: 'adjustment',
          qtyChange: -6,
          stockAfter: 14,
          createdAt: Value(periodStart.add(const Duration(days: 2))),
        ));

    final emissions = <double?>[];
    final sub = db.watchStockOverview().listen((rows) {
      final row = rows.where((r) => r.unitId == unitId).toList();
      emissions.add(row.isEmpty ? null : row.single.stock);
    });
    addTearDown(sub.cancel);

    // Tunggu emission awal (sebelum tutup buku): stok = 14.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(emissions, isNotEmpty);
    expect(emissions.last, 14);
    final emissionCountBeforeTutupBuku = emissions.length;

    await TutupBukuService.execute(
      db: db,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );

    // Beri waktu stream Drift meng-emit ulang (async gap sungguhan, BUKAN
    // simulasi manual re-query).
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(emissions.length, greaterThan(emissionCountBeforeTutupBuku),
        reason: 'watchStockOverview() HARUS meng-emit lagi setelah Tutup '
            'Buku mengubah stock_ledger — kalau jumlah emission tidak '
            'bertambah, berarti Drift tidak tahu tabel ini berubah '
            '(customUpdate/customInsert tanpa `updates:`) dan layar '
            'Ringkasan akan terlihat "tidak berubah" walau data DB sudah '
            'benar sampai app di-restart manual');
    // Baris dalam periode dihapus, tapi carry-forward membawa saldo 14
    // (prior=0 + deletedSum=20-6=14) tetap ke baris terbaru.
    expect(emissions.last, 14,
        reason: 'nilai stok yang di-emit ulang harus mencerminkan saldo '
            'carry-forward pasca tutup buku (14), bukan nilai stale/null');

    // Drain: hindari StreamProvider hang saat db.close() di addTearDown.
  });
}
