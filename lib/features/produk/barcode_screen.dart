import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';

class BarcodeScreen extends ConsumerStatefulWidget {
  const BarcodeScreen({super.key, required this.productId});
  final String productId;

  @override
  ConsumerState<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends ConsumerState<BarcodeScreen> {
  Product? _product;
  List<_BarcodeEntry> _entries = [];
  bool _loading = true;

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
    if (p == null || !mounted) {
      setState(() => _loading = false);
      return;
    }
    final units = await db.getProductUnits(widget.productId);
    final entries = <_BarcodeEntry>[];
    for (final u in units) {
      final unitType = await (db.select(db.unitTypes)
            ..where((t) => t.id.equals(u.unitTypeId ?? 1)))
          .getSingleOrNull();
      final barcodes = await db.getProductBarcodes(u.id);
      for (final bc in barcodes) {
        entries.add(_BarcodeEntry(
          barcode: bc.barcode,
          productName: p.name,
          unitName: unitType?.name ?? 'Satuan',
          isPrimary: bc.isPrimary,
        ));
      }
    }
    if (mounted) {
      setState(() {
        _product = p;
        _entries = entries;
        _loading = false;
      });
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
                    'Tidak ada barcode untuk produk ini.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _entries
                      .map((e) => _BarcodeCard(entry: e))
                      .toList(),
                ),
    );
  }
}

class _BarcodeEntry {
  const _BarcodeEntry({
    required this.barcode,
    required this.productName,
    required this.unitName,
    required this.isPrimary,
  });
  final String barcode;
  final String productName;
  final String unitName;
  final bool isPrimary;
}

class _BarcodeCard extends StatelessWidget {
  const _BarcodeCard({required this.entry});
  final _BarcodeEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Text('${entry.productName} · ${entry.unitName}',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (entry.isPrimary)
                  Chip(
                    label: const Text('Primer', style: TextStyle(fontSize: 10)),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: scheme.primaryContainer,
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            BarcodeWidget(
              barcode: Barcode.code128(),
              data: entry.barcode,
              width: double.infinity,
              height: 80,
              drawText: true,
              style: TextStyle(
                  fontSize: 11, color: scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
