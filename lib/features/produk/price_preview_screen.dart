import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/services/price_match_service.dart';
import '../../core/services/price_sync_service.dart';
import '../../core/widgets/inline_banner.dart';

class PricePreviewScreen extends ConsumerStatefulWidget {
  const PricePreviewScreen({super.key, required this.result});
  final PriceMatchResult result;

  @override
  ConsumerState<PricePreviewScreen> createState() => _PricePreviewScreenState();
}

class _PricePreviewScreenState extends ConsumerState<PricePreviewScreen>
    with InlineBannerStateMixin<PricePreviewScreen> {
  late final List<MatchedItem> _matched;
  late final List<_NotFoundItem> _notFound;
  late final List<_AmbiguousAction> _ambiguous;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _matched = widget.result.matched.toList();
    _notFound = widget.result.notFound
        .map((c) => _NotFoundItem(catalogItem: c))
        .toList();
    _ambiguous = widget.result.ambiguous
        .map((a) => _AmbiguousAction(item: a))
        .toList();
  }

  int get _matchedSelected => _matched.where((m) => m.selected && m.hasChanges).length;
  int get _notFoundAdd => _notFound.where((n) => n.action == _NfAction.add).length;
  int get _ambiguousLink =>
      _ambiguous.where((a) => a.action == _AmbAction.link).length;

  Future<void> _apply() async {
    final db = ref.read(databaseProvider);
    setState(() => _busy = true);

    int updated = 0;
    int added = 0;
    int linked = 0;

    try {
      // 1. Update matched items
      for (final m in _matched) {
        if (!m.selected || !m.hasChanges) continue;
        await db.customStatement(
          'UPDATE price_tiers SET price = ?, cost_price = ? '
          'WHERE product_unit_id = ? AND min_qty = 1',
          [m.catalogItem.price, m.catalogItem.costPrice, m.localProductUnitId],
        );
        await (db.update(db.products)
              ..where((t) => t.id.equals(m.localProductId)))
            .write(ProductsCompanion(updatedAt: Value(DateTime.now())));
        updated++;
      }

      // 2. Add not-found items
      for (final nf in _notFound) {
        if (nf.action != _NfAction.add) continue;
        final c = nf.catalogItem;
        final productId = const Uuid().v4();
        final unitId = const Uuid().v4();
        final now = DateTime.now();

        await db.into(db.products).insert(ProductsCompanion.insert(
          id: productId,
          name: c.productName,
          kodeProduk: Value(c.kodeProduk),
          updatedAt: Value(now),
        ));
        await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: productId,
        ));
        await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: const Uuid().v4(),
          productUnitId: unitId,
          price: c.price,
          costPrice: Value(c.costPrice),
        ));
        if (c.barcode != null && c.barcode!.isNotEmpty) {
          await db.into(db.productBarcodes).insert(
            ProductBarcodesCompanion.insert(
              id: const Uuid().v4(),
              productUnitId: unitId,
              barcode: c.barcode!,
              isPrimary: const Value(true),
            ),
          );
        }
        added++;
      }

      // 3. Ambiguous items
      for (final a in _ambiguous) {
        final c = a.item.catalogItem;
        if (a.action == _AmbAction.link) {
          await db.customStatement(
            'UPDATE price_tiers SET price = ?, cost_price = ? '
            'WHERE product_unit_id = ? AND min_qty = 1',
            [c.price, c.costPrice, a.item.localProductUnitId],
          );
          await (db.update(db.products)
                ..where((t) => t.id.equals(a.item.localProductId)))
              .write(ProductsCompanion(updatedAt: Value(DateTime.now())));
          linked++;
        } else if (a.action == _AmbAction.addNew) {
          final productId = const Uuid().v4();
          final unitId = const Uuid().v4();
          final now = DateTime.now();
          await db.into(db.products).insert(ProductsCompanion.insert(
            id: productId,
            name: c.productName,
            kodeProduk: Value(c.kodeProduk),
            updatedAt: Value(now),
          ));
          await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
            id: unitId,
            productId: productId,
          ));
          await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: const Uuid().v4(),
            productUnitId: unitId,
            price: c.price,
            costPrice: Value(c.costPrice),
          ));
          if (c.barcode != null && c.barcode!.isNotEmpty) {
            await db.into(db.productBarcodes).insert(
              ProductBarcodesCompanion.insert(
                id: const Uuid().v4(),
                productUnitId: unitId,
                barcode: c.barcode!,
                isPrimary: const Value(true),
              ),
            );
          }
          added++;
        }
      }

      if (!mounted) return;

      final parts = <String>[];
      if (updated > 0) parts.add('$updated harga diupdate');
      if (added > 0) parts.add('$added produk ditambah');
      if (linked > 0) parts.add('$linked produk disamakan');
      final msg = parts.isEmpty ? 'Tidak ada perubahan' : parts.join(', ');

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Selesai'),
          content: Text(msg),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showError('Gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Preview Harga'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Cocok (${_matched.length})'),
              Tab(text: 'Baru (${_notFound.length})'),
              Tab(text: 'Mirip (${_ambiguous.length})'),
            ],
          ),
        ),
        body: Column(
          children: [
            inlineBanner(),
            Expanded(
              child: TabBarView(
                children: [
                  _buildMatchedTab(scheme),
                  _buildNotFoundTab(scheme),
                  _buildAmbiguousTab(scheme),
                ],
              ),
            ),
            _buildBottomBar(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchedTab(ColorScheme scheme) {
    final changed = _matched.where((m) => m.hasChanges).toList();
    final unchanged = _matched.where((m) => !m.hasChanges).toList();

    if (_matched.isEmpty) {
      return const Center(child: Text('Tidak ada produk yang cocok'));
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (changed.isNotEmpty) ...[
          Row(
            children: [
              Text('Harga Berubah (${changed.length})',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: () {
                  final allSelected = changed.every((m) => m.selected);
                  setState(() {
                    for (final m in changed) {
                      m.selected = !allSelected;
                    }
                  });
                },
                child: Text(changed.every((m) => m.selected)
                    ? 'Hapus Semua'
                    : 'Centang Semua'),
              ),
            ],
          ),
          ...changed.map((m) => _MatchedTile(
                item: m,
                onToggle: () => setState(() => m.selected = !m.selected),
              )),
        ],
        if (unchanged.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Harga Sama (${unchanged.length})',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          ...unchanged.map((m) => ListTile(
                dense: true,
                leading: Icon(Icons.check_circle_outline,
                    color: scheme.outlineVariant, size: 20),
                title: Text(m.localProductName,
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                    'Rp ${_fmt(m.localPrice)} — tidak berubah',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              )),
        ],
      ],
    );
  }

  Widget _buildNotFoundTab(ColorScheme scheme) {
    if (_notFound.isEmpty) {
      return const Center(child: Text('Semua produk ditemukan'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Text('${_notFound.length} produk tidak ditemukan',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  for (final n in _notFound) {
                    n.action = _NfAction.add;
                  }
                }),
                child: const Text('Tambah Semua'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  for (final n in _notFound) {
                    n.action = _NfAction.skip;
                  }
                }),
                child: const Text('Lewati Semua'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _notFound.length,
            itemBuilder: (context, i) {
              final nf = _notFound[i];
              return _NotFoundTile(
                item: nf,
                onChanged: (action) =>
                    setState(() => nf.action = action),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAmbiguousTab(ColorScheme scheme) {
    if (_ambiguous.isEmpty) {
      return const Center(child: Text('Tidak ada produk ambigu'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _ambiguous.length,
      itemBuilder: (context, i) {
        final a = _ambiguous[i];
        return _AmbiguousTile(
          item: a,
          onChanged: (action) => setState(() => a.action = action),
        );
      },
    );
  }

  Widget _buildBottomBar(ColorScheme scheme) {
    final total = _matchedSelected + _notFoundAdd + _ambiguousLink;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withOpacity(0.3))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _busy || total == 0 ? null : _apply,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text('Terapkan ($total perubahan)'),
          ),
        ),
      ),
    );
  }
}

// ── Data classes ──

enum _NfAction { skip, add }

class _NotFoundItem {
  _NotFoundItem({required this.catalogItem, this.action = _NfAction.skip});
  final PriceCatalogItem catalogItem;
  _NfAction action;
}

enum _AmbAction { skip, link, addNew }

class _AmbiguousAction {
  _AmbiguousAction({required this.item, this.action = _AmbAction.skip});
  final AmbiguousItem item;
  _AmbAction action;
}

// ── Tiles ──

class _MatchedTile extends StatelessWidget {
  const _MatchedTile({required this.item, required this.onToggle});
  final MatchedItem item;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final matchLabel = switch (item.matchType) {
      MatchType.barcode => 'Barcode',
      MatchType.sku => 'SKU',
      MatchType.fuzzy => 'Nama',
    };

    return CheckboxListTile(
      value: item.selected,
      onChanged: (_) => onToggle(),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(item.localProductName, style: const TextStyle(fontSize: 13)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.priceChanged)
            RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                children: [
                  const TextSpan(text: 'Harga: '),
                  TextSpan(
                    text: 'Rp ${_fmt(item.localPrice)}',
                    style: const TextStyle(
                        decoration: TextDecoration.lineThrough, fontSize: 11),
                  ),
                  TextSpan(
                    text: ' → Rp ${_fmt(item.catalogItem.price)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: scheme.primary),
                  ),
                ],
              ),
            ),
          if (item.costChanged)
            RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                children: [
                  const TextSpan(text: 'Modal: '),
                  TextSpan(
                    text: 'Rp ${_fmt(item.localCostPrice)}',
                    style: const TextStyle(
                        decoration: TextDecoration.lineThrough, fontSize: 11),
                  ),
                  TextSpan(
                    text: ' → Rp ${_fmt(item.catalogItem.costPrice)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: scheme.tertiary),
                  ),
                ],
              ),
            ),
          Text('Cocok via: $matchLabel',
              style: TextStyle(fontSize: 10, color: scheme.outline)),
        ],
      ),
    );
  }
}

class _NotFoundTile extends StatelessWidget {
  const _NotFoundTile({required this.item, required this.onChanged});
  final _NotFoundItem item;
  final ValueChanged<_NfAction> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = item.catalogItem;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.productName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            if (c.barcode != null)
              Text('Barcode: ${c.barcode}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            if (c.kodeProduk != null)
              Text('SKU: ${c.kodeProduk}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            Text('Harga: Rp ${_fmt(c.price)}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            SegmentedButton<_NfAction>(
              segments: const [
                ButtonSegment(value: _NfAction.skip, label: Text('Lewati')),
                ButtonSegment(value: _NfAction.add, label: Text('Tambah')),
              ],
              selected: {item.action},
              onSelectionChanged: (s) => onChanged(s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(
                    Theme.of(context).textTheme.labelSmall),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbiguousTile extends StatelessWidget {
  const _AmbiguousTile({required this.item, required this.onChanged});
  final _AmbiguousAction item;
  final ValueChanged<_AmbAction> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = item.item;
    final pct = (a.similarity * 100).round();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: scheme.tertiaryContainer.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.help_outline, size: 16, color: scheme.tertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('"${a.catalogItem.productName}" dari sumber',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mirip dengan: "${a.localProductName}"',
                          style: const TextStyle(fontSize: 12)),
                      Text('Kemiripan: $pct%',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant)),
                      if (a.catalogItem.price != a.localPrice)
                        Text(
                            'Harga: Rp ${_fmt(a.localPrice)} → Rp ${_fmt(a.catalogItem.price)}',
                            style: TextStyle(
                                fontSize: 12, color: scheme.primary)),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            SegmentedButton<_AmbAction>(
              segments: const [
                ButtonSegment(value: _AmbAction.skip, label: Text('Lewati')),
                ButtonSegment(
                    value: _AmbAction.link, label: Text('Samakan')),
                ButtonSegment(
                    value: _AmbAction.addNew, label: Text('Tambah Baru')),
              ],
              selected: {item.action},
              onSelectionChanged: (s) => onChanged(s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(
                    Theme.of(context).textTheme.labelSmall),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmt(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}
