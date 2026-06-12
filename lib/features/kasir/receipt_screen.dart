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
import '../../core/utils/input_formatters.dart';
import 'widgets/tx_history_sheet.dart';

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
  Map<String, String?> _parentOf = {}; // productId → parentProductId
  Customer? _customer;
  bool _loading = true;

  /// Checklist verifikasi serah-terima barang. Murni lokal (tidak disimpan).
  final Map<String, bool> _checked = {};
  bool get _allChecked =>
      _items.isNotEmpty && _items.every((i) => _checked[i.id] == true);
  Set<String> get _checkedIds => _checked.entries
      .where((e) => e.value)
      .map((e) => e.key)
      .toSet();

  /// Item induk dari sebuah baris (null bila baris ini bukan varian atau
  /// induknya tidak ada di transaksi ini).
  TransactionItem? _parentItemOf(TransactionItem item) {
    final pid = _parentOf[item.productId];
    if (pid == null) return null;
    for (final it in _items) {
      if (it.productId == pid && _parentOf[it.productId] == null) return it;
    }
    return null;
  }

  List<TransactionItem> get _topLevelItems =>
      _items.where((i) => _parentItemOf(i) == null).toList();

  List<TransactionItem> _childrenOf(TransactionItem parent) =>
      _items.where((i) => _parentItemOf(i)?.id == parent.id).toList();

  void _setParentChecked(TransactionItem parent, bool v) {
    setState(() {
      _checked[parent.id] = v;
      for (final c in _childrenOf(parent)) {
        _checked[c.id] = v;
      }
    });
  }

  void _setChildChecked(TransactionItem parent, TransactionItem child, bool v) {
    setState(() {
      _checked[child.id] = v;
      final kids = _childrenOf(parent);
      _checked[parent.id] = kids.every((c) => _checked[c.id] == true);
    });
  }

  Widget _itemCheckRow(TransactionItem item, ColorScheme scheme,
      {required bool isVariant, TransactionItem? parent}) {
    final checked = _checked[item.id] ?? false;
    final hasChildren = !isVariant && _childrenOf(item).isNotEmpty;
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: checked,
      contentPadding: EdgeInsets.only(left: isVariant ? 28 : 4, right: 4),
      onChanged: (v) {
        final nv = v ?? false;
        if (isVariant && parent != null) {
          _setChildChecked(parent, item, nv);
        } else if (hasChildren) {
          _setParentChecked(item, nv);
        } else {
          setState(() => _checked[item.id] = nv);
        }
      },
      title: Row(
        children: [
          if (isVariant)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.subdirectory_arrow_right,
                  size: 13, color: scheme.onSurfaceVariant),
            ),
          Expanded(
            child: Text(
              _productNames[item.productId] ?? item.productId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isVariant ? 12 : 13,
                fontWeight: isVariant ? FontWeight.w400 : FontWeight.w500,
                decoration: checked ? TextDecoration.lineThrough : null,
                color: checked
                    ? scheme.onSurfaceVariant
                    : (isVariant ? scheme.onSurfaceVariant : null),
              ),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: EdgeInsets.only(left: isVariant ? 17 : 0),
        child: Text(
          '${_unitNames[item.productUnitId] ?? ''} ${item.qty % 1 == 0 ? item.qty.toInt() : item.qty} × ${formatRupiah(item.priceAtSale)}'
          '${item.itemNote != null ? '\n${item.itemNote}' : ''}',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ),
      secondary: Text(
        formatRupiah(item.subtotal),
        style: TextStyle(
            fontSize: isVariant ? 12 : 13, fontWeight: FontWeight.w600),
      ),
    );
  }

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
    final parentOf = <String, String?>{};
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

    if (mounted) {
      setState(() {
        _tx = tx;
        _items = items;
        _productNames = productNames;
        _unitNames = unitNames;
        _parentOf = parentOf;
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
    final messenger = ScaffoldMessenger.of(context);
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
              inputFormatters: const [ThousandsSeparatorFormatter()],
              decoration:
                  const InputDecoration(prefixText: 'Rp ', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => ctx.pop(), child: const Text('Batal')),
          FilledButton(
            onPressed: () =>
                ctx.pop(ThousandsSeparatorFormatter.parseValue(ctrl.text)),
            child: const Text('Bayar'),
          ),
        ],
      ),
    );

    if (result != null && result > 0 && mounted) {
      final db = ref.read(databaseProvider);
      final device = ref.read(deviceProvider);
      final now = DateTime.now();
      final tx = _tx!;
      // Uang diterima boleh melebihi sisa → kelebihan jadi kembalian.
      final applied = result.clamp(1, remaining);
      final change = result > remaining ? result - remaining : 0;

      await db.into(db.transactionPayments).insert(
            TransactionPaymentsCompanion.insert(
              id: _receiptUuid.v4(),
              transactionId: widget.transactionId,
              amount: applied,
              method: 'tunai',
              paidAt: Value(now),
              kasirId: Value(device.deviceCode),
            ),
          );

      final newPaid = tx.paid + applied;
      final lunas = newPaid >= tx.total;
      await (db.update(db.transactions)
            ..where((t) => t.id.equals(widget.transactionId)))
          .write(TransactionsCompanion(
        paid: Value(newPaid),
        status: Value(lunas ? 'lunas' : 'kurang_bayar'),
        changeAmount: Value(tx.changeAmount + change),
      ));
      await _load();
      if (change > 0) {
        messenger.showSnackBar(SnackBar(
            content: Text('Kembalian ${formatRupiah(change)}')));
      }
    }
  }

  Future<void> _showVoid(BuildContext context) async {
    final ok = await showVoidTransactionDialog(context, ref, _tx!);
    if (ok && mounted) await _load();
  }

  Future<void> _showReturSheet(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final returnQty = <String, double>{for (final i in _items) i.id: 0};
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            int refund = 0;
            for (final i in _items) {
              refund += (i.priceAtSale * (returnQty[i.id] ?? 0)).round();
            }
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Retur Barang',
                        style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Pilih jumlah barang yang dikembalikan.',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: _items.map((item) {
                          final maxQty = item.qty;
                          final q = returnQty[item.id] ?? 0;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                                _productNames[item.productId] ??
                                    item.productId,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                                'Maks ${maxQty % 1 == 0 ? maxQty.toInt() : maxQty} · ${formatRupiah(item.priceAtSale)}',
                                style: const TextStyle(fontSize: 11)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                      Icons.remove_circle_outline,
                                      size: 20),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: q <= 0
                                      ? null
                                      : () => setSheet(() =>
                                          returnQty[item.id] = q - 1),
                                ),
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    q % 1 == 0 ? q.toInt().toString() : '$q',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline,
                                      size: 20),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: q >= maxQty
                                      ? null
                                      : () => setSheet(() =>
                                          returnQty[item.id] = q + 1),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Refund',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        Text(formatRupiah(refund),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: scheme.error)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: refund <= 0
                          ? null
                          : () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                          backgroundColor: scheme.error),
                      child: const Text('Konfirmasi Retur'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved != true || !mounted) return;

    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final now = DateTime.now();
    final txCount = await db.countTodayTransactions(device.deviceCode);
    final localId =
        '${device.deviceCode}-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(txCount + 1).toString().padLeft(4, '0')}';

    final returnItems = [
      for (final item in _items)
        if ((returnQty[item.id] ?? 0) > 0)
          (
            productUnitId: item.productUnitId,
            productId: item.productId,
            qty: returnQty[item.id]!,
            price: item.priceAtSale,
            costPrice: item.costAtSale,
          ),
    ];
    if (returnItems.isEmpty) return;

    await db.addReturnTransaction(
      originalTxId: _tx!.id,
      localId: localId,
      returnItems: returnItems,
      kasirId: device.deviceCode,
    );
    if (mounted) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Retur dicatat, stok dikembalikan')));
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
            onPressed: () => context.push('/pengaturan/printer'),
          ),
        ),
      );
      return;
    }
    // Pastikan izin Bluetooth runtime sudah ada agar tidak menggantung.
    final granted = await PrinterService.ensurePermissions();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Izin Bluetooth ditolak'),
          action: SnackBarAction(
            label: 'Pengaturan',
            onPressed: () => context.push('/pengaturan/printer'),
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
      parentOf: _parentOf,
      checkedIds: _checkedIds,
    );
    if (!mounted) return;
    AppTheme.showSnack(
        context, ok ? 'Struk berhasil dicetak' : 'Gagal mencetak struk',
        isError: !ok);
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
                      parentOf: _parentOf,
                      checkedIds: _checkedIds,
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
    final isVoid = tx.status == 'void';
    final isRetur = tx.internalNote?.startsWith('RETUR:') ?? false;

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

          // Verifikasi serah-terima barang
          if (_items.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  final target = !_allChecked;
                  for (final i in _items) {
                    _checked[i.id] = target;
                  }
                }),
                icon: Icon(
                    _allChecked
                        ? Icons.remove_done
                        : Icons.done_all,
                    size: 18),
                label: Text(_allChecked ? 'Hapus Tanda' : 'Tandai Semua',
                    style: const TextStyle(fontSize: 12)),
              ),
            ),

          // Items (varian bersarang di bawah induk)
          Card(
            child: Column(
              children: [
                for (final parent in _topLevelItems) ...[
                  _itemCheckRow(parent, scheme, isVariant: false),
                  for (final child in _childrenOf(parent))
                    _itemCheckRow(child, scheme,
                        isVariant: true, parent: parent),
                ],
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

          if (isKurangBayar && !isVoid) ...[
            FilledButton.tonal(
              onPressed: () => _showTambahBayar(context),
              child: const Text('Tambah Bayar'),
            ),
            const SizedBox(height: 8),
          ],
          if (!isVoid && !isRetur)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showVoid(context),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Batalkan'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showReturSheet(context),
                    icon: const Icon(Icons.assignment_return_outlined,
                        size: 18),
                    label: const Text('Retur'),
                  ),
                ),
              ],
            ),
          if (isVoid)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.block, color: scheme.onErrorContainer, size: 18),
                  const SizedBox(width: 8),
                  Text('Transaksi ini telah dibatalkan',
                      style: TextStyle(color: scheme.onErrorContainer)),
                ],
              ),
            ),
          const SizedBox(height: 8),
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
    this.parentOf = const {},
    this.checkedIds = const {},
  });

  final Transaction tx;
  final List<TransactionItem> items;
  final Map<String, String> productNames;
  final Map<String, String> unitNames;
  final Map<String, String?> parentOf;
  final String customerName;
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final Set<String> checkedIds;

  static const _ink = Color(0xFF111111);
  static const _mono = TextStyle(
      fontFamily: 'monospace', fontSize: 12, color: _ink, height: 1.4);

  TransactionItem? _parentItemOf(TransactionItem item) {
    final pid = parentOf[item.productId];
    if (pid == null) return null;
    for (final it in items) {
      if (it.productId == pid && parentOf[it.productId] == null) return it;
    }
    return null;
  }

  /// Item terurut: induk diikuti varian-variannya.
  List<TransactionItem> get _ordered {
    final out = <TransactionItem>[];
    for (final it in items) {
      if (_parentItemOf(it) == null) {
        out.add(it);
        for (final c in items) {
          if (_parentItemOf(c)?.id == it.id) out.add(c);
        }
      }
    }
    return out;
  }

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
          ..._ordered.expand((item) {
            final isVar = _parentItemOf(item) != null;
            final pad = isVar ? '  ' : '';
            final qtyStr = item.qty % 1 == 0
                ? item.qty.toInt().toString()
                : item.qty.toString();
            final mark = checkedIds.contains(item.id) ? '✓ ' : '';
            final namePrefix = isVar ? '$pad└ ' : '';
            return [
              Text('$mark$namePrefix${productNames[item.productId] ?? ''}',
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
              if (item.itemNote != null)
                Text('$pad* ${item.itemNote}',
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
