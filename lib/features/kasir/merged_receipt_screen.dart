import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/services/printer_service.dart';
import '../../core/theme/app_theme.dart';
import 'receipt_screen.dart' show netPaidDisplay, netRemainingOwed;

/// Struk gabungan beberapa nota (gabung nota). Tampilan murni baca: item
/// ditampilkan terpisah per nota, dengan total akumulatif di bawah. Bisa
/// dicetak ke printer thermal maupun dibagikan sebagai gambar.
class MergedReceiptScreen extends ConsumerStatefulWidget {
  const MergedReceiptScreen({super.key, required this.txIds});
  final List<String> txIds;

  @override
  ConsumerState<MergedReceiptScreen> createState() =>
      _MergedReceiptScreenState();
}

class _MergedReceiptScreenState extends ConsumerState<MergedReceiptScreen> {
  bool _loading = true;
  List<Transaction> _txs = [];
  Map<String, List<TransactionItem>> _itemsByTx = {};
  Map<String, List<TransactionPayment>> _paymentsByTx = {};
  Map<String, String> _productNames = {};
  Map<String, String> _unitNames = {};
  Map<String, String?> _parentOf = {};
  String _customerName = 'Umum';
  String _customerAddress = '';
  bool _showEmployee = true;
  DateTime? _lastPaymentAt; // waktu pelunasan terakhir lintas nota

  String _storeName = '';
  String _storeAddress = '';
  String _storePhone = '';
  String _storeWhatsapp = '';
  String _storeTelegram = '';
  String _receiptHeader = '';

  final GlobalKey _boundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);

    final txs = await (db.select(db.transactions)
          ..where((t) => t.id.isIn(widget.txIds))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();

    final itemsByTx = <String, List<TransactionItem>>{};
    final productNames = <String, String>{};
    final unitNames = <String, String>{};
    final parentOf = <String, String?>{};
    for (final tx in txs) {
      final items = await (db.select(db.transactionItems)
            ..where((t) => t.transactionId.equals(tx.id)))
          .get();
      itemsByTx[tx.id] = items;
      for (final item in items) {
        if (!productNames.containsKey(item.productId)) {
          final p = await (db.select(db.products)
                ..where((t) => t.id.equals(item.productId)))
              .getSingleOrNull();
          productNames[item.productId] = p?.name ?? item.productId;
          parentOf[item.productId] = p?.parentProductId;
        }
        if (!unitNames.containsKey(item.productUnitId)) {
          final u = await (db.select(db.productUnits)
                ..where((t) => t.id.equals(item.productUnitId)))
              .getSingleOrNull();
          if (u?.unitTypeId != null) {
            final ut = await (db.select(db.unitTypes)
                  ..where((t) => t.id.equals(u!.unitTypeId!)))
                .getSingleOrNull();
            unitNames[item.productUnitId] = ut?.name ?? '';
          }
        }
      }
    }

    // Waktu pelunasan terakhir (lintas nota) untuk dicantumkan di struk.
    final paymentsByTx = await db.getPaymentsForTxs(widget.txIds);
    DateTime? lastPaymentAt;
    for (final list in paymentsByTx.values) {
      for (final p in list) {
        final cur = lastPaymentAt;
        if (cur == null || p.paidAt.isAfter(cur)) {
          lastPaymentAt = p.paidAt;
        }
      }
    }

    // Nama pelanggan: terdaftar → nama customer; selain itu "Umum".
    var customerName = 'Umum';
    var customerAddress = '';
    final first = txs.isNotEmpty ? txs.first : null;
    if (first?.customerId != null) {
      final c = await (db.select(db.customers)
            ..where((t) => t.id.equals(first!.customerId!)))
          .getSingleOrNull();
      if (c != null) {
        customerName = c.name;
        customerAddress = c.address?.trim() ?? '';
      }
    }

    final storeName = await db.getSetting('store_name') ?? device.storeName;
    final storeAddress = await db.getSetting('store_address') ?? '';
    final storePhone = await db.getSetting('store_phone') ?? '';
    final storeWhatsapp = await db.getSetting('store_whatsapp') ?? '';
    final storeTelegram = await db.getSetting('store_telegram') ?? '';
    final receiptHeader = await db.getSetting('receipt_header') ?? '';
    final showEmp = await db.getSetting('receipt_show_employee');

    if (mounted) {
      setState(() {
        _txs = txs;
        _itemsByTx = itemsByTx;
        _paymentsByTx = paymentsByTx;
        _productNames = productNames;
        _unitNames = unitNames;
        _parentOf = parentOf;
        _customerName = customerName;
        _customerAddress = customerAddress;
        _showEmployee = showEmp == null || showEmp == '1';
        _lastPaymentAt = lastPaymentAt;
        _storeName = storeName.isNotEmpty ? storeName : device.storeName;
        _storeAddress = storeAddress;
        _storePhone = storePhone;
        _storeWhatsapp = storeWhatsapp;
        _storeTelegram = storeTelegram;
        _receiptHeader = receiptHeader;
        _loading = false;
      });
    }
  }

  int get _grandTotal => _txs.fold(0, (s, t) => s + t.total);

  /// Terbayar NET (dikurangi kembalian per nota, sama pola dengan
  /// `netPaidDisplay` di receipt_screen.dart) — BUKAN `Σ tx.paid` mentah,
  /// yang bisa menghitung dobel kembalian yang dipakai ulang sbg pembayaran
  /// baru (akar masalah Item 23, sebelumnya belum ikut diperbaiki di sini).
  int get _grandPaid => _txs.fold(
      0, (s, t) => s + netPaidDisplay(t, _paymentsByTx[t.id] ?? const []));

  /// Sisa NET, dijumlah per nota (masing-masing sudah di-clamp ≥0) — supaya
  /// TOTAL = Terbayar + Sisa tetap konsisten & tidak pernah muncul angka
  /// negatif yang membingungkan ("SISA Rp -31.400").
  int get _grandSisa => _txs.fold(
      0, (s, t) => s + netRemainingOwed(t, _paymentsByTx[t.id] ?? const []));

  /// Pembayaran (bukan dibatalkan) paling baru lintas semua nota yang
  /// menghasilkan kembalian — Item 9, dipakai baris "Uang Diterima" (gross,
  /// uang tender asli sebelum dikurangi kembalian).
  TransactionPayment? get _latestPaymentWithChange {
    TransactionPayment? latest;
    for (final list in _paymentsByTx.values) {
      for (final p in list) {
        if (p.voided || p.changeGiven <= 0) continue;
        if (latest == null || p.paidAt.isAfter(latest.paidAt)) latest = p;
      }
    }
    return latest;
  }

  Future<void> _print() async {
    final mac = await PrinterService.getSavedMac();
    if (mac == null || mac.isEmpty) {
      if (!mounted) return;
      AppTheme.showSnack(context, 'Printer belum dikonfigurasi', isError: true);
      return;
    }
    final granted = await PrinterService.ensurePermissions();
    if (!granted) {
      if (!mounted) return;
      AppTheme.showSnack(context, 'Izin Bluetooth ditolak', isError: true);
      return;
    }
    final ok = await PrinterService.printMergedReceipt(
      txs: _txs,
      itemsByTx: _itemsByTx,
      paymentsByTx: _paymentsByTx,
      productNames: _productNames,
      unitNames: _unitNames,
      customerName: _customerName,
      customerAddress: _customerAddress,
      showEmployee: _showEmployee,
      storeName: _storeName,
      storeAddress: _storeAddress,
      storePhone: _storePhone,
      storeWhatsapp: _storeWhatsapp,
      storeTelegram: _storeTelegram,
      receiptHeader: _receiptHeader,
      parentOf: _parentOf,
      lastPaymentAt: _lastPaymentAt,
    );
    if (!mounted) return;
    AppTheme.showSnack(
        context, ok ? 'Struk gabungan dicetak' : 'Gagal mencetak',
        isError: !ok);
  }

  Future<void> _share() async {
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final dir = await getTemporaryDirectory();
      final ids = _txs.map((t) => t.localId).join('_');
      final file = File('${dir.path}/struk_gabungan_$ids.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Struk Gabungan',
      );
    } catch (e) {
      if (mounted) {
        AppTheme.showSnack(context, 'Gagal membagikan: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Struk Gabungan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Bagikan',
            onPressed: _share,
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Cetak',
            onPressed: _print,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Material(
              elevation: 1,
              child: RepaintBoundary(
                key: _boundaryKey,
                child: _MergedReceiptPaper(
                  txs: _txs,
                  itemsByTx: _itemsByTx,
                  paymentsByTx: _paymentsByTx,
                  productNames: _productNames,
                  unitNames: _unitNames,
                  parentOf: _parentOf,
                  customerName: _customerName,
                  customerAddress: _customerAddress,
                  showEmployee: _showEmployee,
                  storeName: _storeName,
                  storeAddress: _storeAddress,
                  storePhone: _storePhone,
                  storeWhatsapp: _storeWhatsapp,
                  storeTelegram: _storeTelegram,
                  receiptHeader: _receiptHeader,
                  grandTotal: _grandTotal,
                  grandPaid: _grandPaid,
                  grandSisa: _grandSisa,
                  latestPaymentWithChange: _latestPaymentWithChange,
                  lastPaymentAt: _lastPaymentAt,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// Tampilan kertas struk gabungan (putih, monospace) untuk di-capture.
class _MergedReceiptPaper extends StatelessWidget {
  const _MergedReceiptPaper({
    required this.txs,
    required this.itemsByTx,
    required this.paymentsByTx,
    required this.productNames,
    required this.unitNames,
    required this.parentOf,
    required this.customerName,
    this.customerAddress = '',
    this.showEmployee = true,
    required this.storeName,
    required this.storeAddress,
    required this.storePhone,
    required this.storeWhatsapp,
    required this.storeTelegram,
    required this.receiptHeader,
    required this.grandTotal,
    required this.grandPaid,
    required this.grandSisa,
    required this.latestPaymentWithChange,
    required this.lastPaymentAt,
  });

  final List<Transaction> txs;
  final Map<String, List<TransactionItem>> itemsByTx;
  final Map<String, List<TransactionPayment>> paymentsByTx;
  final Map<String, String> productNames;
  final Map<String, String> unitNames;
  final Map<String, String?> parentOf;
  final String customerName;
  final String customerAddress;
  final bool showEmployee;
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String storeWhatsapp;
  final String storeTelegram;
  final String receiptHeader;
  final int grandTotal;
  final int grandPaid;
  final int grandSisa;
  final TransactionPayment? latestPaymentWithChange;
  final DateTime? lastPaymentAt;

  static const _ink = Color(0xFF111111);
  // Item 7 — pin font eksplisit, sama alasan dgn receipt_screen.dart
  // (fontFamily: 'monospace' generik resolve beda-beda per device).
  static TextStyle get _mono =>
      GoogleFonts.robotoMono(fontSize: 12, color: _ink, height: 1.4);

  TransactionItem? _parentItemOf(
      TransactionItem item, List<TransactionItem> items) {
    final pid = parentOf[item.productId];
    if (pid == null) return null;
    for (final it in items) {
      if (it.productId == pid && parentOf[it.productId] == null) return it;
    }
    return null;
  }

  List<TransactionItem> _ordered(List<TransactionItem> items) {
    final out = <TransactionItem>[];
    for (final it in items) {
      if (_parentItemOf(it, items) == null) {
        out.add(it);
        for (final c in items) {
          if (_parentItemOf(c, items)?.id == it.id) out.add(c);
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(storeName.toUpperCase(),
              textAlign: TextAlign.center,
              style: _mono.copyWith(fontSize: 16, fontWeight: FontWeight.w900)),
          if (storeAddress.isNotEmpty)
            Text(storeAddress,
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          if (storePhone.isNotEmpty)
            Text('Telp: $storePhone',
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          if (storeWhatsapp.isNotEmpty)
            Text('WA: $storeWhatsapp',
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          if (storeTelegram.isNotEmpty)
            Text('Telegram: $storeTelegram',
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          if (receiptHeader.isNotEmpty)
            Text(receiptHeader,
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          const _DashedLine(),
          Text(customerName,
              textAlign: TextAlign.center,
              style: _mono.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
          if (customerAddress.isNotEmpty)
            Text(customerAddress,
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),

          // ── Per nota (terpisah) ──────────────────────────────────────────
          ...txs.expand((tx) {
            final items = itemsByTx[tx.id] ?? const <TransactionItem>[];
            // NET (dikurangi kembalian, sudah di-clamp ≥0) — bukan
            // `tx.total - tx.paid` mentah, yang bisa jadi negatif/understate
            // kalau kembalian dipakai ulang sbg pembayaran (Item 23).
            final sisa = netRemainingOwed(tx, paymentsByTx[tx.id] ?? const []);
            final date = _fmtDateTime(tx.createdAt);
            final empName =
                (showEmployee ? tx.employeeName?.trim() : null) ?? '';
            return [
              const _DashedLine(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('#${shortTxNo(tx.localId)}',
                      style: _mono),
                  Text(date, style: _mono),
                ],
              ),
              // Pegawai di bawah id nota. "Pegawai: " normal, nama bold.
              if (empName.isNotEmpty)
                Text.rich(
                  TextSpan(
                    style: _mono,
                    children: [
                      const TextSpan(text: 'Pegawai: '),
                      TextSpan(
                          text: empName,
                          style: _mono.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              // Spasi antara header (id / pegawai) dan produk pertama.
              const SizedBox(height: 6),
              ..._ordered(items).map((item) {
                final isVar = _parentItemOf(item, items) != null;
                final pad = isVar ? '  ' : '';
                final namePrefix = isVar ? '$pad└ ' : '';
                final qtyStr = item.qty % 1 == 0
                    ? item.qty.toInt().toString()
                    : item.qty.toString();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('$namePrefix${productNames[item.productId] ?? ''}',
                        style: _mono.copyWith(
                            fontWeight:
                                isVar ? FontWeight.w400 : FontWeight.w700)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            '$pad$qtyStr ${unitNames[item.productUnitId] ?? ''} x ${_fmtNum(item.priceAtSale)}',
                            style: _mono),
                        Text(_fmtNum(item.subtotal), style: _mono),
                      ],
                    ),
                  ],
                );
              }),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Subtotal nota', style: _mono),
                  Text('Rp ${_fmtNum(tx.total)}',
                      style: _mono.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              if (sisa > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('  Sisa', style: _mono),
                    Text('Rp ${_fmtNum(sisa)}', style: _mono),
                  ],
                ),
            ];
          }),

          // ── Total akumulatif ─────────────────────────────────────────────
          const _DashedLine(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL TAGIHAN',
                  style: _mono.copyWith(
                      fontSize: 14, fontWeight: FontWeight.w900)),
              Text('Rp ${_fmtNum(grandTotal)}',
                  style: _mono.copyWith(
                      fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Terbayar', style: _mono),
              Text('Rp ${_fmtNum(grandPaid)}', style: _mono),
            ],
          ),
          // Item 9 — uang tender ASLI (gross) dari pembayaran terakhir yang
          // menghasilkan kembalian, supaya tidak membingungkan pembeli yang
          // kasih lebih dari tagihan gabungan.
          if (latestPaymentWithChange != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Uang Diterima', style: _mono),
                Text('Rp ${_fmtNum(latestPaymentWithChange!.amount)}',
                    style: _mono),
              ],
            ),
          if (latestPaymentWithChange != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Kembalian', style: _mono),
                Text('Rp ${_fmtNum(latestPaymentWithChange!.changeGiven)}',
                    style: _mono),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('SISA',
                  style: _mono.copyWith(
                      fontSize: 14, fontWeight: FontWeight.w900)),
              Text('Rp ${_fmtNum(grandSisa)}',
                  style: _mono.copyWith(
                      fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
          if (lastPaymentAt != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text('Pelunasan: ${_fmtDateTime(lastPaymentAt!)}',
                  style: _mono.copyWith(fontSize: 11)),
            ),
          const _DashedLine(),
          Text('Terima kasih!',
              textAlign: TextAlign.center,
              style: _mono.copyWith(fontSize: 11)),
        ],
      ),
    );
  }

  String _fmtDateTime(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _fmtNum(int v) {
    final neg = v < 0;
    final s = v.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return neg ? '-$buf' : buf.toString();
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final count = (constraints.maxWidth / 7).floor();
          return Text(
            List.filled(count, '-').join(),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: GoogleFonts.robotoMono(
                fontSize: 12, color: const Color(0xFF777777)),
          );
        },
      ),
    );
  }
}
