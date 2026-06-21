import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final List<String> _matchLog;
  final List<String> _applyLog = [];
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
    _matchLog = widget.result.log.toList();
  }

  int get _matchedSelected => _matched.where((m) => m.selected && m.hasChanges).length;
  int get _notFoundAdd => _notFound.where((n) => n.action == _NfAction.add).length;
  int get _ambiguousLink =>
      _ambiguous.where((a) => a.action == _AmbAction.link).length;

  Future<void> _apply() async {
    final db = ref.read(databaseProvider);
    setState(() => _busy = true);
    _applyLog.clear();
    _applyLog.add('=== APPLY START ===');

    int updated = 0;
    int added = 0;
    int linked = 0;

    try {
      final unitTypes = await db.getAllUnitTypes();
      final typeIdByName = {
        for (final u in unitTypes) u.name.trim().toLowerCase(): u.id
      };

      // 1. Update matched items
      for (final m in _matched) {
        if (!m.selected || !m.hasChanges) continue;
        _applyLog.add('[UPDATE] "${m.localProductName}" '
            'unit=${_short(m.localProductUnitId)}');
        _applyLog.add('  catalog: price=${m.catalogItem.price}, '
            'cost=${m.catalogItem.costPrice}');
        _applyLog.add('  local sebelum: price=${m.localPrice}, '
            'cost=${m.localCostPrice}');

        await _upsertBaseTier(
            db, m.localProductUnitId, m.catalogItem.price, m.catalogItem.costPrice,
            _applyLog);

        // Verifikasi setelah update
        final tiersAfter = await db.getPriceTiers(m.localProductUnitId);
        final allMinQty1 = tiersAfter.where((t) => t.minQty == 1).toList();
        _applyLog.add('  SETELAH update: ${allMinQty1.length} tier minQty=1 →'
            ' ${allMinQty1.map((t) => 'id=${_short(t.id)} price=${t.price} cost=${t.costPrice}').join(' | ')}');

        await (db.update(db.products)
              ..where((t) => t.id.equals(m.localProductId)))
            .write(ProductsCompanion(updatedAt: Value(DateTime.now())));
        updated++;
      }

      // 2. Add not-found items
      for (final nf in _notFound) {
        if (nf.action != _NfAction.add) continue;
        _applyLog.add('[ADD] "${nf.catalogItem.productName}" '
            'price=${nf.catalogItem.price}');
        await _addCatalogProduct(db, nf.catalogItem, typeIdByName);
        added++;
      }

      // 3. Ambiguous items
      for (final a in _ambiguous) {
        final c = a.item.catalogItem;
        if (a.action == _AmbAction.link) {
          _applyLog.add('[LINK] "${a.item.localProductName}" ← '
              '"${c.productName}" price=${c.price}');
          await _upsertBaseTier(
              db, a.item.localProductUnitId, c.price, c.costPrice, _applyLog);
          await (db.update(db.products)
                ..where((t) => t.id.equals(a.item.localProductId)))
              .write(ProductsCompanion(updatedAt: Value(DateTime.now())));
          linked++;
        } else if (a.action == _AmbAction.addNew) {
          _applyLog.add('[ADD-NEW] "${c.productName}" price=${c.price}');
          await _addCatalogProduct(db, c, typeIdByName);
          added++;
        }
      }

      _applyLog.add('=== APPLY DONE: $updated updated, $added added, '
          '$linked linked ===');

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
            TextButton(
              onPressed: () => _showLogDialog(ctx),
              child: const Text('Lihat Log'),
            ),
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
      _applyLog.add('ERROR: $e');
      if (!mounted) return;
      showError('Gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upsertBaseTier(
      AppDatabase db, String unitId, int price, int costPrice,
      [List<String>? log]) async {
    final existing = await (db.select(db.priceTiers)
          ..where((t) => t.productUnitId.equals(unitId) & t.minQty.equals(1)))
        .get();
    log?.add('  _upsertBaseTier: unit=${_short(unitId)}, '
        'target price=$price, cost=$costPrice');
    log?.add('    existing tiers minQty=1: ${existing.length} → '
        '${existing.map((t) => 'id=${_short(t.id)} price=${t.price} cost=${t.costPrice}').join(' | ')}');
    if (existing.isNotEmpty) {
      log?.add('    UPDATE tier id=${_short(existing.first.id)} '
          '(${existing.first.price} → $price)');
      await (db.update(db.priceTiers)
            ..where((t) => t.id.equals(existing.first.id)))
          .write(PriceTiersCompanion(
        price: Value(price),
        costPrice: Value(costPrice),
      ));
    } else {
      final newId = const Uuid().v4();
      log?.add('    INSERT new tier id=${_short(newId)}');
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: newId,
            productUnitId: unitId,
            price: price,
            costPrice: Value(costPrice),
          ));
    }
  }

  static String _short(String uuid) =>
      uuid.length > 8 ? uuid.substring(0, 8) : uuid;

  /// Cari produk lokal yang cocok (prioritas kode produk, lalu nama). Untuk
  /// varian, pencocokan nama juga dibatasi pada induk yang sama agar dua varian
  /// bernama sama di bawah induk berbeda tidak saling tertukar. Bila tidak ada,
  /// buat produk baru. Mencegah duplikat saat beberapa baris katalog menunjuk
  /// produk yang sama (mis. satu produk dengan beberapa satuan).
  Future<String> _findOrCreateProduct(
    AppDatabase db, {
    required String name,
    String? kode,
    String? parentId,
    bool isChild = false,
  }) async {
    final candidates = await db.searchProducts('');
    Product? found;
    if (kode != null && kode.trim().isNotEmpty) {
      final k = kode.trim().toLowerCase();
      found = candidates
          .where((p) => (p.kodeProduk ?? '').trim().toLowerCase() == k)
          .firstOrNull;
    }
    found ??= candidates.where((p) {
      if (p.name.trim().toLowerCase() != name.trim().toLowerCase()) {
        return false;
      }
      return isChild ? p.parentProductId == parentId : true;
    }).firstOrNull;
    if (found != null) return found.id;

    final id = const Uuid().v4();
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: id,
          name: name,
          kodeProduk: Value(kode),
          parentProductId: Value(parentId),
          updatedAt: Value(DateTime.now()),
        ));
    return id;
  }

  /// Tambah produk dari catalog item: tautkan ke induk bila varian, buat unit
  /// dengan satuan & rasio yang benar, lalu set harga.
  Future<void> _addCatalogProduct(
    AppDatabase db,
    PriceCatalogItem c,
    Map<String, int> typeIdByName,
  ) async {
    String? parentId;
    if (c.isVariant) {
      final pName = (c.parentName ?? c.parentKode ?? '').trim();
      if (pName.isNotEmpty) {
        parentId = await _findOrCreateProduct(db, name: pName, kode: c.parentKode);
      }
    }

    final productId = await _findOrCreateProduct(
      db,
      name: c.productName,
      kode: c.kodeProduk,
      parentId: parentId,
      isChild: parentId != null,
    );

    final unitId = const Uuid().v4();
    final unitTypeId = c.unitTypeName.trim().isEmpty
        ? null
        : typeIdByName[c.unitTypeName.trim().toLowerCase()];
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: productId,
          unitTypeId: Value(unitTypeId),
          isBaseUnit: Value(c.isBaseUnit),
          ratioToBase: Value(c.ratioToBase),
        ));
    await _upsertBaseTier(db, unitId, c.price, c.costPrice);

    if (c.barcode != null && c.barcode!.isNotEmpty) {
      // Hindari crash unique-constraint bila barcode sudah ada di device ini.
      final existingBc = await db.lookupBarcode(c.barcode!);
      if (existingBc == null) {
        await db.into(db.productBarcodes).insert(
              ProductBarcodesCompanion.insert(
                id: const Uuid().v4(),
                productUnitId: unitId,
                barcode: c.barcode!,
                isPrimary: const Value(true),
              ),
            );
      }
    }
  }

  void _showLogDialog(BuildContext ctx) {
    final allLog = [..._matchLog, '', ..._applyLog];
    final text = allLog.join('\n');
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Sync Log', style: TextStyle(fontSize: 16))),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(c).showSnackBar(
                    const SnackBar(content: Text('Log disalin')));
              },
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Preview Harga'),
          actions: [
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: 'Lihat Log Matching',
              onPressed: () => _showLogDialog(context),
            ),
          ],
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
  _NotFoundItem({required this.catalogItem});
  final PriceCatalogItem catalogItem;
  _NfAction action = _NfAction.skip;
}

enum _AmbAction { skip, link, addNew }

class _AmbiguousAction {
  _AmbiguousAction({required this.item});
  final AmbiguousItem item;
  _AmbAction action = _AmbAction.skip;
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
            if (c.isVariant)
              Text('Varian dari: ${c.parentName ?? c.parentKode}',
                  style: TextStyle(fontSize: 11, color: scheme.tertiary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (action, label) in const [
                  (_NfAction.skip, 'Lewati'),
                  (_NfAction.add, 'Tambah'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: item.action == action,
                    onSelected: (_) => onChanged(action),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
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
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (action, label) in const [
                  (_AmbAction.skip, 'Lewati'),
                  (_AmbAction.link, 'Samakan'),
                  (_AmbAction.addNew, 'Tambah Baru'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: item.action == action,
                    onSelected: (_) => onChanged(action),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
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
