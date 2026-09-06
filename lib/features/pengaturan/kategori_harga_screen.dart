import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/utils/price_category_calc.dart';

/// Fase B "Kategori Harga" — kategori murni label pengelompokan (TIDAK ADA
/// margin default per kategori, lihat dok `PriceCategories`). Margin selalu
/// per-produk lewat `KategoriHargaDetailScreen`.
///
/// Fase C (toggle aktif kategori di keranjang kasir + integrasi
/// `PriceService`) MENYUSUL terpisah — TIDAK disentuh di sini. Manual
/// override selalu menang begitu Fase C ada (pengingat, lihat PLAN/HANDOFF).
final _priceCategoriesProvider = StreamProvider<List<PriceCategory>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchPriceCategories();
});

class KategoriHargaScreen extends ConsumerWidget {
  const KategoriHargaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(_priceCategoriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kategori Harga'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDialog(context, ref),
          ),
        ],
      ),
      body: catsAsync.when(
        data: (cats) => cats.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Belum ada kategori harga. Buat kategori untuk '
                    'mengelompokkan produk (mis. "Grosir", "Rokok") dan atur '
                    'margin per produk.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            : ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: cats.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final ids = cats.map((c) => c.id).toList();
                  final moved = ids.removeAt(oldIndex);
                  ids.insert(newIndex, moved);
                  ref.read(databaseProvider).reorderPriceCategories(ids);
                },
                itemBuilder: (_, i) => _CategoryTile(
                    key: ValueKey(cats[i].id), category: cats[i], index: i),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile(
      {super.key, required this.category, required this.index});
  final PriceCategory category;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    final tile = Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: Icon(Icons.drag_handle, color: scheme.onSurfaceVariant),
        ),
        title: Text(category.name),
        trailing: IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          tooltip: 'Ubah nama',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _NameDialog(existing: category),
          ),
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => KategoriHargaDetailScreen(
              categoryId: category.id, categoryName: category.name),
        )),
      ),
    );

    return Dismissible(
      key: ValueKey('cat-dismiss-${category.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline, color: scheme.error),
      ),
      confirmDismiss: (_) async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Hapus ${category.name}?'),
            content: const Text(
                'Kategori ini akan dihapus. Produk anggotanya TIDAK ikut '
                'terhapus — harganya jadi harga manual biasa (beku di nilai '
                'terakhir), tidak lagi ikut kategori ini.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Hapus')),
            ],
          ),
        );
        return ok ?? false;
      },
      onDismissed: (_) async {
        await ref.read(databaseProvider).deletePriceCategory(category.id);
      },
      child: tile,
    );
  }
}

class _NameDialog extends ConsumerStatefulWidget {
  const _NameDialog({this.existing});
  final PriceCategory? existing;

  @override
  ConsumerState<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends ConsumerState<_NameDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.existing?.name ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    final db = ref.read(databaseProvider);
    final navigator = Navigator.of(context);
    if (widget.existing == null) {
      await db.addPriceCategory(name);
    } else {
      await db.renamePriceCategory(widget.existing!.id, name);
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Tambah Kategori' : 'Ubah Nama'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(
            labelText: 'Nama kategori',
            hintText: 'Grosir, Rokok, Sembako…',
            isDense: true),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(
            onPressed: _save,
            child: Text(widget.existing == null ? 'Tambah' : 'Simpan')),
      ],
    );
  }
}

// ─────────────────────────── Detail kategori ──────────────────────────────

class KategoriHargaDetailScreen extends ConsumerStatefulWidget {
  const KategoriHargaDetailScreen(
      {super.key, required this.categoryId, required this.categoryName});
  final String categoryId;
  final String categoryName;

  @override
  ConsumerState<KategoriHargaDetailScreen> createState() =>
      _KategoriHargaDetailScreenState();
}

class _KategoriHargaDetailScreenState
    extends ConsumerState<KategoriHargaDetailScreen> {
  List<PriceCategoryMember> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final members =
        await ref.read(databaseProvider).getPriceCategoryMembers(widget.categoryId);
    if (!mounted) return;
    setState(() {
      _members = members;
      _loading = false;
    });
  }

  Future<void> _addProduct() async {
    final picked = await Navigator.of(context).push<_PickedUnit>(
      MaterialPageRoute(builder: (_) => const _ProductUnitPickerScreen()),
    );
    if (picked == null || !mounted) return;
    // Produk baru masuk kategori dgn margin default 0% dari harga dasar
    // (harga jual = harga dasar apa adanya) — owner isi margin sungguhan
    // lewat editor yang langsung terbuka.
    await _openMarginEditor(
      productUnitId: picked.productUnitId,
      productName: picked.productName,
      unitName: picked.unitName,
      basePrice: picked.basePrice,
      costPrice: picked.costPrice,
      existingAnchor: null,
      existingType: null,
      existingValue: null,
    );
    await _load();
  }

  Future<void> _editMember(PriceCategoryMember m) async {
    await _openMarginEditor(
      productUnitId: m.productUnitId,
      productName: m.productName,
      unitName: m.unitName,
      basePrice: m.basePrice,
      costPrice: m.costPrice,
      existingAnchor: m.marginAnchor,
      existingType: m.marginType,
      existingValue: m.marginValue,
    );
    await _load();
  }

  Future<void> _openMarginEditor({
    required String productUnitId,
    required String productName,
    required String unitName,
    required int basePrice,
    required int costPrice,
    required String? existingAnchor,
    required String? existingType,
    required double? existingValue,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MarginEditorSheet(
        categoryId: widget.categoryId,
        categoryName: widget.categoryName,
        productUnitId: productUnitId,
        productName: productName,
        unitName: unitName,
        basePrice: basePrice,
        costPrice: costPrice,
        initialAnchor: existingAnchor ?? kMarginAnchorDasar,
        initialType: existingType ?? kMarginTypePercent,
        initialValue: existingValue ?? 0,
      ),
    );
  }

  Future<void> _removeMember(PriceCategoryMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Keluarkan ${m.productName}?'),
        content: const Text(
            'Produk ini akan dikeluarkan dari kategori. Pengaturan margin '
            'untuk produk ini akan dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Keluarkan')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(databaseProvider).removeProductFromPriceCategory(m.altPriceId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Produk — ${widget.categoryName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Tambah produk',
            onPressed: _addProduct,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _members.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Belum ada produk di kategori ini. Ketuk + untuk '
                      'menambahkan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _members.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final m = _members[i];
                    final marginDesc = m.marginType == null
                        ? 'Belum diatur'
                        : m.marginType == kMarginTypePercent
                            ? '${m.marginAnchor == kMarginAnchorModal ? 'Modal' : 'Dasar'} '
                                '+ ${m.marginValue!.toStringAsFixed(m.marginValue! % 1 == 0 ? 0 : 1)}%'
                            : '${m.marginAnchor == kMarginAnchorModal ? 'Modal' : 'Dasar'} '
                                '+ ${formatRupiah(m.marginValue!.round())}';
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        title: Text('${m.productName} · ${m.unitName}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                'Dasar ${formatRupiah(m.basePrice)} · '
                                'Modal ${m.costPrice > 0 ? formatRupiah(m.costPrice) : "-"}',
                                style: const TextStyle(fontSize: 11.5)),
                            Text(marginDesc,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(formatRupiah(m.currentPrice),
                                style: AppTheme.numStyle(context,
                                    size: 15, weight: FontWeight.w700)),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              tooltip: 'Keluarkan dari kategori',
                              onPressed: () => _removeMember(m),
                            ),
                          ],
                        ),
                        onTap: () => _editMember(m),
                      ),
                    );
                  },
                ),
    );
  }
}

/// Editor margin bidirectional (Fase B, keputusan desain user):
/// - Toggle Acuan: "Harga Modal" (disabled kalau costPrice<=0) / "Harga
///   Dasar".
/// - Toggle Jenis: "Rupiah" (fixed) / "Persen".
/// - Field "Margin" DAN field "Harga Jual" saling terhubung LIVE — isi
///   salah satu, yang lain otomatis update (pola sama dgn konverter "beli
///   dengan nominal Rp" di `ItemEntrySheet`).
class _MarginEditorSheet extends ConsumerStatefulWidget {
  const _MarginEditorSheet({
    required this.categoryId,
    required this.categoryName,
    required this.productUnitId,
    required this.productName,
    required this.unitName,
    required this.basePrice,
    required this.costPrice,
    required this.initialAnchor,
    required this.initialType,
    required this.initialValue,
  });

  final String categoryId;
  final String categoryName;
  final String productUnitId;
  final String productName;
  final String unitName;
  final int basePrice;
  final int costPrice;
  final String initialAnchor;
  final String initialType;
  final double initialValue;

  @override
  ConsumerState<_MarginEditorSheet> createState() => _MarginEditorSheetState();
}

class _MarginEditorSheetState extends ConsumerState<_MarginEditorSheet> {
  late String _anchor;
  late String _type;
  late final TextEditingController _marginCtrl;
  late final TextEditingController _sellCtrl;

  /// Guard re-entrancy antar 2 field yg saling mengisi (ubah A -> hitung
  /// B -> set text B -> onChanged B terpanggil lagi -> jangan hitung ulang
  /// A dari situ, akan salah nilainya).
  bool _syncing = false;

  bool get _modalAllowed => widget.costPrice > 0;

  @override
  void initState() {
    super.initState();
    _anchor = widget.initialAnchor == kMarginAnchorModal && !_modalAllowed
        ? kMarginAnchorDasar
        : widget.initialAnchor;
    _type = widget.initialType;
    final initialSell = _safeComputePrice(_anchor, _type, widget.initialValue);
    _marginCtrl = TextEditingController(
        text: widget.initialValue == 0 ? '' : _fmtMarginValue(widget.initialValue));
    _sellCtrl = TextEditingController(
        text: initialSell > 0 ? initialSell.toString() : '');
  }

  @override
  void dispose() {
    _marginCtrl.dispose();
    _sellCtrl.dispose();
    super.dispose();
  }

  String _fmtMarginValue(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();

  int _safeComputePrice(String anchor, String type, double marginValue) {
    try {
      return computeCategoryPrice(
        basePrice: widget.basePrice,
        costPrice: widget.costPrice,
        marginAnchor: anchor,
        marginType: type,
        marginValue: marginValue,
      );
    } catch (_) {
      return 0;
    }
  }

  double? _safeComputeMargin(String anchor, String type, int sellPrice) {
    try {
      return computeMarginValue(
        basePrice: widget.basePrice,
        costPrice: widget.costPrice,
        sellPrice: sellPrice,
        marginAnchor: anchor,
        marginType: type,
      );
    } catch (_) {
      return null;
    }
  }

  void _onMarginChanged(String raw) {
    if (_syncing) return;
    final v = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
    final sell = _safeComputePrice(_anchor, _type, v);
    _syncing = true;
    _sellCtrl.text = sell > 0 ? sell.toString() : '';
    _syncing = false;
    setState(() {});
  }

  void _onSellChanged(String raw) {
    if (_syncing) return;
    final sell = ThousandsSeparatorFormatter.parseValue(raw);
    final margin = _safeComputeMargin(_anchor, _type, sell);
    if (margin == null) return;
    _syncing = true;
    _marginCtrl.text = margin == 0 ? '' : _fmtMarginValue(margin);
    _syncing = false;
    setState(() {});
  }

  void _recomputeSellFromMargin() {
    final v = double.tryParse(_marginCtrl.text.replaceAll(',', '.')) ?? 0;
    final sell = _safeComputePrice(_anchor, _type, v);
    _sellCtrl.text = sell > 0 ? sell.toString() : '';
  }

  Future<void> _save() async {
    final marginValue = double.tryParse(_marginCtrl.text.replaceAll(',', '.'));
    if (marginValue == null) return;
    final computed = _safeComputePrice(_anchor, _type, marginValue);
    if (computed <= 0) return;
    await ref.read(databaseProvider).setPriceCategoryMargin(
          priceCategoryId: widget.categoryId,
          productUnitId: widget.productUnitId,
          categoryName: widget.categoryName,
          marginAnchor: _anchor,
          marginType: _type,
          marginValue: marginValue,
          computedPrice: computed,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.productName} · ${widget.unitName}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Harga Dasar ${formatRupiah(widget.basePrice)} · '
            'Harga Modal ${_modalAllowed ? formatRupiah(widget.costPrice) : "belum diisi"}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text('Acuan', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              const ButtonSegment(
                  value: kMarginAnchorDasar, label: Text('Harga Dasar')),
              ButtonSegment(
                value: kMarginAnchorModal,
                label: const Text('Harga Modal'),
                enabled: _modalAllowed,
              ),
            ],
            selected: {_anchor},
            showSelectedIcon: false,
            onSelectionChanged: (sel) {
              setState(() => _anchor = sel.first);
              _recomputeSellFromMargin();
            },
          ),
          if (!_modalAllowed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Harga Modal (HPP) belum diisi untuk produk ini — pakai '
                'Harga Dasar, atau isi HPP dulu di form Produk.',
                style: TextStyle(fontSize: 11, color: scheme.error),
              ),
            ),
          const SizedBox(height: 16),
          Text('Jenis Margin', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: kMarginTypeFixed, label: Text('Rupiah')),
              ButtonSegment(value: kMarginTypePercent, label: Text('Persen')),
            ],
            selected: {_type},
            showSelectedIcon: false,
            onSelectionChanged: (sel) {
              setState(() => _type = sel.first);
              _recomputeSellFromMargin();
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _marginCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]')),
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Margin',
                    prefixText: _type == kMarginTypeFixed ? 'Rp ' : null,
                    suffixText: _type == kMarginTypePercent ? '%' : null,
                  ),
                  onChanged: _onMarginChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _sellCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsSeparatorFormatter()],
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Harga Jual',
                    prefixText: 'Rp ',
                  ),
                  onChanged: _onSellChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Pemilih produk+satuan ─────────────────────────

typedef _PickedUnit = ({
  String productUnitId,
  String productName,
  String unitName,
  int basePrice,
  int costPrice,
});

/// Cari produk lalu pilih satuannya — mirip pola pencarian di
/// `CategoryAssignProductsScreen`, tapi hasil akhirnya memilih SATU
/// productUnitId (AltPrices/harga kategori di-key per satuan, bukan per
/// produk) alih-alih toggle keanggotaan massal.
class _ProductUnitPickerScreen extends ConsumerStatefulWidget {
  const _ProductUnitPickerScreen();

  @override
  ConsumerState<_ProductUnitPickerScreen> createState() =>
      _ProductUnitPickerScreenState();
}

class _ProductUnitPickerScreenState
    extends ConsumerState<_ProductUnitPickerScreen> {
  final _searchCtrl = TextEditingController();
  List<Product> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    final db = ref.read(databaseProvider);
    final results = await db.searchProducts(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  Future<void> _pick(Product p) async {
    final db = ref.read(databaseProvider);
    final units = await db.getProductUnits(p.id);
    if (units.isEmpty || !mounted) return;
    ProductUnit unit;
    if (units.length == 1) {
      unit = units.first;
    } else {
      final selected = await showModalBottomSheet<ProductUnit>(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Pilih satuan — ${p.name}',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final u in units)
                ListTile(
                  title: FutureBuilder<UnitType?>(
                    future: (db.select(db.unitTypes)
                          ..where((t) => t.id.equals(u.unitTypeId ?? 1)))
                        .getSingleOrNull(),
                    builder: (_, snap) => Text(snap.data?.name ?? 'Satuan'),
                  ),
                  onTap: () => Navigator.of(context).pop(u),
                ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;
      unit = selected;
    }

    final unitType = await (db.select(db.unitTypes)
          ..where((t) => t.id.equals(unit.unitTypeId ?? 1)))
        .getSingleOrNull();
    final tiers = await db.getPriceTiers(unit.id);
    final base = tiers.isEmpty
        ? null
        : tiers.firstWhere((t) => t.minQty <= 1, orElse: () => tiers.last);
    if (!mounted) return;
    Navigator.of(context).pop((
      productUnitId: unit.id,
      productName: p.name,
      unitName: unitType?.name ?? 'Satuan',
      basePrice: base?.price ?? 0,
      costPrice: base?.costPrice ?? 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Produk')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Cari produk…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) {
                setState(() => _loading = true);
                _load(v.trim());
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Text('Tidak ada produk ditemukan',
                            style:
                                TextStyle(color: scheme.onSurfaceVariant)),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final p = _results[i];
                          return ListTile(
                            title: Text(p.name),
                            subtitle: p.kodeProduk != null
                                ? Text('Kode: ${p.kodeProduk}')
                                : null,
                            onTap: () => _pick(p),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
