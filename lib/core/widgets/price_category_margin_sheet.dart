import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../providers/device_provider.dart';
import '../theme/app_theme.dart' show formatRupiah;
import '../utils/input_formatters.dart';
import '../utils/price_category_calc.dart';

/// Hasil editor margin — dipakai baik dari layar Kategori Harga
/// (`kategori_harga_screen.dart`, langsung menulis via `setPriceCategoryMargin`)
/// maupun dari jalur "assign ke Kategori Harga" di Edit Produk
/// (`produk_form_screen.dart`, ditahan di state lokal sampai form disimpan —
/// pola sama seperti Harga Lain manual).
typedef PriceCategoryMarginResult = ({
  String marginAnchor,
  String marginType,
  double marginValue,
  int computedPrice,
});

/// Editor margin bidirectional (Fase B, keputusan desain user) — diekstrak
/// dari `kategori_harga_screen.dart` (`_MarginEditorSheet`) supaya bisa
/// dipakai ulang dari Edit Produk. Berbeda dari versi asalnya: sheet ini
/// TIDAK menulis ke DB sendiri, cuma `Navigator.pop(context, result)` —
/// pemanggil yang memutuskan mau langsung ditulis (layar Kategori Harga)
/// atau ditahan dulu di state lokal (Edit Produk).
/// - Toggle Acuan: "Harga Modal" (disabled kalau costPrice<=0) / "Harga
///   Dasar".
/// - Toggle Jenis: "Rupiah" (fixed) / "Persen".
/// - Field "Margin" DAN field "Harga Jual" saling terhubung LIVE — isi
///   salah satu, yang lain otomatis update.
class PriceCategoryMarginSheet extends StatefulWidget {
  const PriceCategoryMarginSheet({
    super.key,
    this.categoryName,
    required this.productName,
    required this.unitName,
    required this.basePrice,
    required this.costPrice,
    required this.initialAnchor,
    required this.initialType,
    required this.initialValue,
  });

  /// Null di layar Kategori Harga (nama kategori sudah jadi judul AppBar) —
  /// diisi saat dipakai dari Edit Produk supaya jelas kategori mana yang
  /// sedang dipilih.
  final String? categoryName;
  final String productName;
  final String unitName;
  final int basePrice;
  final int costPrice;
  final String initialAnchor;
  final String initialType;
  final double initialValue;

  @override
  State<PriceCategoryMarginSheet> createState() =>
      _PriceCategoryMarginSheetState();
}

class _PriceCategoryMarginSheetState extends State<PriceCategoryMarginSheet> {
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
        text: widget.initialValue == 0
            ? ''
            : _fmtMarginValue(widget.initialValue));
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

  void _save() {
    final marginValue = double.tryParse(_marginCtrl.text.replaceAll(',', '.'));
    if (marginValue == null) return;
    final computed = _safeComputePrice(_anchor, _type, marginValue);
    if (computed <= 0) return;
    Navigator.of(context).pop<PriceCategoryMarginResult>((
      marginAnchor: _anchor,
      marginType: _type,
      marginValue: marginValue,
      computedPrice: computed,
    ));
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
          if (widget.categoryName != null) ...[
            const SizedBox(height: 2),
            Text('Kategori: ${widget.categoryName}',
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.primary,
                    fontWeight: FontWeight.w600)),
          ],
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
                'Harga Modal (HPP) belum diisi untuk produk ini — '
                'pakai Harga Dasar, atau isi HPP dulu di form Produk.',
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

/// Sentinel dikembalikan `showModalBottomSheet` saat user memilih "Lepas
/// dari Kategori" pada [pickPriceCategoryForRow].
class _UnassignMarker {
  const _UnassignMarker();
}

/// Hasil lengkap alur "assign ke Kategori Harga" dari SISI PRODUK (Edit
/// Produk — baik satuan produk utama maupun varian): pilih kategori (atau
/// buat baru) lalu atur margin. TIDAK menulis apa pun ke DB — pemanggil yang
/// memutuskan (baris Harga Lain di form ditahan di state lokal sampai
/// tombol Simpan form ditekan, pola sama seperti Harga Lain manual).
typedef PriceCategoryAssignOutcome = ({
  /// true = user pilih "Lepas dari Kategori" (field lain di bawah ini null).
  bool unassign,
  String? categoryId,
  String? categoryName,
  PriceCategoryMarginResult? margin,
});

/// Alur lengkap: pilih Kategori Harga (dari daftar yang ada, atau buat baru)
/// lalu atur margin lewat [PriceCategoryMarginSheet]. Return `null` bila
/// dibatalkan di titik manapun.
///
/// [currentCategoryId] != null menampilkan opsi "Lepas dari Kategori" di
/// puncak daftar, dan bila kategori yang dipilih SAMA dengan yang sedang
/// aktif, margin sebelumnya ([currentAnchor]/[currentType]/[currentValue])
/// dipakai sbg nilai awal editor (bukan default 0%/Dasar).
Future<PriceCategoryAssignOutcome?> pickPriceCategoryForRow({
  required BuildContext context,
  required WidgetRef ref,
  required String productName,
  required String unitName,
  required int basePrice,
  required int costPrice,
  String? currentCategoryId,
  String? currentAnchor,
  String? currentType,
  double? currentValue,
}) async {
  final db = ref.read(databaseProvider);
  final cats = await db.getAllPriceCategories();
  if (!context.mounted) return null;

  final picked = await showModalBottomSheet<Object>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Pilih Kategori Harga',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
          ),
          if (currentCategoryId != null)
            ListTile(
              leading: Icon(Icons.link_off, color: Theme.of(ctx).colorScheme.error),
              title: const Text('Lepas dari Kategori'),
              onTap: () => Navigator.pop(ctx, const _UnassignMarker()),
            ),
          if (cats.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Belum ada Kategori Harga. Ketik nama baru di bawah untuk '
                'membuatnya.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in cats)
                  ListTile(
                    leading: Icon(
                      c.id == currentCategoryId
                          ? Icons.radio_button_checked
                          : Icons.sell_outlined,
                      color: c.id == currentCategoryId
                          ? Theme.of(ctx).colorScheme.primary
                          : null,
                    ),
                    title: Text(c.name),
                    onTap: () => Navigator.pop(ctx, c),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _NewCategoryField(
              onCreate: (name) => Navigator.pop(ctx, name),
            ),
          ),
        ],
      ),
    ),
  );
  if (picked == null) return null;
  if (picked is _UnassignMarker) {
    return (
      unassign: true,
      categoryId: null,
      categoryName: null,
      margin: null,
    );
  }

  PriceCategory cat;
  if (picked is String) {
    final id = await db.addPriceCategory(picked);
    cat = PriceCategory(
        id: id, name: picked, sortOrder: 0, createdAt: DateTime.now());
  } else {
    cat = picked as PriceCategory;
  }
  if (!context.mounted) return null;

  final sameCategory = cat.id == currentCategoryId;
  final margin = await showModalBottomSheet<PriceCategoryMarginResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => PriceCategoryMarginSheet(
      categoryName: cat.name,
      productName: productName,
      unitName: unitName,
      basePrice: basePrice,
      costPrice: costPrice,
      initialAnchor: sameCategory ? (currentAnchor ?? kMarginAnchorDasar) : kMarginAnchorDasar,
      initialType: sameCategory ? (currentType ?? kMarginTypePercent) : kMarginTypePercent,
      initialValue: sameCategory ? (currentValue ?? 0) : 0,
    ),
  );
  if (margin == null) return null;
  return (
    unassign: false,
    categoryId: cat.id,
    categoryName: cat.name,
    margin: margin,
  );
}

/// Field kecil "+ Kategori Baru" — ketik nama lalu tekan Enter/tombol untuk
/// membuatnya, dipakai di puncak [pickPriceCategoryForRow].
class _NewCategoryField extends StatefulWidget {
  const _NewCategoryField({required this.onCreate});
  final ValueChanged<String> onCreate;

  @override
  State<_NewCategoryField> createState() => _NewCategoryFieldState();
}

class _NewCategoryFieldState extends State<_NewCategoryField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    widget.onCreate(name);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Kategori baru',
              hintText: 'mis. Grosir, Rokok…',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          // AppTheme default `minimumSize` lebar PENUH — dalam Row tanpa
          // Expanded ini WAJIB dioverride sempit, kalau tidak infinite-width
          // constraint bikin layout crash (lihat CLAUDE.md gotcha).
          style: FilledButton.styleFrom(minimumSize: const Size(64, 36)),
          onPressed: _submit,
          child: const Text('Buat'),
        ),
      ],
    );
  }
}
