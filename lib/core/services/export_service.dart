import 'package:drift/drift.dart' hide Column;
import 'package:excel/excel.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../database/app_database.dart';

final _fmtRp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _fmtDate = DateFormat('dd/MM/yyyy');

class ExportService {
  ExportService._();

  // ─── PDF ────────────────────────────────────────────────────────────────

  static Future<void> exportPdf({
    required AppDatabase db,
    required DateTimeRange range,
    required String storeName,
  }) async {
    final data = await _fetchData(db, range);
    final doc = pw.Document();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(storeName.isEmpty ? 'Laporan' : storeName,
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                  'Periode: ${_fmtDate.format(range.start)} – ${_fmtDate.format(range.end)}',
                  style: const pw.TextStyle(fontSize: 11)),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        _buildKpiSection(data),
        pw.SizedBox(height: 16),
        _buildTransaksiTable(data.transactions),
        pw.SizedBox(height: 16),
        _buildProdukTable(data.topProducts),
      ],
    ));

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'laporan_${_fmtDate.format(range.start)}-${_fmtDate.format(range.end)}.pdf',
    );
  }

  static pw.Widget _buildKpiSection(_ReportData data) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _kpiCell('Total Penjualan', _fmtRp.format(data.totalRevenue)),
            _kpiCell('Jumlah Transaksi', data.txCount.toString()),
            _kpiCell('Laba Kotor', _fmtRp.format(data.grossProfit)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _kpiCell(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        children: [
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  static pw.Widget _buildTransaksiTable(List<_TxRow> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Transaksi', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        pw.SizedBox(height: 4),
        if (rows.isEmpty) pw.Text('Tidak ada data'),
        if (rows.isNotEmpty)
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.5),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: ['No', 'Tanggal', 'Customer', 'Total']
                    .map((h) => _cell(h, bold: true))
                    .toList(),
              ),
              ...rows.map((r) => pw.TableRow(children: [
                    _cell(r.localId),
                    _cell(_fmtDate.format(r.createdAt)),
                    _cell(r.customerLabel),
                    _cell(_fmtRp.format(r.total), align: pw.TextAlign.right),
                  ])),
            ],
          ),
      ],
    );
  }

  static pw.Widget _buildProdukTable(List<_ProductRow> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Produk Terlaris', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        pw.SizedBox(height: 4),
        if (rows.isEmpty) pw.Text('Tidak ada data'),
        if (rows.isNotEmpty)
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: ['Produk', 'Qty', 'Omzet']
                    .map((h) => _cell(h, bold: true))
                    .toList(),
              ),
              ...rows.map((r) => pw.TableRow(children: [
                    _cell(r.name),
                    _cell(r.totalQty.toString()),
                    _cell(_fmtRp.format(r.totalRevenue), align: pw.TextAlign.right),
                  ])),
            ],
          ),
      ],
    );
  }

  static pw.Widget _cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(text,
          style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : null, fontSize: 9),
          textAlign: align),
    );
  }

  // ─── XLSX ────────────────────────────────────────────────────────────────

  static Future<Uint8List> exportXlsx({
    required AppDatabase db,
    required DateTimeRange range,
  }) async {
    final data = await _fetchData(db, range);
    final excel = Excel.createExcel();

    // Ringkasan sheet
    {
      final sheet = excel['Ringkasan'];
      sheet.appendRow([TextCellValue('Metrik'), TextCellValue('Nilai')]);
      sheet.appendRow([TextCellValue('Total Penjualan'), IntCellValue(data.totalRevenue)]);
      sheet.appendRow([TextCellValue('Jumlah Transaksi'), IntCellValue(data.txCount)]);
      sheet.appendRow([TextCellValue('COGS'), IntCellValue(data.totalCogs)]);
      sheet.appendRow([TextCellValue('Laba Kotor'), IntCellValue(data.grossProfit)]);
    }

    // Transaksi sheet
    {
      final sheet = excel['Transaksi'];
      sheet.appendRow([
        TextCellValue('No'), TextCellValue('Tanggal'), TextCellValue('Customer'),
        TextCellValue('Total'), TextCellValue('Bayar'), TextCellValue('Status'),
      ]);
      for (final r in data.transactions) {
        sheet.appendRow([
          TextCellValue(r.localId),
          TextCellValue(_fmtDate.format(r.createdAt)),
          TextCellValue(r.customerLabel),
          IntCellValue(r.total),
          IntCellValue(r.paid),
          TextCellValue(r.status),
        ]);
      }
    }

    // Produk sheet
    {
      final sheet = excel['Produk'];
      sheet.appendRow([
        TextCellValue('Produk'), TextCellValue('Total Qty'), TextCellValue('Total Omzet'),
      ]);
      for (final r in data.topProducts) {
        sheet.appendRow([
          TextCellValue(r.name),
          DoubleCellValue(r.totalQty),
          IntCellValue(r.totalRevenue),
        ]);
      }
    }

    // Pelanggan sheet
    {
      final sheet = excel['Pelanggan'];
      sheet.appendRow([
        TextCellValue('Customer'), TextCellValue('Jumlah Transaksi'), TextCellValue('Total Belanja'),
      ]);
      for (final r in data.customers) {
        sheet.appendRow([
          TextCellValue(r.name),
          IntCellValue(r.txCount),
          IntCellValue(r.totalSpend),
        ]);
      }
    }

    // Remove default sheet
    excel.delete('Sheet1');
    return Uint8List.fromList(excel.save()!);
  }

  // ─── Data fetching ────────────────────────────────────────────────────────

  static Future<_ReportData> _fetchData(AppDatabase db, DateTimeRange range) async {
    final txs = await (db.select(db.transactions)
          ..where((t) =>
              t.status.isNotValue('void') &
              t.createdAt.isBiggerOrEqualValue(range.start) &
              t.createdAt.isSmallerOrEqualValue(range.end))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();

    int totalRevenue = 0;
    int totalCogs = 0;

    final txRows = <_TxRow>[];
    for (final tx in txs) {
      totalRevenue += tx.total;
      txRows.add(_TxRow(
        localId: tx.localId,
        createdAt: tx.createdAt,
        customerLabel: tx.customerId != null
            ? 'Pelanggan'
            : tx.customerName ?? 'Umum',
        total: tx.total,
        paid: tx.paid,
        status: tx.status,
      ));
    }

    // Aggregate products
    final Map<String, _ProductAgg> prodAgg = {};
    for (final tx in txs) {
      final items = await (db.select(db.transactionItems)
            ..where((t) => t.transactionId.equals(tx.id)))
          .get();
      for (final item in items) {
        totalCogs += (item.costAtSale * item.qty).round();
        prodAgg.update(
          item.productId,
          (p) => p.copyWith(
            totalQty: p.totalQty + item.qty,
            totalRevenue: p.totalRevenue + item.subtotal,
          ),
          ifAbsent: () => _ProductAgg(
            productId: item.productId,
            totalQty: item.qty,
            totalRevenue: item.subtotal,
          ),
        );
      }
    }

    // Resolve product names
    final productRows = <_ProductRow>[];
    for (final agg in prodAgg.entries) {
      final p = await (db.select(db.products)
            ..where((t) => t.id.equals(agg.key)))
          .getSingleOrNull();
      productRows.add(_ProductRow(
        name: p?.name ?? agg.key,
        totalQty: agg.value.totalQty,
        totalRevenue: agg.value.totalRevenue,
      ));
    }
    productRows.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

    // Aggregate customers
    final Map<String, _CustAgg> custAgg = {};
    for (final tx in txs) {
      if (tx.customerId == null) continue;
      custAgg.update(
        tx.customerId!,
        (c) => c.copyWith(txCount: c.txCount + 1, totalSpend: c.totalSpend + tx.total),
        ifAbsent: () => _CustAgg(customerId: tx.customerId!, txCount: 1, totalSpend: tx.total),
      );
    }
    final custRows = <_CustRow>[];
    for (final agg in custAgg.entries) {
      final c = await (db.select(db.customers)
            ..where((t) => t.id.equals(agg.key)))
          .getSingleOrNull();
      custRows.add(_CustRow(
        name: c?.name ?? agg.key,
        txCount: agg.value.txCount,
        totalSpend: agg.value.totalSpend,
      ));
    }
    custRows.sort((a, b) => b.totalSpend.compareTo(a.totalSpend));

    return _ReportData(
      totalRevenue: totalRevenue,
      txCount: txs.length,
      totalCogs: totalCogs,
      grossProfit: totalRevenue - totalCogs,
      transactions: txRows,
      topProducts: productRows,
      customers: custRows,
    );
  }
}

class _ReportData {
  const _ReportData({
    required this.totalRevenue,
    required this.txCount,
    required this.totalCogs,
    required this.grossProfit,
    required this.transactions,
    required this.topProducts,
    required this.customers,
  });
  final int totalRevenue;
  final int txCount;
  final int totalCogs;
  final int grossProfit;
  final List<_TxRow> transactions;
  final List<_ProductRow> topProducts;
  final List<_CustRow> customers;
}

class _TxRow {
  const _TxRow({
    required this.localId,
    required this.createdAt,
    required this.customerLabel,
    required this.total,
    required this.paid,
    required this.status,
  });
  final String localId;
  final DateTime createdAt;
  final String customerLabel;
  final int total;
  final int paid;
  final String status;
}

class _ProductAgg {
  const _ProductAgg({required this.productId, required this.totalQty, required this.totalRevenue});
  final String productId;
  final double totalQty;
  final int totalRevenue;
  _ProductAgg copyWith({double? totalQty, int? totalRevenue}) => _ProductAgg(
      productId: productId, totalQty: totalQty ?? this.totalQty, totalRevenue: totalRevenue ?? this.totalRevenue);
}

class _ProductRow {
  const _ProductRow({required this.name, required this.totalQty, required this.totalRevenue});
  final String name;
  final double totalQty;
  final int totalRevenue;
}

class _CustAgg {
  const _CustAgg({required this.customerId, required this.txCount, required this.totalSpend});
  final String customerId;
  final int txCount;
  final int totalSpend;
  _CustAgg copyWith({int? txCount, int? totalSpend}) => _CustAgg(
      customerId: customerId, txCount: txCount ?? this.txCount, totalSpend: totalSpend ?? this.totalSpend);
}

class _CustRow {
  const _CustRow({required this.name, required this.txCount, required this.totalSpend});
  final String name;
  final int txCount;
  final int totalSpend;
}
