import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';

// Ekspor laporan PER KATEGORI (tab). Setiap tab punya PDF & XLSX sendiri.
// Grafik di PDF = tangkapan widget chart asli aplikasi (identik tampilannya).
// Pengiriman lewat FilePicker.saveFile (bukan Printing.sharePdf) agar tidak
// merasterisasi seluruh halaman → menghindari Out of Memory & gagal diam.

enum ReportTab { ringkasan, produk, pelanggan, transaksi }

final _fmtRp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _fmtDate = DateFormat('dd/MM/yyyy');
final _fmtDateFile = DateFormat('yyyyMMdd');

String _tabLabel(ReportTab t) => switch (t) {
      ReportTab.ringkasan => 'Ringkasan',
      ReportTab.produk => 'Produk',
      ReportTab.pelanggan => 'Pelanggan',
      ReportTab.transaksi => 'Transaksi',
    };

// ─── Orkestrator ekspor ────────────────────────────────────────────────────

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
    final Uint8List bytes;
    if (format == 'pdf') {
      bytes = await _buildPdf(context, db, range, tab, storeName);
    } else {
      bytes = await _buildXlsx(db, range, tab);
    }
    if (!context.mounted) return;
    final ext = format == 'pdf' ? 'pdf' : 'xlsx';
    final fname = 'laporan_${_tabLabel(tab).toLowerCase()}_'
        '${_fmtDateFile.format(range.start)}-${_fmtDateFile.format(range.end)}.$ext';
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
              'Laporan ${_tabLabel(tab)} · ${_fmtDate.format(range.start)} – '
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
      child: Material(
        color: Colors.white,
        child: Directionality(
          textDirection: ui.TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Theme(
              data: AppTheme.light(),
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
      this.byMethod, this.daily);
  final int revenue;
  final int cogs;
  final int txCount;
  final int profit;
  final Map<String, int> byMethod;
  final Map<DateTime, int> daily;
}

Future<_RingkasanData> _fetchRingkasan(
    AppDatabase db, DateTimeRange range) async {
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
  return _RingkasanData(
      revenue, cogs, txCount, revenue - cogs, byMethod, daily);
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
                final h = max > 0 ? (e.value / max * 70) : 2.0;
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
