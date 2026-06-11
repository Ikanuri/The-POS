import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/services/printer_service.dart';
import '../../core/theme/app_theme.dart';

const _receiptUuid = Uuid();

class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key, required this.transactionId});
  final String transactionId;

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  Transaction? _tx;
  List<TransactionItem> _items = [];
  Map<String, String> _productNames = {};
  Map<String, String> _unitNames = {};
  Customer? _customer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(widget.transactionId)))
        .getSingleOrNull();
    if (tx == null || !mounted) {
      setState(() => _loading = false);
      return;
    }
    final items = await (db.select(db.transactionItems)
          ..where((t) => t.transactionId.equals(widget.transactionId)))
        .get();

    Customer? customer;
    if (tx.customerId != null) {
      customer = await (db.select(db.customers)
            ..where((t) => t.id.equals(tx.customerId!)))
          .getSingleOrNull();
    }

    // Load product + unit names
    final productNames = <String, String>{};
    final unitNames = <String, String>{};
    for (final item in items) {
      if (!productNames.containsKey(item.productId)) {
        final p = await (db.select(db.products)
              ..where((t) => t.id.equals(item.productId)))
            .getSingleOrNull();
        productNames[item.productId] = p?.name ?? item.productId;
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

    if (mounted) {
      setState(() {
        _tx = tx;
        _items = items;
        _productNames = productNames;
        _unitNames = unitNames;
        _customer = customer;
        _loading = false;
      });
    }
  }

  String _customerDisplay(Transaction tx) {
    if (_customer != null) return _customer!.name;
    if (tx.customerName != null) return tx.customerName!;
    return 'Umum';
  }

  String _methodLabel(String method) => switch (method) {
        'tunai' => 'Tunai',
        'transfer' => 'Transfer',
        'qris' => 'QRIS',
        'ewallet' => 'E-Wallet',
        'tempo' => 'Tempo',
        _ => method,
      };

  Future<void> _showTambahBayar(BuildContext context) async {
    final ctrl = TextEditingController();
    final remaining = _tx!.total - _tx!.paid;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Bayar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sisa tagihan: ${formatRupiah(remaining)}'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(prefixText: 'Rp ', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => ctx.pop(), child: const Text('Batal')),
          FilledButton(
            onPressed: () => ctx.pop(int.tryParse(ctrl.text)),
            child: const Text('Bayar'),
          ),
        ],
      ),
    );

    if (result != null && result > 0 && mounted) {
      final db = ref.read(databaseProvider);
      final device = ref.read(deviceProvider);
      final now = DateTime.now();
      await db.into(db.transactionPayments).insert(
            TransactionPaymentsCompanion.insert(
              id: _receiptUuid.v4(),
              transactionId: widget.transactionId,
              amount: result,
              method: 'tunai',
              paidAt: Value(now),
              kasirId: Value(device.deviceCode),
            ),
          );

      final tx = _tx!;
      final newPaid = tx.paid + result;
      final newStatus = newPaid >= tx.total ? 'lunas' : 'kurang_bayar';
      await (db.update(db.transactions)
            ..where((t) => t.id.equals(widget.transactionId)))
          .write(TransactionsCompanion(
        paid: Value(newPaid),
        status: Value(newStatus),
      ));
      await _load();
    }
  }

  Future<void> _printReceipt() async {
    final mac = await PrinterService.getSavedMac();
    if (mac == null || mac.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Printer belum dikonfigurasi'),
          action: SnackBarAction(
            label: 'Pengaturan',
            onPressed: () {},
          ),
        ),
      );
      return;
    }
    final prefs = await _getStorePrefs();
    final ok = await PrinterService.printReceipt(
      tx: _tx!,
      items: _items,
      productNames: _productNames,
      unitNames: _unitNames,
      customer: _customer,
      storeName: prefs.$1,
      storeAddress: prefs.$2,
      storePhone: prefs.$3,
      strukNote: _tx!.strukNote,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Struk berhasil dicetak' : 'Gagal mencetak struk'),
      backgroundColor: ok ? null : Theme.of(context).colorScheme.error,
    ));
  }

  Future<(String, String, String)> _getStorePrefs() async {
    final db = ref.read(databaseProvider);
    final name = await db.getSetting('store_name') ?? '';
    final address = await db.getSetting('store_address') ?? '';
    final phone = await db.getSetting('store_phone') ?? '';
    return (name, address, phone);
  }

  Future<void> _showShareSheet() async {
    final prefs = await _getStorePrefs();
    final device = ref.read(deviceProvider);
    if (!mounted) return;

    final boundaryKey = GlobalKey();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Bagikan Struk',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: _ReceiptPaper(
                      tx: _tx!,
                      items: _items,
                      productNames: _productNames,
                      unitNames: _unitNames,
                      customerName: _customerDisplay(_tx!),
                      storeName: prefs.$1.isNotEmpty
                          ? prefs.$1
                          : device.storeName,
                      storeAddress: prefs.$2,
                      storePhone: prefs.$3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _captureAndShare(ctx, boundaryKey),
                icon: const Icon(Icons.share),
                label: const Text('Bagikan Gambar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _captureAndShare(
      BuildContext sheetCtx, GlobalKey boundaryKey) async {
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/struk_${_tx!.localId}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Struk ${_tx!.localId}',
      );
      if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
    } catch (e) {
      if (sheetCtx.mounted) {
        ScaffoldMessenger.of(sheetCtx).showSnackBar(
          SnackBar(content: Text('Gagal membagikan: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(deviceProvider);
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_tx == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Struk')),
        body: const Center(child: Text('Transaksi tidak ditemukan')),
      );
    }

    final tx = _tx!;
    final isKurangBayar =
        tx.status == 'kurang_bayar' || tx.status == 'tempo';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Struk'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/kasir'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Bagikan Struk',
            onPressed: _tx == null ? null : () => _showShareSheet(),
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Cetak Struk',
            onPressed: _tx == null ? null : () => _printReceipt(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isKurangBayar
                  ? scheme.errorContainer
                  : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  isKurangBayar
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: isKurangBayar
                      ? scheme.onErrorContainer
                      : scheme.onPrimaryContainer,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isKurangBayar
                          ? (tx.status == 'tempo'
                              ? 'Transaksi Tempo'
                              : 'Kurang Bayar')
                          : 'Transaksi Berhasil',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: isKurangBayar
                                    ? scheme.onErrorContainer
                                    : scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    Text(
                      tx.localId,
                      style: TextStyle(
                        fontSize: 12,
                        color: (isKurangBayar
                                ? scheme.onErrorContainer
                                : scheme.onPrimaryContainer)
                            .withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Store & customer info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        device.storeName,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        _formatDateTime(tx.createdAt),
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('Kasir: ${device.deviceName}',
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 12),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Pelanggan: ',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant),
                            ),
                            TextSpan(
                              text: _customerDisplay(tx),
                              style: TextStyle(
                                fontSize: 12,
                                color: _customer != null
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                fontWeight: _customer != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontStyle: (_customer == null &&
                                        tx.customerName == null)
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Items
          Card(
            child: Column(
              children: [
                ..._items.map((item) => ListTile(
                      dense: true,
                      title: Text(
                        _productNames[item.productId] ?? item.productId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: item.itemNote != null
                          ? Text(item.itemNote!,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic))
                          : null,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_unitNames[item.productUnitId] ?? ''} ${item.qty % 1 == 0 ? item.qty.toInt() : item.qty} × ${formatRupiah(item.priceAtSale)}',
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant),
                          ),
                          Text(
                            formatRupiah(item.subtotal),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _SummaryRow('Total', formatRupiah(tx.total),
                          bold: true, color: scheme.primary),
                      if (tx.paid > 0)
                        _SummaryRow('Dibayar',
                            '${_methodLabel(tx.paymentMethod)} · ${formatRupiah(tx.paid)}'),
                      if (tx.changeAmount > 0)
                        _SummaryRow(
                            'Kembalian', formatRupiah(tx.changeAmount),
                            color: scheme.tertiary),
                      if (isKurangBayar)
                        _SummaryRow(
                          'Sisa Tagihan',
                          formatRupiah(tx.total - tx.paid),
                          color: scheme.error,
                          bold: true,
                        ),
                      if (tx.pointsEarned > 0)
                        _SummaryRow(
                            'Poin Didapat', '+${tx.pointsEarned} poin',
                            color: scheme.tertiary),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (isKurangBayar) ...[
            FilledButton.tonal(
              onPressed: () => _showTambahBayar(context),
              child: const Text('Tambah Bayar'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            onPressed: () => context.go('/kasir'),
            child: const Text('Transaksi Baru'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Tampilan struk gaya kertas thermal (putih, monospace) untuk
/// di-capture sebagai gambar dan dibagikan.
class _ReceiptPaper extends StatelessWidget {
  const _ReceiptPaper({
    required this.tx,
    required this.items,
    required this.productNames,
    required this.unitNames,
    required this.customerName,
    required this.storeName,
    required this.storeAddress,
    required this.storePhone,
  });

  final Transaction tx;
  final List<TransactionItem> items;
  final Map<String, String> productNames;
  final Map<String, String> unitNames;
  final String customerName;
  final String storeName;
  final String storeAddress;
  final String storePhone;

  static const _ink = Color(0xFF111111);
  static const _mono = TextStyle(
      fontFamily: 'monospace', fontSize: 12, color: _ink, height: 1.4);

  @override
  Widget build(BuildContext context) {
    final remaining = tx.total - tx.paid;
    final date =
        '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year} '
        '${tx.createdAt.hour.toString().padLeft(2, '0')}:${tx.createdAt.minute.toString().padLeft(2, '0')}';

    return Container(
      width: 300,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(storeName.toUpperCase(),
              textAlign: TextAlign.center,
              style: _mono.copyWith(
                  fontSize: 16, fontWeight: FontWeight.w900)),
          if (storeAddress.isNotEmpty)
            Text(storeAddress,
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          if (storePhone.isNotEmpty)
            Text('WA: $storePhone',
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          const _DashedLine(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(date, style: _mono),
              Text('#${tx.localId}', style: _mono),
            ],
          ),
          Text(customerName,
              style: _mono.copyWith(
                  fontSize: 16, fontWeight: FontWeight.w900)),
          const _DashedLine(),
          ...items.expand((item) {
            final qtyStr = item.qty % 1 == 0
                ? item.qty.toInt().toString()
                : item.qty.toString();
            return [
              Text(productNames[item.productId] ?? '',
                  style: _mono.copyWith(fontWeight: FontWeight.w700)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      '$qtyStr ${unitNames[item.productUnitId] ?? ''} x ${_fmtNum(item.priceAtSale)}',
                      style: _mono),
                  Text(_fmtNum(item.subtotal), style: _mono),
                ],
              ),
              if (item.itemNote != null)
                Text('* ${item.itemNote}',
                    style: _mono.copyWith(
                        fontSize: 11, fontStyle: FontStyle.italic)),
            ];
          }),
          const _DashedLine(),
          Text('Produk: ${items.length}', style: _mono),
          const _DashedLine(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: _mono.copyWith(
                      fontSize: 14, fontWeight: FontWeight.w900)),
              Text('Rp ${_fmtNum(tx.total)}',
                  style: _mono.copyWith(
                      fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
          if (tx.paid > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Bayar..', style: _mono),
                Text('Rp ${_fmtNum(tx.paid)}', style: _mono),
              ],
            ),
          if (tx.changeAmount > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Kembali',
                    style: _mono.copyWith(
                        fontSize: 14, fontWeight: FontWeight.w900)),
                Text('Rp ${_fmtNum(tx.changeAmount)}',
                    style: _mono.copyWith(
                        fontSize: 14, fontWeight: FontWeight.w900)),
              ],
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              remaining <= 0
                  ? 'Sudah bayar'
                  : 'Sisa hutang Rp ${_fmtNum(remaining)}',
              style: _mono,
            ),
          ),
          if (tx.strukNote != null) ...[
            const _DashedLine(),
            Text(tx.strukNote!,
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          ],
          const _DashedLine(),
          Text('Terima kasih!',
              textAlign: TextAlign.center,
              style: _mono.copyWith(fontSize: 11)),
        ],
      ),
    );
  }

  String _fmtNum(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
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
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF777777)),
          );
        },
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(
    this.label,
    this.value, {
    this.bold = false,
    this.color,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.normal,
                  color: color)),
          Text(value,
              style: TextStyle(
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.normal,
                  color: color)),
        ],
      ),
    );
  }
}
