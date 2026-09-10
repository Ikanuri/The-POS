import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/chart_utils.dart';

// Ekspor laporan PER KATEGORI (tab). Setiap tab punya PDF & XLSX sendiri.
// Grafik di PDF = tangkapan widget chart asli aplikasi (identik tampilannya).
// Dua jalur tujuan file: [exportReport] (simpan ke penyimpanan lewat
// FilePicker.saveFile — bukan Printing.sharePdf agar tidak merasterisasi
// seluruh halaman → menghindari Out of Memory & gagal diam) & [shareReport]
// (langsung ke share sheet OS lewat file sementara, TANPA nangkring di
// storage — dipicu dari ikon share di dropdown ekspor custom `laporan_
// screen.dart`, pola sama `saveOrShareExport` di `export_destination.dart`).

enum ReportTab {
  ringkasan,
  produk,
  pelanggan,
  transaksi,
  hutang,
  stok,
  pengeluaran,
  arusKas,
}

final _fmtRp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _fmtDate = DateFormat('dd/MM/yyyy');
final _fmtDateFile = DateFormat('yyyyMMdd');

String _tabLabel(ReportTab t) => switch (t) {
      ReportTab.ringkasan => 'Ringkasan',
      ReportTab.produk => 'Produk',
      ReportTab.pelanggan => 'Pelanggan',
      ReportTab.transaksi => 'Transaksi',
      ReportTab.hutang => 'Hutang',
      ReportTab.stok => 'Stok',
      ReportTab.pengeluaran => 'Pengeluaran',
      ReportTab.arusKas => 'Arus Kas',
    };

/// Hutang (buku hutang "sekarang") & Stok (snapshot nilai inventori
/// "sekarang") TIDAK terikat rentang tanggal — beda dari tab lain yang
/// laporan aktivitas dalam periode. Judul PDF kedua tab ini menampilkan
/// "per [tanggal ekspor]", bukan rentang tanggal yang sedang dipilih user.
bool _isSnapshotTab(ReportTab t) =>
    t == ReportTab.hutang || t == ReportTab.stok;

// ─── Orkestrator ekspor ────────────────────────────────────────────────────

Future<Uint8List> _buildReportBytes(BuildContext context, AppDatabase db,
    DateTimeRange range, ReportTab tab, String format, String storeName) {
  return format == 'pdf'
      ? _buildPdf(context, db, range, tab, storeName)
      : _buildXlsx(db, range, tab);
}

/// Dipakai HANYA oleh test (`test/report_export_new_tabs_test.dart`) —
/// jembatan tipis ke `_buildReportBytes` yang privat, supaya Tier 1 bisa
/// membuktikan builder PDF/XLSX tiap tab jalan thd `AppDatabase` sungguhan
/// TANPA menembus `FilePicker.saveFile`/`Share.shareXFiles` (plugin native
/// tanpa mock method channel di codebase ini, lihat dok
/// `backup_share_option_test.dart`).
@visibleForTesting
Future<Uint8List> buildReportBytesForTest({
  required BuildContext context,
  required AppDatabase db,
  required DateTimeRange range,
  required ReportTab tab,
  required String format,
  required String storeName,
}) =>
    _buildReportBytes(context, db, range, tab, format, storeName);

String _reportFileName(ReportTab tab, DateTimeRange range, String ext) =>
    'laporan_${_tabLabel(tab).toLowerCase().replaceAll(' ', '_')}_'
    '${_fmtDateFile.format(range.start)}-${_fmtDateFile.format(range.end)}.$ext';

/// Simpan laporan ke penyimpanan perangkat (`FilePicker.saveFile`) — perilaku
/// lama, dipicu tekan BADAN chip PDF/Excel (bukan ikon share) di dropdown
/// ekspor.
Future<void> exportReport({
  required BuildContext context,
  required WidgetRef ref,
  required DateTimeRange range,
  required ReportTab tab,
  required String format, // 'pdf' | 'xlsx'
  required String storeName,
}) async {
  final db = ref.read(databaseProvider);
  try {
    final bytes =
        await _buildReportBytes(context, db, range, tab, format, storeName);
    if (!context.mounted) return;
    final ext = format == 'pdf' ? 'pdf' : 'xlsx';
    final fname = _reportFileName(tab, range, ext);
    final path = await FilePicker.platform.saveFile(
      fileName: fname,
      bytes: bytes,
      type: FileType.any,
    );
    if (!context.mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Laporan ${_tabLabel(tab)} ($ext) tersimpan')));
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Gagal export: $e'),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
  }
}

/// Bagikan laporan LANGSUNG lewat share sheet OS, TANPA nangkring di
/// penyimpanan lokal dulu — dipicu tekan ikon share di chip PDF/Excel.
/// Byte-building sama persis dgn [exportReport] (`_buildReportBytes`),
/// cuma tujuan akhirnya beda: file sementara (dibersihkan `TempShareCleanup`
/// spt file share lain di app ini) → `Share.shareXFiles`.
Future<void> shareReport({
  required BuildContext context,
  required WidgetRef ref,
  required DateTimeRange range,
  required ReportTab tab,
  required String format, // 'pdf' | 'xlsx'
  required String storeName,
}) async {
  final db = ref.read(databaseProvider);
  try {
    final bytes =
        await _buildReportBytes(context, db, range, tab, format, storeName);
    if (!context.mounted) return;
    final ext = format == 'pdf' ? 'pdf' : 'xlsx';
    final fname = _reportFileName(tab, range, ext);
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/laporan_${DateTime.now().millisecondsSinceEpoch}_$fname');
    await file.writeAsBytes(bytes);
    if (!context.mounted) return;
    await Share.shareXFiles([XFile(file.path)],
        text: 'Laporan ${_tabLabel(tab)}'
            '${storeName.isEmpty ? '' : ' - $storeName'}');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Laporan ${_tabLabel(tab)} ($ext) dibagikan')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Gagal membagikan: $e'),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
  }
}

// ─── PDF builder per tab ────────────────────────────────────────────────────

Future<Uint8List> _buildPdf(BuildContext context, AppDatabase db,
    DateTimeRange range, ReportTab tab, String storeName) async {
  final doc = pw.Document();
  final body = <pw.Widget>[];

  switch (tab) {
    case ReportTab.ringkasan:
      final d = await _fetchRingkasan(db, range);
      // Tangkap chart asli aplikasi → gambar.
      Uint8List? donut;
      Uint8List? daily;
      if (context.mounted && d.byMethod.length >= 2) {
        donut = await _captureWidget(context,
            _PaymentDonutChart(byMethod: d.byMethod, total: d.revenue),
            width: 260);
      }
      if (context.mounted && d.daily.isNotEmpty) {
        daily = await _captureWidget(context, _DailyBarChart(daily: d.daily),
            width: 520);
      }
      body.add(_pdfKpiGrid([
        ('Omzet', _fmtRp.format(d.revenue)),
        ('Transaksi', '${d.txCount}'),
        ('HPP', _fmtRp.format(d.cogs)),
        ('Laba Kotor', _fmtRp.format(d.profit)),
        ('Pengeluaran', _fmtRp.format(d.expenses)),
        ('Laba Bersih', _fmtRp.format(d.netProfit)),
      ]));
      if (donut != null) {
        body.add(pw.SizedBox(height: 14));
        body.add(_pdfSection('Metode Pembayaran'));
        body.add(pw.Center(child: pw.Image(pw.MemoryImage(donut), width: 200)));
      }
      if (d.byMethod.isNotEmpty) {
        body.add(pw.SizedBox(height: 8));
        body.add(_pdfTable(
          ['Metode', 'Porsi', 'Nominal'],
          d.byMethod.entries.map((e) {
            final pct =
                d.revenue > 0 ? (e.value / d.revenue * 100).round() : 0;
            return [
              _methodLabel(e.key),
              '$pct%',
              _fmtRp.format(e.value),
            ];
          }).toList(),
          aligns: const [
            pw.TextAlign.left,
            pw.TextAlign.center,
            pw.TextAlign.right
          ],
        ));
      }
      if (daily != null) {
        body.add(pw.SizedBox(height: 14));
        body.add(_pdfSection('Penjualan Harian'));
        body.add(pw.Image(pw.MemoryImage(daily)));
      }

    case ReportTab.produk:
      final stats = await db.getTopProductsByRevenue(range.start, range.end);
      Uint8List? donut;
      if (context.mounted && stats.length >= 2) {
        final slices = _topSlices(
            stats.map((s) => (s.name, s.revenue)).toList());
        donut = await _captureWidget(
            context, _TopDonutChart(slices: slices.$1, otherValue: slices.$2),
            width: 360);
      }
      if (donut != null) {
        body.add(pw.Center(child: pw.Image(pw.MemoryImage(donut), width: 320)));
        body.add(pw.SizedBox(height: 12));
      }
      body.add(_pdfSection('Produk Terlaris'));
      body.add(pw.SizedBox(height: 4));
      body.add(_pdfTable(
        ['No', 'Produk', 'Qty', 'Omzet', 'Laba'],
        [
          for (var i = 0; i < stats.length; i++)
            [
              '${i + 1}',
              stats[i].name,
              _fmtQty(stats[i].qtySold),
              _fmtRp.format(stats[i].revenue),
              _fmtRp.format(stats[i].revenue - stats[i].cogs),
            ]
        ],
        aligns: const [
          pw.TextAlign.center,
          pw.TextAlign.left,
          pw.TextAlign.right,
          pw.TextAlign.right,
          pw.TextAlign.right,
        ],
        flex: const [1, 4, 1.4, 2.2, 2.2],
      ));

    case ReportTab.pelanggan:
      final stats = await db.getTopCustomersByRevenue(range.start, range.end);
      Uint8List? donut;
      if (context.mounted && stats.length >= 2) {
        final slices = _topSlices(
            stats.map((s) => (s.name, s.totalSpent)).toList());
        donut = await _captureWidget(
            context, _TopDonutChart(slices: slices.$1, otherValue: slices.$2),
            width: 360);
      }
      if (donut != null) {
        body.add(pw.Center(child: pw.Image(pw.MemoryImage(donut), width: 320)));
        body.add(pw.SizedBox(height: 12));
      }
      body.add(_pdfSection('Pelanggan Teratas'));
      body.add(pw.SizedBox(height: 4));
      body.add(_pdfTable(
        ['No', 'Pelanggan', 'Transaksi', 'Poin', 'Total Belanja'],
        [
          for (var i = 0; i < stats.length; i++)
            [
              '${i + 1}',
              stats[i].name.isEmpty ? 'Umum' : stats[i].name,
              '${stats[i].txCount}',
              '${stats[i].loyaltyPoints}',
              _fmtRp.format(stats[i].totalSpent),
            ]
        ],
        aligns: const [
          pw.TextAlign.center,
          pw.TextAlign.left,
          pw.TextAlign.center,
          pw.TextAlign.center,
          pw.TextAlign.right,
        ],
        flex: const [1, 4, 1.8, 1.4, 2.4],
      ));

    case ReportTab.transaksi:
      final txs =
          await db.getTransactionsInRange(range.start, range.end, limit: 2000);
      final ordered = txs.reversed.toList();
      body.add(_pdfSection('Daftar Transaksi'));
      body.add(pw.SizedBox(height: 4));
      if (txs.length >= 2000) {
        body.add(pw.Text(
          'Menampilkan 2000 transaksi terbaru. Persempit rentang tanggal untuk '
          'daftar lengkap.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ));
        body.add(pw.SizedBox(height: 4));
      }
      body.add(_pdfTable(
        ['No Nota', 'Tanggal', 'Pelanggan', 'Total', 'Status'],
        [
          for (final t in ordered)
            [
              t.localId,
              _fmtDate.format(t.createdAt),
              t.customerName ?? (t.customerId != null ? 'Pelanggan' : 'Umum'),
              _fmtRp.format(t.total),
              _statusLabel(t.status),
            ]
        ],
        aligns: const [
          pw.TextAlign.left,
          pw.TextAlign.left,
          pw.TextAlign.left,
          pw.TextAlign.right,
          pw.TextAlign.center,
        ],
        flex: const [2, 1.8, 2.4, 2, 1.6],
      ));

    case ReportTab.hutang:
      final debts = await db.getDebtBook();
      final totalDebt = debts.fold<int>(0, (s, e) => s + e.debt);
      const cap = 1000;
      final capped = debts.length > cap ? debts.sublist(0, cap) : debts;
      body.add(_pdfKpiGrid([
        ('Total Hutang', _fmtRp.format(totalDebt)),
        ('Pelanggan Berhutang', '${debts.length}'),
      ]));
      body.add(pw.SizedBox(height: 14));
      body.add(_pdfSection('Buku Hutang (diurut paling lama menunggak)'));
      body.add(pw.SizedBox(height: 4));
      if (debts.length > cap) {
        body.add(pw.Text(
          'Menampilkan $cap pelanggan paling lama menunggak dari '
          '${debts.length}.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ));
        body.add(pw.SizedBox(height: 4));
      }
      body.add(_pdfTable(
        ['Pelanggan', 'Menunggak', 'Nota', 'Jumlah Hutang'],
        [
          for (final e in capped)
            [e.name, '${e.daysOverdue} hari', '${e.count}', _fmtRp.format(e.debt)]
        ],
        aligns: const [
          pw.TextAlign.left,
          pw.TextAlign.center,
          pw.TextAlign.center,
          pw.TextAlign.right,
        ],
        flex: const [3, 1.6, 1, 2],
      ));

    case ReportTab.stok:
      final s = await _fetchStok(db);
      body.add(_pdfKpiGrid([
        ('Nilai Inventori', _fmtRp.format(s.grandTotal)),
        ('Produk Tanpa Harga Pokok', '${s.missingCostCount}'),
      ]));
      body.add(pw.SizedBox(height: 14));
      body.add(_pdfSection('Nilai per Kategori'));
      body.add(pw.SizedBox(height: 4));
      body.add(_pdfTable(
        ['Kategori', 'Nilai'],
        [for (final c in s.perCategory) [c.label, _fmtRp.format(c.value)]],
        aligns: const [pw.TextAlign.left, pw.TextAlign.right],
        flex: const [3, 2],
      ));
      if (s.negativeStock.isNotEmpty) {
        body.add(pw.SizedBox(height: 14));
        body.add(_pdfSection(
            'Stok Negatif (${s.negativeStock.length}) - perlu ditinjau'));
        body.add(pw.SizedBox(height: 4));
        body.add(_pdfTable(
          ['Produk', 'Stok'],
          [for (final r in s.negativeStock) [r.name, _fmtQty(r.stock)]],
          aligns: const [pw.TextAlign.left, pw.TextAlign.right],
          flex: const [3, 1],
        ));
      }

    case ReportTab.pengeluaran:
      final byType = await db.getExpenseBreakdownByType(range.start, range.end);
      final daily = await db.getExpenseDailyTotals(range.start, range.end);
      final total = byType.values.fold(0, (s, v) => s + v);
      final entries = byType.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      body.add(_pdfKpiGrid([
        ('Total Pengeluaran', _fmtRp.format(total)),
      ]));
      body.add(pw.SizedBox(height: 14));
      body.add(_pdfSection('Rincian per Jenis'));
      body.add(pw.SizedBox(height: 4));
      body.add(_pdfTable(
        ['Jenis', 'Porsi', 'Nominal'],
        [
          for (final e in entries)
            [
              _expenseTypeLabel(e.key),
              total > 0 ? '${(e.value / total * 100).round()}%' : '0%',
              _fmtRp.format(e.value),
            ]
        ],
        aligns: const [
          pw.TextAlign.left,
          pw.TextAlign.center,
          pw.TextAlign.right,
        ],
        flex: const [3, 1.4, 2],
      ));
      if (daily.isNotEmpty) {
        final sortedDaily = daily.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        body.add(pw.SizedBox(height: 14));
        body.add(_pdfSection('Tren Harian'));
        body.add(pw.SizedBox(height: 4));
        body.add(_pdfTable(
          ['Tanggal', 'Nominal'],
          [
            for (final e in sortedDaily)
              [_fmtDate.format(e.key), _fmtRp.format(e.value)]
          ],
          aligns: const [pw.TextAlign.left, pw.TextAlign.right],
          flex: const [2, 2],
        ));
      }

    case ReportTab.arusKas:
      final summary = await db.getCashFlowSummary(range.start, range.end);
      final daily = await db.getCashFlowDaily(range.start, range.end);
      final totalIn = summary.cashIn + summary.nonCashIn;
      final net = totalIn - summary.cashOut;
      body.add(_pdfKpiGrid([
        ('Kas Masuk', _fmtRp.format(totalIn)),
        ('Kas Keluar', _fmtRp.format(summary.cashOut)),
        ('Arus Kas Bersih', _fmtRp.format(net)),
      ]));
      body.add(pw.SizedBox(height: 14));
      body.add(_pdfSection('Rincian Kas Masuk'));
      body.add(pw.SizedBox(height: 4));
      final inEntries = summary.inByMethod.entries
          .where((e) => e.key != 'tempo')
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      body.add(_pdfTable(
        ['Metode', 'Nominal'],
        [
          for (final e in inEntries)
            [_cashMethodLabel(e.key), _fmtRp.format(e.value)]
        ],
        aligns: const [pw.TextAlign.left, pw.TextAlign.right],
        flex: const [3, 2],
      ));
      body.add(pw.SizedBox(height: 14));
      body.add(_pdfSection('Rincian Kas Keluar'));
      body.add(pw.SizedBox(height: 4));
      final outEntries = summary.outByType.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      body.add(_pdfTable(
        ['Jenis', 'Nominal'],
        [
          for (final e in outEntries)
            [_expenseTypeLabel(e.key), _fmtRp.format(e.value)]
        ],
        aligns: const [pw.TextAlign.left, pw.TextAlign.right],
        flex: const [3, 2],
      ));
      if (daily.isNotEmpty) {
        body.add(pw.SizedBox(height: 14));
        body.add(_pdfSection('Tren Harian'));
        body.add(pw.SizedBox(height: 4));
        body.add(_pdfTable(
          ['Tanggal', 'Masuk', 'Keluar'],
          [
            for (final d in daily)
              [
                _fmtDate.format(d.date),
                _fmtRp.format(d.cashIn),
                _fmtRp.format(d.cashOut),
              ]
          ],
          aligns: const [
            pw.TextAlign.left,
            pw.TextAlign.right,
            pw.TextAlign.right,
          ],
          flex: const [2, 2, 2],
        ));
      }
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    header: (ctx) => ctx.pageNumber == 1
        ? pw.SizedBox()
        : pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text('Laporan ${_tabLabel(tab)}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
          ),
    build: (ctx) => [
      pw.Header(
        level: 0,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(storeName.isEmpty ? 'Laporan' : storeName,
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(
              _isSnapshotTab(tab)
                  ? 'Laporan ${_tabLabel(tab)} - per '
                      '${_fmtDate.format(DateTime.now())}'
                  : 'Laporan ${_tabLabel(tab)} - '
                      '${_fmtDate.format(range.start)} s/d '
                      '${_fmtDate.format(range.end)}',
              style: const pw.TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 12),
      ...body,
    ],
  ));

  return doc.save();
}

// ─── XLSX builder per tab ───────────────────────────────────────────────────

Future<Uint8List> _buildXlsx(
    AppDatabase db, DateTimeRange range, ReportTab tab) async {
  final excel = Excel.createExcel();
  final sheet = excel[_tabLabel(tab)];

  switch (tab) {
    case ReportTab.ringkasan:
      final d = await _fetchRingkasan(db, range);
      sheet.appendRow([TextCellValue('Metrik'), TextCellValue('Nilai')]);
      sheet.appendRow(
          [TextCellValue('Omzet'), IntCellValue(d.revenue)]);
      sheet.appendRow(
          [TextCellValue('Jumlah Transaksi'), IntCellValue(d.txCount)]);
      sheet.appendRow([TextCellValue('HPP'), IntCellValue(d.cogs)]);
      sheet.appendRow([TextCellValue('Laba Kotor'), IntCellValue(d.profit)]);
      sheet.appendRow(
          [TextCellValue('Pengeluaran'), IntCellValue(d.expenses)]);
      sheet.appendRow(
          [TextCellValue('Laba Bersih'), IntCellValue(d.netProfit)]);
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([
        TextCellValue('Metode Pembayaran'),
        TextCellValue('Nominal'),
      ]);
      for (final e in d.byMethod.entries) {
        sheet.appendRow(
            [TextCellValue(_methodLabel(e.key)), IntCellValue(e.value)]);
      }

    case ReportTab.produk:
      final stats = await db.getTopProductsByRevenue(range.start, range.end);
      sheet.appendRow([
        TextCellValue('Produk'),
        TextCellValue('Qty'),
        TextCellValue('Omzet'),
        TextCellValue('Laba'),
      ]);
      for (final s in stats) {
        sheet.appendRow([
          TextCellValue(s.name),
          DoubleCellValue(s.qtySold),
          IntCellValue(s.revenue),
          IntCellValue(s.revenue - s.cogs),
        ]);
      }

    case ReportTab.pelanggan:
      final stats = await db.getTopCustomersByRevenue(range.start, range.end);
      sheet.appendRow([
        TextCellValue('Pelanggan'),
        TextCellValue('Transaksi'),
        TextCellValue('Poin'),
        TextCellValue('Total Belanja'),
      ]);
      for (final s in stats) {
        sheet.appendRow([
          TextCellValue(s.name.isEmpty ? 'Umum' : s.name),
          IntCellValue(s.txCount),
          IntCellValue(s.loyaltyPoints),
          IntCellValue(s.totalSpent),
        ]);
      }

    case ReportTab.transaksi:
      // Batas wajar — paket excel boros memori untuk ribuan baris.
      final txs =
          await db.getTransactionsInRange(range.start, range.end, limit: 10000);
      sheet.appendRow([
        TextCellValue('No Nota'),
        TextCellValue('Tanggal'),
        TextCellValue('Pelanggan'),
        TextCellValue('Total'),
        TextCellValue('Bayar'),
        TextCellValue('Status'),
      ]);
      for (final t in txs.reversed) {
        sheet.appendRow([
          TextCellValue(t.localId),
          TextCellValue(_fmtDate.format(t.createdAt)),
          TextCellValue(
              t.customerName ?? (t.customerId != null ? 'Pelanggan' : 'Umum')),
          IntCellValue(t.total),
          IntCellValue(t.paid),
          TextCellValue(_statusLabel(t.status)),
        ]);
      }

    case ReportTab.hutang:
      final debts = await db.getDebtBook();
      sheet.appendRow([
        TextCellValue('Pelanggan'),
        TextCellValue('Menunggak (hari)'),
        TextCellValue('Jumlah Nota'),
        TextCellValue('Jumlah Hutang'),
      ]);
      const cap = 5000;
      for (final e in debts.take(cap)) {
        sheet.appendRow([
          TextCellValue(e.name),
          IntCellValue(e.daysOverdue),
          IntCellValue(e.count),
          IntCellValue(e.debt),
        ]);
      }

    case ReportTab.stok:
      final s = await _fetchStok(db);
      sheet.appendRow([TextCellValue('Kategori'), TextCellValue('Nilai')]);
      for (final c in s.perCategory) {
        sheet.appendRow([TextCellValue(c.label), IntCellValue(c.value)]);
      }
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([TextCellValue('Total'), IntCellValue(s.grandTotal)]);
      if (s.negativeStock.isNotEmpty) {
        sheet.appendRow([TextCellValue('')]);
        sheet.appendRow(
            [TextCellValue('Stok Negatif'), TextCellValue('Stok')]);
        for (final r in s.negativeStock) {
          sheet.appendRow([TextCellValue(r.name), DoubleCellValue(r.stock)]);
        }
      }

    case ReportTab.pengeluaran:
      final byType = await db.getExpenseBreakdownByType(range.start, range.end);
      final daily = await db.getExpenseDailyTotals(range.start, range.end);
      sheet.appendRow([TextCellValue('Jenis'), TextCellValue('Nominal')]);
      for (final e in byType.entries) {
        sheet.appendRow(
            [TextCellValue(_expenseTypeLabel(e.key)), IntCellValue(e.value)]);
      }
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([TextCellValue('Tanggal'), TextCellValue('Nominal')]);
      for (final e in daily.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key))) {
        sheet.appendRow(
            [TextCellValue(_fmtDate.format(e.key)), IntCellValue(e.value)]);
      }

    case ReportTab.arusKas:
      final summary = await db.getCashFlowSummary(range.start, range.end);
      final daily = await db.getCashFlowDaily(range.start, range.end);
      sheet.appendRow([TextCellValue('Metrik'), TextCellValue('Nilai')]);
      sheet.appendRow([
        TextCellValue('Kas Masuk'),
        IntCellValue(summary.cashIn + summary.nonCashIn),
      ]);
      sheet.appendRow(
          [TextCellValue('Kas Keluar'), IntCellValue(summary.cashOut)]);
      sheet.appendRow([
        TextCellValue('Arus Kas Bersih'),
        IntCellValue(
            summary.cashIn + summary.nonCashIn - summary.cashOut),
      ]);
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow(
          [TextCellValue('Rincian Kas Masuk'), TextCellValue('')]);
      for (final e in summary.inByMethod.entries) {
        sheet.appendRow(
            [TextCellValue(_cashMethodLabel(e.key)), IntCellValue(e.value)]);
      }
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow(
          [TextCellValue('Rincian Kas Keluar'), TextCellValue('')]);
      for (final e in summary.outByType.entries) {
        sheet.appendRow(
            [TextCellValue(_expenseTypeLabel(e.key)), IntCellValue(e.value)]);
      }
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([
        TextCellValue('Tanggal'),
        TextCellValue('Masuk'),
        TextCellValue('Keluar'),
      ]);
      for (final d in daily) {
        sheet.appendRow([
          TextCellValue(_fmtDate.format(d.date)),
          IntCellValue(d.cashIn),
          IntCellValue(d.cashOut),
        ]);
      }
  }

  excel.delete('Sheet1');
  return Uint8List.fromList(excel.save()!);
}

// ─── Tangkapan widget → PNG (render off-screen lewat Overlay) ────────────────

Future<Uint8List?> _captureWidget(
  BuildContext context,
  Widget child, {
  required double width,
  double pixelRatio = 2.5,
}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  final boundaryKey = GlobalKey();

  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -99999,
      top: 0,
      child: Directionality(
        textDirection: ui.TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Theme(
            data: AppTheme.light(),
            // Material harus di dalam Theme agar DefaultTextStyle menggunakan
            // warna teks light-theme (gelap), bukan warna dari theme app yang
            // mungkin sedang dark-mode (teks putih → tidak terbaca di PDF).
            child: Material(
              color: Colors.white,
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(width: width, child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);

  try {
    // Tunggu layout + paint + animasi chart selesai.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await WidgetsBinding.instance.endOfFrame;
    final boundary = boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    entry.remove();
  }
}

// ─── PDF helper widgets ─────────────────────────────────────────────────────

pw.Widget _pdfSection(String title) => pw.Text(title,
    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13));

pw.Widget _pdfKpiGrid(List<(String, String)> items) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300),
    children: [
      for (var r = 0; r < items.length; r += 2)
        pw.TableRow(
          children: [
            _pdfKpiCell(items[r].$1, items[r].$2),
            if (r + 1 < items.length)
              _pdfKpiCell(items[r + 1].$1, items[r + 1].$2)
            else
              pw.Container(),
          ],
        ),
    ],
  );
}

pw.Widget _pdfKpiCell(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style:
                  const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        ],
      ),
    );

pw.Widget _pdfTable(
  List<String> headers,
  List<List<String>> rows, {
  List<pw.TextAlign>? aligns,
  List<double>? flex,
}) {
  pw.Widget cell(String text, {bool bold = false, pw.TextAlign? align}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontWeight: bold ? pw.FontWeight.bold : null, fontSize: 9),
            textAlign: align ?? pw.TextAlign.left),
      );

  final columnWidths = <int, pw.TableColumnWidth>{};
  if (flex != null) {
    for (var i = 0; i < flex.length; i++) {
      columnWidths[i] = pw.FlexColumnWidth(flex[i]);
    }
  }

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300),
    columnWidths: columnWidths,
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          for (var i = 0; i < headers.length; i++)
            cell(headers[i], bold: true, align: aligns?[i]),
        ],
      ),
      for (final row in rows)
        pw.TableRow(children: [
          for (var i = 0; i < row.length; i++) cell(row[i], align: aligns?[i]),
        ]),
    ],
  );
}

// ─── Data & helper ──────────────────────────────────────────────────────────

class _RingkasanData {
  _RingkasanData(this.revenue, this.cogs, this.txCount, this.profit,
      this.expenses, this.netProfit, this.byMethod, this.daily);
  final int revenue;
  final int cogs;
  final int txCount;
  /// Laba KOTOR (revenue - cogs) — BUKAN laba bersih, lihat [netProfit].
  final int profit;

  /// Item 47 (PLAN.md) — total pengeluaran P&L (subset
  /// `AppDatabase.netProfitExpenseTypes`), SAMA PERSIS sumbernya dgn kartu
  /// "Pengeluaran" di `ringkasan_tab.dart` (`getNetProfitExpenseTotal`).
  /// Sebelum ini, ekspor Ringkasan TIDAK PERNAH menyertakan field ini sama
  /// sekali (beda dari tampilan on-screen yg sudah benar) — grid KPI PDF &
  /// baris Excel cuma Omzet/Transaksi/HPP/Laba Kotor.
  final int expenses;

  /// Laba Bersih = Laba Kotor - [expenses], konsisten dgn on-screen.
  final int netProfit;
  final Map<String, int> byMethod;
  final Map<DateTime, int> daily;
}

Future<_RingkasanData> _fetchRingkasan(
    AppDatabase db, DateTimeRange range) async {
  // Perbaiki-sendiri ringkasan basi (transaksi hasil sync tak selalu merebuild
  // cache) supaya ekspor cermin transaksi nyata — lihat rebuildStaleSummaries.
  await db.rebuildStaleSummariesInRange(range.start, range.end);
  final summaries = await db.getDailySummaries(range.start, range.end);
  var revenue = 0, cogs = 0, txCount = 0;
  final byMethod = <String, int>{};
  final daily = <DateTime, int>{};
  for (final s in summaries) {
    revenue += s.omzet;
    cogs += s.hpp;
    txCount += s.jumlahTransaksi;
    if (s.pembayaranTunai > 0) {
      byMethod['tunai'] = (byMethod['tunai'] ?? 0) + s.pembayaranTunai;
    }
    if (s.pembayaranQris > 0) {
      byMethod['qris'] = (byMethod['qris'] ?? 0) + s.pembayaranQris;
    }
    if (s.pembayaranTransfer > 0) {
      byMethod['transfer'] = (byMethod['transfer'] ?? 0) + s.pembayaranTransfer;
    }
    if (s.pembayaranLainnya > 0) {
      byMethod['lainnya'] = (byMethod['lainnya'] ?? 0) + s.pembayaranLainnya;
    }
    final parts = s.date.split('-').map(int.parse).toList();
    daily[DateTime(parts[0], parts[1], parts[2])] = s.omzet;
  }
  final profit = revenue - cogs;
  final expenses = await db.getNetProfitExpenseTotal(range.start, range.end);
  return _RingkasanData(revenue, cogs, txCount, profit, expenses,
      profit - expenses, byMethod, daily);
}

/// Top 5 slice + sisa sebagai "Lainnya".
(List<_Slice>, int) _topSlices(List<(String, int)> all) {
  final slices = <_Slice>[];
  var other = 0;
  for (var i = 0; i < all.length; i++) {
    if (i < 5) {
      slices.add(_Slice(all[i].$1, all[i].$2));
    } else {
      other += all[i].$2;
    }
  }
  return (slices, other);
}

String _fmtQty(double q) => q % 1 == 0 ? q.toInt().toString() : q.toString();

String _statusLabel(String s) => switch (s) {
      'void' => 'Void',
      'kurang_bayar' => 'Kurang',
      'tempo' => 'Tempo',
      'lunas' => 'Lunas',
      _ => s,
    };

String _methodLabel(String m) => switch (m) {
      'tunai' => 'Tunai',
      'transfer' => 'Transfer Bank',
      'qris' => 'QRIS',
      'ewallet' => 'E-Wallet',
      'tempo' => 'Tempo',
      'lainnya' => 'Lainnya',
      _ => m,
    };

// Label kategori pengeluaran (enum `Expenses.type`) — DUPLIKAT sengaja dari
// `_expenseTypeLabels`/`pengaturan/expenses_screen.dart` (pola sama dgn
// `_methodLabel` di atas, yang juga terduplikasi antar-file utk kebutuhan
// map label kecil serupa).
const _expenseTypeLabels = {
  'daily_expense': 'Operasional',
  'owner_withdrawal': 'Ambil Pribadi (Owner)',
  'supplier_payment': 'Bayar Supplier',
  'change_given': 'Uang Keluar Laci',
};

String _expenseTypeLabel(String t) => _expenseTypeLabels[t] ?? t;

// Label metode arus kas — kunci di sini nilai MENTAH kolom
// `transaction_payments.method` ('bank', bukan 'transfer'), beda dari
// `_methodLabel` di atas (dipakai tab Ringkasan) — lihat dok `_methodLabels`
// di `arus_kas_tab.dart` soal kenapa keduanya sengaja berbeda.
const _cashMethodLabels = {
  'tunai': 'Tunai',
  'bank': 'Transfer',
  'qris': 'QRIS',
  'ewallet': 'E-Wallet',
  'retur': 'Retur (kembalian)',
  'edit': 'Koreksi item (kembalian)',
};

String _cashMethodLabel(String m) => _cashMethodLabels[m] ?? m;

/// Satu baris nilai per-kategori tab Stok — DUPLIKAT ringan dari
/// `_CategoryValue` privat di `stok_tab.dart` (tak bisa diimpor lintas file
/// krn privat, dan tab itu sendiri tak perlu tahu soal ekspor).
class _StokCategoryValue {
  _StokCategoryValue(this.label);
  final String label;
  int value = 0;
}

/// Replikasi agregasi `_stokTabProvider` (`stok_tab.dart`) dari baris mentah
/// `getInventoryRows()` — snapshot nilai inventori SEKARANG, bukan aktivitas
/// dalam rentang tanggal (lihat `_isSnapshotTab`).
Future<
    ({
      List<_StokCategoryValue> perCategory,
      int grandTotal,
      int missingCostCount,
      List<InventoryRow> negativeStock,
    })> _fetchStok(AppDatabase db) async {
  final rows = await db.getInventoryRows();
  final groups = await db.getAllProductGroups();
  final groupNameById = {
    for (final g in groups)
      if (g.name != null) g.id: g.name!,
  };

  final perCategory = <int?, _StokCategoryValue>{};
  var grandTotal = 0;
  var missingCostCount = 0;
  final negativeStock = <InventoryRow>[];

  for (final r in rows) {
    final value = (r.stock * r.costPrice).round();
    grandTotal += value;
    if (r.costPrice <= 0) missingCostCount++;
    if (r.stock < 0) negativeStock.add(r);

    final label = groupNameById[r.groupId] ?? 'Tanpa Kategori';
    perCategory.putIfAbsent(r.groupId, () => _StokCategoryValue(label)).value +=
        value;
  }

  final categoryList = perCategory.values.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  negativeStock.sort((a, b) => a.stock.compareTo(b.stock));

  return (
    perCategory: categoryList,
    grandTotal: grandTotal,
    missingCostCount: missingCostCount,
    negativeStock: negativeStock,
  );
}

Color _methodColor(String m, ColorScheme scheme) => switch (m) {
      'tunai' => scheme.primary,
      'qris' => scheme.secondary,
      'transfer' => scheme.tertiary,
      _ => scheme.surfaceContainerHighest,
    };

Color _methodOnColor(String m, ColorScheme scheme) => switch (m) {
      'tunai' => scheme.onPrimary,
      'qris' => scheme.onSecondary,
      'transfer' => scheme.onTertiary,
      _ => scheme.onSurfaceVariant,
    };

// ─── Salinan widget chart (identik dgn tab; animasi dimatikan utk capture) ───

class _Slice {
  const _Slice(this.label, this.value);
  final String label;
  final int value;
}

class _PaymentDonutChart extends StatelessWidget {
  const _PaymentDonutChart({required this.byMethod, required this.total});
  final Map<String, int> byMethod;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = byMethod.entries.toList();
    return SizedBox(
      height: 180,
      child: PieChart(
        PieChartData(
          centerSpaceRadius: 40,
          sectionsSpace: 2,
          sections: entries.map((e) {
            final pct = total > 0 ? (e.value / total * 100) : 0.0;
            return PieChartSectionData(
              value: e.value.toDouble(),
              color: _methodColor(e.key, scheme),
              title: '${pct.round()}%',
              radius: 50,
              titleStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _methodOnColor(e.key, scheme),
              ),
            );
          }).toList(),
        ),
        swapAnimationDuration: Duration.zero,
      ),
    );
  }
}

class _TopDonutChart extends StatelessWidget {
  const _TopDonutChart({required this.slices, required this.otherValue});
  final List<_Slice> slices;
  final int otherValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topColors = <Color>[
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.error,
      const Color(0xFF4C7DBF),
    ];
    final onTopColors = <Color>[
      scheme.onPrimary,
      scheme.onTertiary,
      scheme.onSecondary,
      scheme.onError,
      Colors.white,
    ];
    final otherColor = scheme.surfaceContainerHighest;
    final onOtherColor = scheme.onSurfaceVariant;

    final hasOther = otherValue > 0;
    final all = [
      ...slices,
      if (hasOther) _Slice('Lainnya', otherValue),
    ];
    final total = all.fold(0, (a, s) => a + s.value);

    bool isOther(int i) => hasOther && i == all.length - 1;
    Color colorFor(int i) =>
        isOther(i) ? otherColor : topColors[i % topColors.length];
    Color onColorFor(int i) =>
        isOther(i) ? onOtherColor : onTopColors[i % onTopColors.length];

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < all.length; i++) {
      final double pct = total > 0 ? all[i].value / total * 100 : 0;
      final small = pct < 8;
      sections.add(PieChartSectionData(
        value: all[i].value.toDouble(),
        color: colorFor(i),
        title: total > 0 ? '${pct.round()}%' : '',
        radius: 27,
        titlePositionPercentageOffset: small ? 1.4 : 0.5,
        titleStyle: TextStyle(
          fontSize: small ? 9 : 10.5,
          fontWeight: FontWeight.w700,
          color: small ? scheme.onSurface : onColorFor(i),
        ),
      ));
    }

    return Row(
      children: [
        SizedBox(
          width: 150,
          height: 150,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 30,
              sectionsSpace: 2,
              sections: sections,
            ),
            swapAnimationDuration: Duration.zero,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < all.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colorFor(i),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(all[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DailyBarChart extends StatelessWidget {
  const _DailyBarChart({required this.daily});
  final Map<DateTime, int> daily;

  @override
  Widget build(BuildContext context) {
    final sorted = daily.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final max = sorted.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;
    final total = sorted.length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: sorted.map((e) {
                final h = clampedBarHeight(e.value, max);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      height: h,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: sorted.asMap().entries.map((entry) {
              final i = entry.key;
              final date = entry.value.key;
              final bool show = total <= 7
                  ? true
                  : total <= 14
                      ? i % 2 == 0
                      : total <= 31
                          ? i % 3 == 0 || i == total - 1
                          : i % 7 == 0 || i == total - 1;
              return Expanded(
                child: Text(
                  show ? '${date.day}/${date.month}' : '',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.visible,
                  softWrap: false,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
