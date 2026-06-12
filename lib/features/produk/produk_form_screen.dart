import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/utils/input_formatters.dart';

const _uuid = Uuid();

class ProdukFormScreen extends ConsumerStatefulWidget {
  const ProdukFormScreen({super.key, this.productId});
  final String? productId;

  @override
  ConsumerState<ProdukFormScreen> createState() => _ProdukFormScreenState();
}

class _ProdukFormScreenState extends ConsumerState<ProdukFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _kodeCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isEdit = false;
  bool _readOnly = false;

  List<_UnitEntry> _units = [];
  List<ProductGroup> _groups = [];
  List<UnitType> _unitTypes = [];
  int? _selectedGroupId;
  String? _productId;
  Stream<List<Product>>? _variantStream;

  @override
  void initState() {
    super.initState();
    _productId = widget.productId == 'baru' ? null : widget.productId;
    _isEdit = _productId != null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    if (device.deviceRole == 'kasir') {
      final allowed = await db.isPermissionEnabled('input_stok');
      if (mounted) setState(() => _readOnly = !allowed);
    }

    final groups = await db.getAllProductGroups();
    final unitTypes = await db.getAllUnitTypes();

    if (!mounted) return;
    setState(() {
      _groups = groups;
      _unitTypes = unitTypes;
    });

    if (_isEdit) {
      final product = await (db.select(db.products)
            ..where((t) => t.id.equals(_productId!)))
          .getSingleOrNull();
      if (product == null || !mounted) return;
      _nameCtrl.text = product.name;
      _kodeCtrl.text = product.kodeProduk ?? '';
      final units = await db.getProductUnits(_productId!);
      final entries = <_UnitEntry>[];
      for (final u in units) {
        final tiers = await db.getPriceTiers(u.id);
        final barcodes = await db.getProductBarcodes(u.id);
        // tiers ordered DESC minQty — base tier is the one with minQty == 1
        final baseTier = tiers.firstWhere(
          (t) => t.minQty == 1,
          orElse: () => tiers.isNotEmpty ? tiers.last : PriceTier(
            id: '', productUnitId: u.id, minQty: 1, price: 0, costPrice: 0,
            createdAt: DateTime.now(),
          ),
        );
        final extraTiers = tiers
            .where((t) => t.minQty != 1)
            .map((t) => _TierEntry(
                  id: t.id,
                  minQty: t.minQty,
                  price: t.price,
                  costPrice: t.costPrice,
                ))
            .toList()
          ..sort((a, b) => a.minQty.compareTo(b.minQty));

        entries.add(_UnitEntry(
          id: u.id,
          unitTypeId: u.unitTypeId ?? 1,
          isBaseUnit: u.isBaseUnit,
          ratioToBase: u.ratioToBase,
          price: baseTier.price,
          costPrice: baseTier.costPrice,
          extraTiers: extraTiers,
          barcode: barcodes
              .where((b) => b.isPrimary)
              .map((b) => b.barcode)
              .firstOrNull,
        ));
      }
      if (mounted) {
        setState(() {
          _selectedGroupId = product.productGroupId;
          _units = entries;
        });
      }
    } else {
      final defaultUnitTypeId = _unitTypes.isNotEmpty ? _unitTypes.first.id : 1;
      setState(() {
        _units = [
          _UnitEntry(
            id: _uuid.v4(),
            unitTypeId: defaultUnitTypeId,
            isBaseUnit: true,
            ratioToBase: 1.0,
            price: 0,
            costPrice: 0,
          ),
        ];
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_units.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan minimal 1 satuan')),
      );
      return;
    }

    // Validate extra tiers: no duplicate minQty, ratioToBase > 0.
    for (final u in _units) {
      if (u.ratioToBase <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rasio satuan harus > 0')),
        );
        return;
      }
      final minQtys = u.extraTiers.map((t) => t.minQty).toList();
      if (minQtys.toSet().length != minQtys.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Minimum qty pada tier harga tidak boleh duplikat')),
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final now = DateTime.now();
      final prodId = _productId ?? _uuid.v4();

      final productCompanion = ProductsCompanion(
        id: Value(prodId),
        name: Value(_nameCtrl.text.trim()),
        kodeProduk: Value(_kodeCtrl.text.trim().isEmpty
            ? null
            : _kodeCtrl.text.trim()),
        productGroupId: Value(_selectedGroupId),
        isActive: const Value(true),
        updatedAt: Value(now),
        createdAt: _isEdit ? const Value.absent() : Value(now),
      );

      final unitCompanions = _units.map((u) => ProductUnitsCompanion(
            id: Value(u.id),
            productId: Value(prodId),
            unitTypeId: Value(u.unitTypeId),
            isBaseUnit: Value(u.isBaseUnit),
            ratioToBase: Value(u.ratioToBase),
            isNonStock: const Value(false),
          )).toList();

      final tiers = <String, List<PriceTiersCompanion>>{};
      for (final u in _units) {
        tiers[u.id] = [
          // Base price (minQty defaults to 1)
          PriceTiersCompanion.insert(
            id: _uuid.v4(),
            productUnitId: u.id,
            price: u.price,
            costPrice: Value(u.costPrice),
            createdAt: Value(now),
          ),
          // Grosir tiers
          ...u.extraTiers.map((t) => PriceTiersCompanion.insert(
                id: _uuid.v4(),
                productUnitId: u.id,
                minQty: Value(t.minQty),
                price: t.price,
                costPrice: Value(t.costPrice),
                createdAt: Value(now),
              )),
        ];
      }

      final barcodes = <String, List<ProductBarcodesCompanion>>{};
      for (final u in _units) {
        if (u.barcode != null && u.barcode!.isNotEmpty) {
          barcodes[u.id] = [
            ProductBarcodesCompanion.insert(
              id: _uuid.v4(),
              productUnitId: u.id,
              barcode: u.barcode!,
              isPrimary: const Value(true),
              isGenerated: const Value(false),
            ),
          ];
        }
      }

      await db.saveProduct(
        product: productCompanion,
        units: unitCompanions,
        tiersByUnitTempId: tiers,
        barcodesByUnitTempId: barcodes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEdit ? 'Produk diperbarui' : 'Produk disimpan')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addUnit() {
    final defaultUnitTypeId = _unitTypes.isNotEmpty ? _unitTypes.first.id : 1;
    setState(() {
      _units.add(_UnitEntry(
        id: _uuid.v4(),
        unitTypeId: defaultUnitTypeId,
        isBaseUnit: false,
        ratioToBase: 1.0,
        price: 0,
        costPrice: 0,
      ));
    });
  }

  void _removeUnit(int index) {
    if (_units.length <= 1) return;
    setState(() => _units.removeAt(index));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _kodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit
            ? (_readOnly ? 'Detail Produk' : 'Edit Produk')
            : 'Tambah Produk'),
        actions: [
          if (_isEdit && !_readOnly)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Nonaktifkan',
              onPressed: _confirmDeactivate,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_readOnly)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mode baca — izin Input Stok belum aktif',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextFormField(
                    controller: _nameCtrl,
                    readOnly: _readOnly,
                    decoration: const InputDecoration(
                      labelText: 'Nama Produk *',
                      hintText: 'Contoh: Indomie Goreng',
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => _readOnly
                        ? null
                        : (v == null || v.trim().isEmpty
                            ? 'Nama wajib diisi'
                            : null),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _kodeCtrl,
                    readOnly: _readOnly,
                    decoration: const InputDecoration(
                      labelText: 'Kode Produk',
                      hintText: 'Contoh: IMI-001 (opsional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_groups.where((g) => g.name != null).isNotEmpty)
                    DropdownButtonFormField<int?>(
                      value: _selectedGroupId,
                      decoration: const InputDecoration(labelText: 'Kategori'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Tanpa Kategori')),
                        ..._groups
                            .where((g) => g.name != null)
                            .map((g) => DropdownMenuItem(
                                  value: g.id,
                                  child: Text(g.name!),
                                )),
                      ],
                      onChanged: _readOnly
                          ? null
                          : (v) => setState(() => _selectedGroupId = v),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text('Satuan & Harga',
                          style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      if (!_readOnly)
                        TextButton.icon(
                          onPressed: _addUnit,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Tambah Satuan'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._units.asMap().entries.map((e) => _UnitCard(
                        key: ValueKey(e.value.id),
                        entry: e.value,
                        index: e.key,
                        unitTypes: _unitTypes,
                        canRemove: !_readOnly && _units.length > 1,
                        readOnly: _readOnly,
                        onChanged: _readOnly
                            ? (_) {}
                            : (updated) =>
                                setState(() => _units[e.key] = updated),
                        onRemove: () => _removeUnit(e.key),
                      )),

                  // ── Varian (produk anak / add-on) ────────────────────
                  if (_isEdit && _productId != null) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text('Varian',
                            style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        if (!_readOnly)
                          TextButton.icon(
                            onPressed: _addVariant,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Tambah Varian'),
                          ),
                      ],
                    ),
                    Text(
                      'Sub-item seperti rasa / tipe (mis. Pop Ice → Coklat). '
                      'Muncul saat tap produk di kasir & bersarang di struk.',
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<List<Product>>(
                      stream: _variantStream ??= ref
                          .read(databaseProvider)
                          .watchVariants(_productId!),
                      builder: (ctx, snap) {
                        final vs = snap.data ?? const <Product>[];
                        if (vs.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text('Belum ada varian.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                          );
                        }
                        return Column(
                          children: vs
                              .map((v) => Card(
                                    margin:
                                        const EdgeInsets.only(bottom: 6),
                                    child: ListTile(
                                      dense: true,
                                      leading: const Icon(
                                          Icons.subdirectory_arrow_right,
                                          size: 18),
                                      title: Text(v.name),
                                      subtitle: v.kodeProduk != null
                                          ? Text('Kode: ${v.kodeProduk}',
                                              style: const TextStyle(
                                                  fontSize: 11))
                                          : null,
                                      trailing: _readOnly
                                          ? null
                                          : IconButton(
                                              icon: Icon(
                                                  Icons.delete_outline,
                                                  size: 20,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error),
                                              onPressed: () =>
                                                  _deleteVariant(v),
                                            ),
                                    ),
                                  ))
                              .toList(),
                        );
                      },
                    ),
                  ],
                  if (_isEdit == false)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Simpan produk dulu untuk menambahkan varian.',
                        style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                    ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
      bottomNavigationBar: _readOnly
          ? null
          : Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
              child: FilledButton(
                onPressed: _isLoading ? null : _save,
                child: const Text('Simpan Produk'),
              ),
            ),
    );
  }

  Future<void> _addVariant() async {
    final base = _units.firstWhere((u) => u.isBaseUnit,
        orElse: () => _units.isNotEmpty
            ? _units.first
            : _UnitEntry(
                id: '',
                unitTypeId: 1,
                isBaseUnit: true,
                ratioToBase: 1,
                price: 0,
                costPrice: 0));
    final nameCtrl = TextEditingController();
    // Harga default mengikuti induk.
    final priceCtrl = TextEditingController(
        text: ThousandsSeparatorFormatter.format(base.price));
    final barcodeCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Varian'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Nama Varian *', hintText: 'Contoh: Coklat'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: const [ThousandsSeparatorFormatter()],
              decoration: const InputDecoration(
                  labelText: 'Harga', prefixText: 'Rp '),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: barcodeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Barcode (opsional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseProvider);
    await db.createVariant(
      parentProductId: _productId!,
      name: nameCtrl.text.trim(),
      price: ThousandsSeparatorFormatter.parseValue(priceCtrl.text),
      costPrice: base.costPrice,
      unitTypeId: base.unitTypeId,
      barcode: barcodeCtrl.text.trim().isEmpty
          ? null
          : barcodeCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Varian "${nameCtrl.text.trim()}" ditambahkan')),
      );
    }
  }

  Future<void> _deleteVariant(Product v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Varian'),
        content: Text('Hapus varian "${v.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(databaseProvider).deleteVariant(v.id);
  }

  Future<void> _confirmDeactivate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nonaktifkan Produk?'),
        content: const Text(
            'Produk tidak akan muncul di katalog kasir. Data tetap tersimpan.'),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => ctx.pop(true),
              child: const Text('Nonaktifkan')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(databaseProvider).deactivateProduct(_productId!);
      if (mounted) context.pop();
    }
  }
}

// ─── Data classes ────────────────────────────────────────────────────────────

class _TierEntry {
  _TierEntry({
    required this.id,
    required this.minQty,
    required this.price,
    required this.costPrice,
  });

  final String id;
  int minQty;
  int price;
  int costPrice;
}

class _UnitEntry {
  _UnitEntry({
    required this.id,
    required this.unitTypeId,
    required this.isBaseUnit,
    required this.ratioToBase,
    required this.price,
    required this.costPrice,
    List<_TierEntry>? extraTiers,
    this.barcode,
  }) : extraTiers = extraTiers ?? [];

  final String id;
  int unitTypeId;
  bool isBaseUnit;
  double ratioToBase;
  int price;
  int costPrice;
  List<_TierEntry> extraTiers;
  String? barcode;

  _UnitEntry copyWith({
    int? unitTypeId,
    bool? isBaseUnit,
    double? ratioToBase,
    int? price,
    int? costPrice,
    List<_TierEntry>? extraTiers,
    String? barcode,
  }) =>
      _UnitEntry(
        id: id,
        unitTypeId: unitTypeId ?? this.unitTypeId,
        isBaseUnit: isBaseUnit ?? this.isBaseUnit,
        ratioToBase: ratioToBase ?? this.ratioToBase,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        extraTiers: extraTiers ?? this.extraTiers,
        barcode: barcode ?? this.barcode,
      );
}

// ─── Unit Card ───────────────────────────────────────────────────────────────

class _UnitCard extends StatefulWidget {
  const _UnitCard({
    super.key,
    required this.entry,
    required this.index,
    required this.unitTypes,
    required this.canRemove,
    required this.readOnly,
    required this.onChanged,
    required this.onRemove,
  });

  final _UnitEntry entry;
  final int index;
  final List<UnitType> unitTypes;
  final bool canRemove;
  final bool readOnly;
  final ValueChanged<_UnitEntry> onChanged;
  final VoidCallback onRemove;

  @override
  State<_UnitCard> createState() => _UnitCardState();
}

class _UnitCardState extends State<_UnitCard> {
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _ratioCtrl;
  late final TextEditingController _barcodeCtrl;

  late List<_TierEntry> _extraTiers;
  late List<TextEditingController> _tierMinCtrl;
  late List<TextEditingController> _tierPriceCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
        text: widget.entry.price > 0 ? widget.entry.price.toString() : '');
    _costCtrl = TextEditingController(
        text: widget.entry.costPrice > 0
            ? widget.entry.costPrice.toString()
            : '');
    _ratioCtrl = TextEditingController(
        text: widget.entry.ratioToBase != 1.0
            ? widget.entry.ratioToBase.toString()
            : '1');
    _barcodeCtrl =
        TextEditingController(text: widget.entry.barcode ?? '');

    _extraTiers = List.from(widget.entry.extraTiers);
    _tierMinCtrl = _extraTiers
        .map((t) => TextEditingController(text: t.minQty.toString()))
        .toList();
    _tierPriceCtrl = _extraTiers
        .map((t) => TextEditingController(
            text: t.price > 0 ? t.price.toString() : ''))
        .toList();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _ratioCtrl.dispose();
    _barcodeCtrl.dispose();
    for (final c in _tierMinCtrl) {
      c.dispose();
    }
    for (final c in _tierPriceCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  void _addTier() {
    final newTier = _TierEntry(
      id: _uuid.v4(),
      minQty: _extraTiers.isNotEmpty
          ? (_extraTiers.last.minQty + 10)
          : 10,
      price: 0,
      costPrice: 0,
    );
    setState(() {
      _extraTiers.add(newTier);
      _tierMinCtrl
          .add(TextEditingController(text: newTier.minQty.toString()));
      _tierPriceCtrl.add(TextEditingController(text: ''));
    });
    widget.onChanged(widget.entry.copyWith(extraTiers: List.from(_extraTiers)));
  }

  void _removeTier(int i) {
    _tierMinCtrl[i].dispose();
    _tierPriceCtrl[i].dispose();
    setState(() {
      _extraTiers.removeAt(i);
      _tierMinCtrl.removeAt(i);
      _tierPriceCtrl.removeAt(i);
    });
    widget.onChanged(widget.entry.copyWith(extraTiers: List.from(_extraTiers)));
  }

  void _syncTier(int i) {
    final rawMin = int.tryParse(_tierMinCtrl[i].text) ?? 2;
    _extraTiers[i] = _TierEntry(
      id: _extraTiers[i].id,
      minQty: rawMin < 2 ? 2 : rawMin,
      price: int.tryParse(_tierPriceCtrl[i].text) ?? 0,
      costPrice: _extraTiers[i].costPrice,
    );
    widget.onChanged(widget.entry.copyWith(extraTiers: List.from(_extraTiers)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────────────────
            Row(
              children: [
                Text(
                  'Satuan ${widget.index + 1}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (widget.entry.isBaseUnit) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: const Text('Dasar', style: TextStyle(fontSize: 10)),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: scheme.primaryContainer,
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                  ),
                ],
                const Spacer(),
                if (widget.canRemove)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onRemove,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Unit type dropdown ───────────────────────────────────────────
            DropdownButtonFormField<int>(
              value: widget.entry.unitTypeId,
              decoration: const InputDecoration(
                  labelText: 'Jenis Satuan', isDense: true),
              items: widget.unitTypes
                  .map((u) => DropdownMenuItem(
                        value: u.id,
                        child: Text(u.name),
                      ))
                  .toList(),
              onChanged: widget.readOnly
                  ? null
                  : (v) {
                      if (v != null) {
                        widget.onChanged(widget.entry.copyWith(unitTypeId: v));
                      }
                    },
            ),
            const SizedBox(height: 8),

            // ── Base price row ───────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceCtrl,
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      labelText: 'Harga Jual (Rp)',
                      isDense: true,
                      prefixText: 'Rp ',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: widget.readOnly
                        ? null
                        : (v) {
                            widget.onChanged(widget.entry
                                .copyWith(price: int.tryParse(v) ?? 0));
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _costCtrl,
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      labelText: 'Harga Pokok (Rp)',
                      isDense: true,
                      prefixText: 'Rp ',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: widget.readOnly
                        ? null
                        : (v) {
                            widget.onChanged(widget.entry
                                .copyWith(costPrice: int.tryParse(v) ?? 0));
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Ratio & barcode row ──────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _ratioCtrl,
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      labelText: 'Isi per Satuan',
                      isDense: true,
                      hintText: 'Contoh: 10, 40',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: widget.readOnly
                        ? null
                        : (v) {
                            final r = double.tryParse(v);
                            if (r != null) {
                              widget.onChanged(
                                  widget.entry.copyWith(ratioToBase: r));
                            }
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _barcodeCtrl,
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      labelText: 'Barcode',
                      isDense: true,
                    ),
                    onChanged: widget.readOnly
                        ? null
                        : (v) {
                            widget.onChanged(widget.entry.copyWith(
                                barcode:
                                    v.trim().isEmpty ? null : v.trim()));
                          },
                  ),
                ),
              ],
            ),

            // ── Grosir tiers ─────────────────────────────────────────────────
            if (_extraTiers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Harga Grosir',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < _extraTiers.length; i++) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 76,
                      child: TextFormField(
                        controller: _tierMinCtrl[i],
                        readOnly: widget.readOnly,
                        decoration: const InputDecoration(
                          labelText: '≥ Qty',
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        onChanged: widget.readOnly
                            ? null
                            : (_) => _syncTier(i),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _tierPriceCtrl[i],
                        readOnly: widget.readOnly,
                        decoration: const InputDecoration(
                          labelText: 'Harga Grosir',
                          isDense: true,
                          prefixText: 'Rp ',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        onChanged: widget.readOnly
                            ? null
                            : (_) => _syncTier(i),
                      ),
                    ),
                    if (!widget.readOnly) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.remove_circle_outline,
                            size: 18, color: scheme.error),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _removeTier(i),
                        tooltip: 'Hapus tier',
                      ),
                    ],
                  ],
                ),
              ],
            ],

            if (!widget.readOnly) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _addTier,
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Tambah Harga Grosir'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],

            // ── Base unit toggle ─────────────────────────────────────────────
            if (!widget.entry.isBaseUnit) ...[
              const SizedBox(height: 4),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Jadikan Satuan Dasar'),
                value: widget.entry.isBaseUnit,
                onChanged: widget.readOnly
                    ? null
                    : (v) {
                        if (v == true) {
                          widget.onChanged(
                              widget.entry.copyWith(isBaseUnit: true));
                        }
                      },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
