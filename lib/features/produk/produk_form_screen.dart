import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';

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

  List<_UnitEntry> _units = [];
  List<ProductGroup> _groups = [];
  List<UnitType> _unitTypes = [];
  int? _selectedGroupId;
  String? _productId;

  @override
  void initState() {
    super.initState();
    _productId = widget.productId == 'baru' ? null : widget.productId;
    _isEdit = _productId != null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
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
        final basePrice = tiers.isNotEmpty
            ? tiers.lastWhere((t) => t.minQty == 1,
                orElse: () => tiers.last)
            : null;
        entries.add(_UnitEntry(
          id: u.id,
          unitTypeId: u.unitTypeId ?? 1,
          isBaseUnit: u.isBaseUnit,
          ratioToBase: u.ratioToBase,
          price: basePrice?.price ?? 0,
          costPrice: basePrice?.costPrice ?? 0,
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
          PriceTiersCompanion.insert(
            id: _uuid.v4(),
            productUnitId: u.id,
            price: u.price,
            costPrice: Value(u.costPrice),
            createdAt: Value(now),
          ),
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
        title: Text(_isEdit ? 'Edit Produk' : 'Tambah Produk'),
        actions: [
          if (_isEdit)
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
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nama Produk *',
                      hintText: 'Contoh: Indomie Goreng',
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _kodeCtrl,
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
                      onChanged: (v) =>
                          setState(() => _selectedGroupId = v),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text('Satuan & Harga',
                          style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
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
                        canRemove: _units.length > 1,
                        onChanged: (updated) => setState(
                            () => _units[e.key] = updated),
                        onRemove: () => _removeUnit(e.key),
                      )),
                  const SizedBox(height: 80),
                ],
              ),
            ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: FilledButton(
          onPressed: _isLoading ? null : _save,
          child: const Text('Simpan Produk'),
        ),
      ),
    );
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

class _UnitEntry {
  _UnitEntry({
    required this.id,
    required this.unitTypeId,
    required this.isBaseUnit,
    required this.ratioToBase,
    required this.price,
    required this.costPrice,
    this.barcode,
  });

  final String id;
  int unitTypeId;
  bool isBaseUnit;
  double ratioToBase;
  int price;
  int costPrice;
  String? barcode;

  _UnitEntry copyWith({
    int? unitTypeId,
    bool? isBaseUnit,
    double? ratioToBase,
    int? price,
    int? costPrice,
    String? barcode,
  }) =>
      _UnitEntry(
        id: id,
        unitTypeId: unitTypeId ?? this.unitTypeId,
        isBaseUnit: isBaseUnit ?? this.isBaseUnit,
        ratioToBase: ratioToBase ?? this.ratioToBase,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        barcode: barcode ?? this.barcode,
      );
}

class _UnitCard extends StatefulWidget {
  const _UnitCard({
    super.key,
    required this.entry,
    required this.index,
    required this.unitTypes,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final _UnitEntry entry;
  final int index;
  final List<UnitType> unitTypes;
  final bool canRemove;
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
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _ratioCtrl.dispose();
    _barcodeCtrl.dispose();
    super.dispose();
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
              onChanged: (v) {
                if (v != null) {
                  widget.onChanged(widget.entry.copyWith(unitTypeId: v));
                }
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Harga Jual (Rp)',
                      isDense: true,
                      prefixText: 'Rp ',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      widget.onChanged(
                          widget.entry.copyWith(price: int.tryParse(v) ?? 0));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _costCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Harga Pokok (Rp)',
                      isDense: true,
                      prefixText: 'Rp ',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      widget.onChanged(widget.entry
                          .copyWith(costPrice: int.tryParse(v) ?? 0));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _ratioCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Isi per Satuan',
                      isDense: true,
                      hintText: 'Contoh: 10, 40',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      final r = double.tryParse(v);
                      if (r != null) {
                        widget.onChanged(widget.entry.copyWith(ratioToBase: r));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _barcodeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Barcode',
                      isDense: true,
                    ),
                    onChanged: (v) {
                      widget.onChanged(widget.entry
                          .copyWith(barcode: v.trim().isEmpty ? null : v.trim()));
                    },
                  ),
                ),
              ],
            ),
            if (!widget.entry.isBaseUnit) ...[
              const SizedBox(height: 4),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Jadikan Satuan Dasar'),
                value: widget.entry.isBaseUnit,
                onChanged: (v) {
                  if (v == true) {
                    widget.onChanged(widget.entry.copyWith(isBaseUnit: true));
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
