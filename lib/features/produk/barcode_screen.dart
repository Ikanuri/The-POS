import 'package:barcode_widget/barcode_widget.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/services/printer_service.dart';
import '../../core/theme/app_theme.dart';

class BarcodeScreen extends ConsumerStatefulWidget {
  const BarcodeScreen({super.key, required this.productId});
  final String productId;

  @override
  ConsumerState<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends ConsumerState<BarcodeScreen> {
  Product? _product;
  List<_UnitEntry> _entries = [];
  bool _loading = true;
  final Set<String> _busyUnitIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final p = await (db.select(db.products)
          ..where((t) => t.id.equals(widget.productId)))
        .getSingleOrNull();
    if (p == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!mounted) return;
    final units = await db.getProductUnits(widget.productId);
    final entries = <_UnitEntry>[];
    for (final u in units) {
      final unitType = await (db.select(db.unitTypes)
            ..where((t) => t.id.equals(u.unitTypeId ?? 1)))
          .getSingleOrNull();
      final barcodes = await db.getProductBarcodes(u.id);
      final baseTier = await (db.select(db.priceTiers)
            ..where(
                (t) => t.productUnitId.equals(u.id) & t.minQty.equals(1)))
          .getSingleOrNull();
      entries.add(_UnitEntry(
        productUnitId: u.id,
        productName: p.name,
        unitName: unitType?.name ?? 'Satuan',
        price: baseTier?.price ?? 0,
        barcodes: barcodes
            .map((bc) => _BarcodeEntry(
                barcode: bc.barcode, isPrimary: bc.isPrimary))
            .toList(),
      ));
    }
    if (mounted) {
      setState(() {
        _product = p;
        _entries = entries;
        _loading = false;
      });
    }
  }

  Future<void> _printLabel(_UnitEntry entry, String barcode) async {
    setState(() => _busyUnitIds.add(entry.productUnitId));
    try {
      final mac = await PrinterService.getSavedMac();
      if (mac == null || mac.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Printer belum diatur — atur di Pengaturan > Printer')));
        }
        return;
      }
      final ok = await PrinterService.printProductLabel(
        productName: entry.productName,
        unitQty: '1',
        variantLabel: entry.unitName,
        price: entry.price,
        barcode: barcode,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(ok ? 'Label terkirim ke printer' : 'Gagal mencetak label')));
      }
    } finally {
      if (mounted) setState(() => _busyUnitIds.remove(entry.productUnitId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_product?.name ?? 'Barcode'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(
                  child: Text(
                    'Tidak ada satuan untuk produk ini.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _entries
                      .map((e) => _UnitCard(
                            entry: e,
                            busy: _busyUnitIds.contains(e.productUnitId),
                            onPrint: (bc) => _printLabel(e, bc),
                          ))
                      .toList(),
                ),
    );
  }
}

class _UnitEntry {
  const _UnitEntry({
    required this.productUnitId,
    required this.productName,
    required this.unitName,
    required this.price,
    required this.barcodes,
  });
  final String productUnitId;
  final String productName;
  final String unitName;
  final int price;
  final List<_BarcodeEntry> barcodes;
}

class _BarcodeEntry {
  const _BarcodeEntry({required this.barcode, required this.isPrimary});
  final String barcode;
  final bool isPrimary;
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.entry,
    required this.busy,
    required this.onPrint,
  });
  final _UnitEntry entry;
  final bool busy;
  final ValueChanged<String> onPrint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${entry.productName} · ${entry.unitName}',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Text(formatRupiah(entry.price),
                    style: AppTheme.numStyle(context)),
              ],
            ),
            const SizedBox(height: 16),
            if (entry.barcodes.isEmpty)
              Text(
                'Belum ada barcode untuk satuan ini — isi/generate lewat '
                'field Barcode di form Edit Produk.',
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              )
            else
              ...entry.barcodes.map((bc) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(bc.barcode,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            if (bc.isPrimary)
                              Chip(
                                label: const Text('Primer',
                                    style: TextStyle(fontSize: 10)),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: scheme.primaryContainer,
                                side: BorderSide.none,
                                padding: EdgeInsets.zero,
                              ),
                            const Spacer(),
                            OutlinedButton.icon(
                              onPressed: busy ? null : () => onPrint(bc.barcode),
                              icon: const Icon(Icons.print_outlined, size: 16),
                              label: const Text('Cetak Label'),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 36)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        BarcodeWidget(
                          barcode: Barcode.code128(),
                          data: bc.barcode,
                          width: double.infinity,
                          height: 60,
                          drawText: false,
                          errorBuilder: (context, error) =>
                              const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
