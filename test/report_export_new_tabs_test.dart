import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/laporan/report_export.dart';

/// Tier 1 (DB murni) — 4 tab yang BARU bisa ekspor (permintaan user):
/// Hutang, Stok, Pengeluaran, Arus Kas. Setiap kasus cukup buktikan
/// `_buildPdf`/`_buildXlsx` (lewat `exportReport`, tapi kita panggil builder
/// PDF/XLSX secara tidak langsung — lihat catatan di bawah) berjalan tanpa
/// exception thd `AppDatabase(NativeDatabase.memory())` sungguhan & hasilkan
/// byte non-kosong berformat benar (PDF: magic bytes `%PDF`; XLSX: valid
/// zip, dibuktikan lewat `Excel.decodeBytes` round-trip).
///
/// `_buildPdf`/`_buildXlsx` privat (tak bisa dipanggil langsung dari test
/// lintas file) — dipanggil TIDAK LANGSUNG lewat `exportReport`/`shareReport`
/// akan menembus `FilePicker.saveFile`/`Share.shareXFiles` sungguhan (plugin
/// native tanpa mock method channel di codebase ini, lihat dok
/// `backup_share_option_test.dart`). Solusi: reproduksi test langsung ke
/// fungsi publik yang paling dekat — di sini kita test lewat pemanggilan
/// widget minimal yg memicu builder tanpa filesystem sungguhan tidak
/// tersedia, jadi test ini memvalidasi via `WidgetsFlutterBinding` + capture
/// exception dari builder PDF (butuh `BuildContext` utk _captureWidget tapi
/// tab baru TIDAK memakai chart capture, jadi context hanya dineruskan).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final range = DateTimeRange(
      start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 31, 23, 59, 59));

  Future<void> seed() async {
    // Pelanggan berhutang (nota tempo).
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'c1',
          name: 'Budi',
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 't1',
          localId: 'K1-0001',
          customerId: const Value('c1'),
          status: 'tempo',
          total: 50000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tempo',
          createdAt: Value(DateTime(2026, 8, 5)),
        ));

    // Produk stok — satu positif, satu negatif, satu tanpa harga pokok.
    Future<String> addProduct(String name,
        {int? groupId, int costPrice = 0}) async {
      final id = 'p-$name';
      final unitId = '$id-u';
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: id,
            name: name,
            productGroupId: Value(groupId),
          ));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
            id: unitId,
            productId: id,
            isBaseUnit: const Value(true),
          ));
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: '$unitId-t1',
            productUnitId: unitId,
            minQty: const Value(1),
            price: 10000,
            costPrice: Value(costPrice),
          ));
      return unitId;
    }

    final u1 = await addProduct('Gula', groupId: 1, costPrice: 12000);
    final u2 = await addProduct('Rusak', groupId: 1, costPrice: 5000);
    await db.adjustStock(productUnitId: u1, newQty: 10);
    await db.adjustStock(productUnitId: u2, newQty: -3);

    // Pengeluaran & pembayaran (kas masuk) utk Arus Kas.
    await db.addExpense(
        type: 'daily_expense', amount: 20000, createdAt: DateTime(2026, 8, 8));
    await db.addExpense(
        type: 'supplier_payment',
        amount: 75000,
        createdAt: DateTime(2026, 8, 9));

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 't2',
          localId: 'K1-0002',
          status: 'lunas',
          total: 30000,
          paid: 30000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(DateTime(2026, 8, 10)),
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
          id: 'pay1',
          transactionId: 't2',
          amount: 30000,
          method: 'tunai',
          paidAt: Value(DateTime(2026, 8, 10)),
        ));
  }

  void expectValidPdf(Uint8List bytes) {
    expect(bytes, isNotEmpty);
    final header = String.fromCharCodes(bytes.take(4));
    expect(header, '%PDF', reason: 'harus PDF valid (magic bytes %PDF)');
  }

  void expectValidXlsx(Uint8List bytes) {
    expect(bytes, isNotEmpty);
    // 'PK' magic bytes (zip) + round-trip decode via package:excel.
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4B);
    final decoded = Excel.decodeBytes(bytes);
    expect(decoded.tables.keys, isNotEmpty);
  }

  for (final tab in [
    ReportTab.hutang,
    ReportTab.stok,
    ReportTab.pengeluaran,
    ReportTab.arusKas,
  ]) {
    testWidgets(
        'ReportTab.${tab.name}: PDF & XLSX builder jalan tanpa exception & '
        'hasilkan byte format valid', (tester) async {
      await seed();

      late BuildContext capturedContext;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          capturedContext = context;
          return const SizedBox();
        }),
      ));
      await tester.pump();

      // Panggil lewat helper publik `buildReportBytesForTest` yang murni
      // meneruskan ke builder privat — lihat `report_export.dart` (fungsi
      // ini HANYA dipakai test, prefiks `@visibleForTesting`).
      final pdfBytes = await buildReportBytesForTest(
        context: capturedContext,
        db: db,
        range: range,
        tab: tab,
        format: 'pdf',
        storeName: 'Toko Uji',
      );
      expectValidPdf(pdfBytes);

      final xlsxBytes = await buildReportBytesForTest(
        context: capturedContext,
        db: db,
        range: range,
        tab: tab,
        format: 'xlsx',
        storeName: 'Toko Uji',
      );
      expectValidXlsx(xlsxBytes);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }

  // PLAN.md Item 47 — ekspor Ringkasan (PDF & XLSX) sekarang IKUT
  // menyertakan "Pengeluaran"/"Laba Bersih" (`getNetProfitExpenseTotal`),
  // konsisten dgn kartu on-screen `ringkasan_tab.dart` — sebelumnya grid KPI
  // ekspor cuma Omzet/Transaksi/HPP/Laba Kotor.
  testWidgets(
      'ReportTab.ringkasan XLSX: baris "Pengeluaran"/"Laba Bersih" ikut '
      'terekspor dgn angka net profit expense yg benar (subset '
      'daily_expense+change_given, BUKAN semua jenis)', (tester) async {
    await seed();

    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        capturedContext = context;
        return const SizedBox();
      }),
    ));
    await tester.pump();

    final bytes = await buildReportBytesForTest(
      context: capturedContext,
      db: db,
      range: range,
      tab: ReportTab.ringkasan,
      format: 'xlsx',
      storeName: 'Toko Uji',
    );
    expectValidXlsx(bytes);

    final decoded = Excel.decodeBytes(bytes);
    final sheet = decoded.tables[decoded.tables.keys.first]!;
    final rows = sheet.rows
        .map((r) => r.map((c) => c?.value?.toString()).toList())
        .toList();

    bool hasRow(String label, String value) => rows.any(
        (r) => r.isNotEmpty && r[0] == label && r.length > 1 && r[1] == value);

    // Seed HANYA punya 'daily_expense' 20000 di dalam netProfitExpenseTypes
    // ('supplier_payment' 75000 SENGAJA tidak ikut — subset P&L, bukan
    // "semua jenis pengeluaran" spt tab Pengeluaran).
    expect(hasRow('Pengeluaran', '20000'), isTrue,
        reason:
            'baris Pengeluaran harus muncul dgn subset netProfitExpenseTypes '
            'saja (20000), bukan total SEMUA pengeluaran (95000)');
    final labaKotorRow =
        rows.firstWhere((r) => r.isNotEmpty && r[0] == 'Laba Kotor');
    final labaKotor = int.parse(labaKotorRow[1]!);
    expect(hasRow('Laba Bersih', '${labaKotor - 20000}'), isTrue,
        reason: 'Laba Bersih = Laba Kotor - Pengeluaran (20000)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
