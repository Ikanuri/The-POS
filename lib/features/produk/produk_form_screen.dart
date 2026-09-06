import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/providers/product_providers.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/utils/internal_barcode.dart';
import '../../core/widgets/inline_banner.dart';
import '../../core/widgets/price_category_margin_sheet.dart';

/// Buka dialog scanner kamera untuk mengisi field barcode secara otomatis.
/// Mengembalikan nilai barcode yang ter-scan, atau null jika dibatalkan.
Future<String?> _scanBarcodeDialog(BuildContext context) async {
  String? result;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 300,
        height: 340,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
              child: Row(
                children: [
                  Text('Scan Barcode',
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(12)),
                child: MobileScanner(
                  onDetect: (capture) {
                    final barcode = capture.barcodes.firstOrNull?.rawValue;
                    if (barcode != null && barcode.isNotEmpty) {
                      result = barcode;
                      Navigator.of(ctx).pop();
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return result;
}

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
  // Item 11: ambang stok menipis (per-produk, disimpan di satuan dasar).
  final _minStockCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isEdit = false;
  bool _readOnly = false;
  bool _isDirty = false;
  bool _initialLoaded = false;

  /// Varian yang ditambahkan selama sesi edit ini. Varian tersimpan langsung
  /// ke DB saat dibuat, jadi bila pengguna membuang perubahan (Buang), varian
  /// sesi ini harus ikut diurungkan agar "data tidak terlanjur tertambah".
  final Set<String> _sessionVariantIds = {};

  void _markDirty() {
    if (_initialLoaded && !_isDirty && !_readOnly) {
      setState(() => _isDirty = true);
    }
  }

  String? _bannerMsg;
  InlineBannerType _bannerType = InlineBannerType.error;
  String? _bannerLinkText;
  VoidCallback? _bannerOnLinkTap;

  /// [linkText] + [onLinkTap] opsional: potongan pesan yang di-highlight &
  /// bisa diketuk (mis. nama produk yang barcode-nya bentrok → buka produk
  /// itu). Selalu di-set ulang tiap panggilan, termasuk ke null, supaya
  /// tautan dari pesan SEBELUMNYA tidak menempel di pesan berikutnya.
  void _showBanner(String msg,
      [InlineBannerType type = InlineBannerType.error,
      String? linkText,
      VoidCallback? onLinkTap]) {
    setState(() {
      _bannerMsg = msg;
      _bannerType = type;
      _bannerLinkText = linkText;
      _bannerOnLinkTap = onLinkTap;
    });
  }

  List<_UnitEntry> _units = [];

  /// Item 49e — id satuan yang baru saja ditambahkan lewat "Tambah Satuan"
  /// di sesi ini, dipakai utk scroll-into-view + autofocus kartunya.
  String? _justAddedUnitId;

  /// Id satuan yang sudah tersimpan di DB (saat load). Hanya satuan tersimpan
  /// yang punya stok untuk disesuaikan — satuan baru belum ada di stock_ledger.
  final Set<String> _persistedUnitIds = {};
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
      final baseUnit =
          units.where((u) => u.isBaseUnit).firstOrNull ?? units.firstOrNull;
      if (baseUnit?.minStock != null) {
        _minStockCtrl.text = baseUnit!.minStock.toString();
      }
      final entries = <_UnitEntry>[];
      for (final u in units) {
        final tiers = await db.getPriceTiers(u.id);
        final altPriceRows = await db.getAltPrices(u.id);
        final barcodes = await db.getProductBarcodes(u.id);
        // tiers ordered DESC minQty — base tier is the one with minQty == 1
        final baseTier = tiers.firstWhere(
          (t) => t.minQty == 1,
          orElse: () => tiers.isNotEmpty
              ? tiers.last
              : PriceTier(
                  id: '',
                  productUnitId: u.id,
                  minQty: 1,
                  price: 0,
                  costPrice: 0,
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

        final altPriceEntries = altPriceRows
            .map((a) => _AltPriceEntry(
                  id: a.id,
                  label: a.label,
                  price: a.price,
                  priceCategoryId: a.priceCategoryId,
                  marginAnchor: a.marginAnchor,
                  marginType: a.marginType,
                  marginValue: a.marginValue,
                ))
            .toList();

        entries.add(_UnitEntry(
          id: u.id,
          unitTypeId: u.unitTypeId ?? 1,
          isBaseUnit: u.isBaseUnit,
          ratioToBase: u.ratioToBase,
          price: baseTier.price,
          costPrice: baseTier.costPrice,
          isNonStock: u.isNonStock,
          requiresDeposit: u.requiresDeposit,
          extraTiers: extraTiers,
          altPrices: altPriceEntries,
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
          _persistedUnitIds
            ..clear()
            ..addAll(units.map((u) => u.id));
          _initialLoaded = true;
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
        _initialLoaded = true;
      });
    }
  }

  /// Dialog penyesuaian stok manual untuk satu satuan. Menulis langsung ke
  /// `stock_ledger` (terlepas dari tombol Simpan form). Mengembalikan true bila
  /// stok berubah, sehingga kartu satuan bisa menyegarkan tampilannya.
  Future<bool> _adjustStockDialog(String unitId, String unitLabel) async {
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final current = await db.currentStock(unitId);
    if (!mounted) return false;

    String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();
    final qtyCtrl = TextEditingController(text: fmt(current));
    // Field ini `autofocus` DAN sudah terisi stok sekarang, jadi begitu dialog
    // terbuka cursor berada di UJUNG angka itu — mengetik langsung MENEMPEL,
    // bukan mengganti (stok 5, ketik "12" -> "512" -> stok jadi 512; kalau
    // stok 0 jadi "012"). Angka lamanya harus dihapus manual dulu, padahal
    // "Stok saat ini" sudah tertulis di atas field. Select-all seluruh angka
    // (pola sama dgn dialog Ubah Nama Kategori) supaya ketik = ganti, tapi
    // nilai lamanya tetap kelihatan & bisa dipertahankan/dikoreksi.
    qtyCtrl.selection =
        TextSelection(baseOffset: 0, extentOffset: qtyCtrl.text.length);
    final noteCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sesuaikan Stok'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$unitLabel\nStok saat ini: ${fmt(current)}',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Stok baru',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                hintText: 'mis. opname, barang rusak',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(false), child: const Text('Batal')),
          FilledButton(
              onPressed: () => ctx.pop(true), child: const Text('Simpan')),
        ],
      ),
    );

    if (confirmed != true) return false;
    final newQty = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.'));
    if (newQty == null || newQty < 0) {
      if (mounted) _showBanner('Angka stok tidak valid');
      return false;
    }
    final delta = await db.adjustStock(
      productUnitId: unitId,
      newQty: newQty,
      kasirId: device.deviceCode,
      note: noteCtrl.text.trim().isEmpty
          ? 'Penyesuaian manual'
          : noteCtrl.text.trim(),
    );
    if (mounted) {
      _showBanner(
        'Stok disesuaikan (${delta >= 0 ? '+' : ''}${fmt(delta)})',
        InlineBannerType.success,
      );
    }
    return delta != 0;
  }

  Future<void> _save() async {
    final wasNew = !_isEdit;
    final ok = await _persistProduct();
    if (!ok) return;
    if (mounted) {
      // Varian sesi ini sudah ikut "dikomit" lewat Simpan → jangan diurungkan.
      _sessionVariantIds.clear();
      // Tandai bersih agar PopScope tidak menahan navigasi programatik ini.
      _isDirty = false;
      // Banner sukses ditampilkan di layar daftar produk setelah kembali
      // (layar ini akan ditutup, jadi banner inline di sini tak terlihat).
      context.pop(wasNew ? 'Produk disimpan' : 'Produk diperbarui');
    }
  }

  /// Simpan produk + satuan ke DB tanpa menutup layar. Mengembalikan true bila
  /// berhasil. Dipakai tombol Simpan dan alur "Tambah Varian" pada produk baru
  /// (varian butuh induk yang sudah tersimpan lebih dulu).
  Future<bool> _persistProduct() async {
    if (!_formKey.currentState!.validate()) return false;
    if (_units.isEmpty) {
      _showBanner('Tambahkan minimal 1 satuan');
      return false;
    }

    // Validate extra tiers: no duplicate minQty, ratioToBase > 0.
    for (final u in _units) {
      if (u.ratioToBase <= 0) {
        _showBanner('Rasio satuan harus > 0');
        return false;
      }
      final minQtys = u.extraTiers.map((t) => t.minQty).toList();
      if (minQtys.toSet().length != minQtys.length) {
        _showBanner('Minimum qty pada tier harga tidak boleh duplikat');
        return false;
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
        kodeProduk:
            Value(_kodeCtrl.text.trim().isEmpty ? null : _kodeCtrl.text.trim()),
        productGroupId: Value(_selectedGroupId),
        isActive: const Value(true),
        updatedAt: Value(now),
        createdAt: _isEdit ? const Value.absent() : Value(now),
      );

      final minStockVal = int.tryParse(_minStockCtrl.text.trim());
      final unitCompanions = _units
          .map((u) => ProductUnitsCompanion(
                id: Value(u.id),
                productId: Value(prodId),
                unitTypeId: Value(u.unitTypeId),
                isBaseUnit: Value(u.isBaseUnit),
                ratioToBase: Value(u.ratioToBase),
                isNonStock: Value(u.isNonStock),
                requiresDeposit: Value(u.requiresDeposit),
                // Ambang stok menipis hanya di satuan dasar (Item 11).
                minStock: Value(u.isBaseUnit ? minStockVal : null),
              ))
          .toList();

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

      final altPrices = <String, List<AltPricesCompanion>>{};
      for (final u in _units) {
        final validAlts = u.altPrices
            .where((a) => a.label.trim().isNotEmpty && a.price > 0)
            .toList();
        altPrices[u.id] = [
          for (var i = 0; i < validAlts.length; i++)
            AltPricesCompanion.insert(
              id: _uuid.v4(),
              productUnitId: u.id,
              label: validAlts[i].label.trim(),
              price: validAlts[i].price,
              createdAt: Value(now),
              // Posisi baris di form saat simpan — hasil drag-reorder user.
              sortOrder: Value(i),
              priceCategoryId: Value(validAlts[i].priceCategoryId),
              marginAnchor: Value(validAlts[i].marginAnchor),
              marginType: Value(validAlts[i].marginType),
              marginValue: Value(validAlts[i].marginValue),
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
        altPricesByUnitTempId: altPrices,
      );

      // Item 40 — tandai "usulan harga/produk" HANYA di device non-owner
      // (owner adalah sumber kebenaran, tidak perlu mengusulkan ke diri
      // sendiri). Dikirim ke owner via sync LAN utk direview manual.
      if (!ref.read(deviceProvider).isOwner) {
        await db.markProductLocallyModified(prodId);
      }

      // Invalidate catalog detail cache (price tiers don't trigger watchProducts).
      ref.read(productUpdateCountProvider.notifier).state++;

      if (mounted) {
        // Produk kini tersimpan: pindah ke mode edit di tempat agar bagian
        // Varian (yang butuh induk tersimpan) langsung bisa dipakai, dan satuan
        // baru bisa disesuaikan stoknya.
        setState(() {
          _productId = prodId;
          _isEdit = true;
          _persistedUnitIds
            ..clear()
            ..addAll(_units.map((u) => u.id));
        });
      }
      return true;
    } on BarcodeConflictException catch (e) {
      // Pesannya sudah ramah & menyebut produk pemegang barcode-nya, jadi
      // tampilkan apa adanya (jangan dibungkus "Error: ..."). Seluruh
      // transaksi saveProduct sudah ter-rollback — tidak ada produk
      // setengah tersimpan, dan barcode produk lain TIDAK tersentuh.
      //
      // Nama produknya dijadikan tautan: ketuk → buka produk itu (di-PUSH
      // di atas form ini, jadi isian form yang belum tersimpan TETAP utuh
      // saat kembali). Alur yang dituju: ketuk nama → bebaskan/ganti
      // barcode di produk itu → kembali → simpan lagi.
      if (mounted) {
        _showBanner(
          e.toString(),
          InlineBannerType.error,
          e.productName,
          () {
            // Tutup banner dulu: kalau user membebaskan barcode di produk
            // tujuan lalu kembali, pesan lama sudah tidak berlaku.
            setState(() => _bannerMsg = null);
            context.push('/produk/${e.productId}');
          },
        );
      }
      return false;
    } catch (e) {
      if (mounted) _showBanner('Error: $e');
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addUnit() {
    final defaultUnitTypeId = _unitTypes.isNotEmpty ? _unitTypes.first.id : 1;
    final newId = _uuid.v4();
    setState(() {
      _units.add(_UnitEntry(
        id: newId,
        unitTypeId: defaultUnitTypeId,
        isBaseUnit: false,
        ratioToBase: 1.0,
        price: 0,
        costPrice: 0,
      ));
      // Item 49e — tandai kartu ini utk scroll-into-view + autofocus di
      // _UnitCard.initState (jalan sekali, cuma utk kartu yg baru dibuat).
      _justAddedUnitId = newId;
    });
    _markDirty();
  }

  void _removeUnit(int index) {
    if (_units.length <= 1) return;
    setState(() => _units.removeAt(index));
    _markDirty();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _kodeCtrl.dispose();
    _minStockCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final hasVariantAdds = _sessionVariantIds.isNotEmpty;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Buang perubahan?'),
            content: Text(hasVariantAdds
                ? 'Perubahan yang belum disimpan akan hilang, termasuk '
                    '${_sessionVariantIds.length} varian yang baru ditambahkan.'
                : 'Perubahan yang belum disimpan akan hilang.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Kembali'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Buang'),
              ),
            ],
          ),
        );
        if (leave == true) {
          // Urungkan varian yang ditambah selama sesi ini sebelum keluar.
          await _discardSessionVariants();
          if (context.mounted) context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit
              ? (_readOnly ? 'Detail Produk' : 'Edit Produk')
              : 'Tambah Produk'),
          actions: [
            if (_isEdit)
              IconButton(
                icon: const Icon(Icons.qr_code_2_outlined),
                tooltip: 'Barcode & Cetak Label',
                onPressed: () =>
                    context.push('/produk/$_productId/barcode'),
              ),
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
            : Column(
                children: [
                  InlineBanner(
                    message: _bannerMsg,
                    type: _bannerType,
                    linkText: _bannerLinkText,
                    onLinkTap: _bannerOnLinkTap,
                    onDismiss: () => setState(() => _bannerMsg = null),
                  ),
                  Expanded(
                    child: Form(
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
                            onChanged: (_) => _markDirty(),
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
                            onChanged: (_) => _markDirty(),
                            decoration: const InputDecoration(
                              labelText: 'Kode Produk',
                              hintText: 'Contoh: IMI-001 (opsional)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Item 11: ambang stok menipis (satuan dasar).
                          TextFormField(
                            controller: _minStockCtrl,
                            readOnly: _readOnly,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _markDirty(),
                            decoration: const InputDecoration(
                              labelText: 'Stok Minimum',
                              hintText: 'Kosongkan bila tidak dipantau',
                              helperText:
                                  'Peringatan muncul bila stok satuan dasar '
                                  'di bawah angka ini',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int?>(
                            // Guard: bila kategori terpilih sudah dihapus di layar
                            // lain, jatuhkan ke null agar dropdown tidak crash
                            // (assert "exactly one item with value").
                            value: _groups.any((g) =>
                                    g.name != null && g.id == _selectedGroupId)
                                ? _selectedGroupId
                                : null,
                            decoration:
                                const InputDecoration(labelText: 'Kategori'),
                            items: [
                              const DropdownMenuItem(
                                  value: null, child: Text('Tanpa Kategori')),
                              ..._groups
                                  .where((g) => g.name != null)
                                  .map((g) => DropdownMenuItem(
                                        value: g.id,
                                        child: Text(g.name!),
                                      )),
                              DropdownMenuItem(
                                value: -1,
                                child: Row(children: [
                                  Icon(Icons.add,
                                      size: 16,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                  const SizedBox(width: 6),
                                  Text('+ Tambah Kategori Baru…',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary)),
                                ]),
                              ),
                            ],
                            onChanged: _readOnly
                                ? null
                                : (v) async {
                                    if (v == -1) {
                                      await context.push('/produk/kategori');
                                      final fresh = await ref
                                          .read(databaseProvider)
                                          .getAllProductGroups();
                                      if (mounted) {
                                        setState(() => _groups = fresh);
                                      }
                                      return;
                                    }
                                    setState(() => _selectedGroupId = v);
                                    _markDirty();
                                  },
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Text('Satuan & Harga',
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
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
                          // Item 49e — dibungkus Column (bukan spread biasa
                          // ke ListView) supaya SEMUA kartu satuan ter-build
                          // langsung, bukan lazy-windowed per-item oleh
                          // sliver ListView terluar (daftar ini kecil &
                          // terbatas — bukan skenario yg butuh virtualisasi,
                          // & lazy per-item bikin kartu yg baru ditambah tak
                          // bisa di-scroll-into-view krn Element-nya belum
                          // pernah dibuat).
                          Column(
                            children: _units.asMap().entries.map((e) {
                              final unitId = e.value.id;
                              final showStock =
                                  _persistedUnitIds.contains(unitId);
                              final unitLabel = _unitTypes
                                      .where((t) => t.id == e.value.unitTypeId)
                                      .map((t) => t.name)
                                      .firstOrNull ??
                                  'Satuan ${e.key + 1}';
                              return _UnitCard(
                                key: ValueKey(unitId),
                                entry: e.value,
                                index: e.key,
                                unitTypes: _unitTypes,
                                productName: _nameCtrl.text.trim().isEmpty
                                    ? 'Produk'
                                    : _nameCtrl.text.trim(),
                                unitLabel: unitLabel,
                                canRemove: !_readOnly && _units.length > 1,
                                readOnly: _readOnly,
                                showStock: showStock,
                                canAdjustStock: showStock && !_readOnly,
                                loadStock: showStock
                                    ? () => ref
                                        .read(databaseProvider)
                                        .currentStock(unitId)
                                    : null,
                                onAdjustStock: () =>
                                    _adjustStockDialog(unitId, unitLabel),
                                autofocusFirstField: unitId == _justAddedUnitId,
                                onGenerateBarcode: _readOnly
                                    ? null
                                    : () => generateInternalBarcode(
                                        ref.read(databaseProvider)),
                                onChanged: _readOnly
                                    ? (_) {}
                                    : (updated) {
                                        setState(() {
                                          _units[e.key] = updated;
                                          // Satuan dasar wajib TUNGGAL: begitu
                                          // satu unit dijadikan dasar, lepaskan
                                          // flag dasar dari unit lain. Tanpa ini
                                          // flag lama tak pernah di-clear (checkbox
                                          // "Jadikan Satuan Dasar"-nya keburu
                                          // hilang dari tampilan) → 2 unit dasar
                                          // aktif sekaligus tersimpan ke DB.
                                          if (updated.isBaseUnit) {
                                            for (var i = 0;
                                                i < _units.length;
                                                i++) {
                                              if (i != e.key &&
                                                  _units[i].isBaseUnit) {
                                                _units[i] = _units[i].copyWith(
                                                    isBaseUnit: false);
                                              }
                                            }
                                          }
                                        });
                                        _markDirty();
                                      },
                                onRemove: () => _removeUnit(e.key),
                              );
                            }).toList(),
                          ),

                          // ── Varian (produk anak / add-on) ────────────────────
                          if (!_readOnly || _productId != null) ...[
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Text('Varian',
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
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
                            if (_productId == null)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  'Tap "Tambah Varian" untuk menyimpan produk ini lalu '
                                  'menambahkan varian.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                                ),
                              )
                            else
                              StreamBuilder<List<Product>>(
                                stream: _variantStream ??= ref
                                    .read(databaseProvider)
                                    .watchVariants(_productId!),
                                builder: (ctx, snap) {
                                  final vs = snap.data ?? const <Product>[];
                                  if (vs.isEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
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
                                              margin: const EdgeInsets.only(
                                                  bottom: 6),
                                              child: ListTile(
                                                dense: true,
                                                onTap: _readOnly
                                                    ? null
                                                    : () => _editVariant(v),
                                                leading: const Icon(
                                                    Icons
                                                        .subdirectory_arrow_right,
                                                    size: 18),
                                                title: Text(v.name),
                                                subtitle: Row(
                                                  children: [
                                                    if (v.kodeProduk != null)
                                                      Text(
                                                          'Kode: ${v.kodeProduk} · ',
                                                          style:
                                                              const TextStyle(
                                                                  fontSize:
                                                                      11)),
                                                    Expanded(
                                                      child:
                                                          _VariantStockLabel(
                                                              variantProductId:
                                                                  v.id),
                                                    ),
                                                  ],
                                                ),
                                                trailing: _readOnly
                                                    ? null
                                                    : Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          IconButton(
                                                            visualDensity:
                                                                VisualDensity
                                                                    .compact,
                                                            padding:
                                                                EdgeInsets.zero,
                                                            constraints:
                                                                const BoxConstraints(),
                                                            icon: const Icon(
                                                                Icons
                                                                    .inventory_2_outlined,
                                                                size: 19),
                                                            tooltip:
                                                                'Sesuaikan stok varian',
                                                            onPressed: () =>
                                                                _adjustVariantStock(
                                                                    v),
                                                          ),
                                                          const SizedBox(
                                                              width: 14),
                                                          IconButton(
                                                            visualDensity:
                                                                VisualDensity
                                                                    .compact,
                                                            padding:
                                                                EdgeInsets.zero,
                                                            constraints:
                                                                const BoxConstraints(),
                                                            icon: const Icon(
                                                                Icons
                                                                    .edit_outlined,
                                                                size: 19),
                                                            tooltip:
                                                                'Edit varian',
                                                            onPressed: () =>
                                                                _editVariant(v),
                                                          ),
                                                          const SizedBox(
                                                              width: 14),
                                                          IconButton(
                                                            visualDensity:
                                                                VisualDensity
                                                                    .compact,
                                                            padding:
                                                                EdgeInsets.zero,
                                                            constraints:
                                                                const BoxConstraints(),
                                                            icon: Icon(
                                                                Icons
                                                                    .delete_outline,
                                                                size: 20,
                                                                color: Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .error),
                                                            tooltip:
                                                                'Hapus varian',
                                                            onPressed: () =>
                                                                _deleteVariant(
                                                                    v),
                                                          ),
                                                        ],
                                                      ),
                                              ),
                                            ))
                                        .toList(),
                                  );
                                },
                              ),
                          ],
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                ],
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
      ),
    );
  }

  /// Dialog form varian (dipakai Tambah & Edit). Mengembalikan nilai input,
  /// atau null bila dibatalkan.
  ///
  /// Susulan (permintaan user) — Harga Lain per varian: dikelola sederhana
  /// (tanpa drag-reorder spt produk utama, urutan ikut urutan tambah) krn
  /// dialog varian memang sengaja ringkas. Baris label kosong DIABAIKAN saat
  /// disimpan (bukan error) — biar staf bisa tambah baris lalu batal isi.
  Future<
      ({
        String name,
        int price,
        String? barcode,
        bool trackStock,
        List<AltPriceInput> altPrices,
        int unitTypeId,
        double contentPerUnit,
        bool followsParentPrice,
      })?> _variantDialog({
    required String title,
    required String confirmLabel,
    String name = '',
    required int price,
    String? barcode,
    bool trackStock = false,
    List<AltPriceInput> altPrices = const [],
    required int unitTypeId,
    double contentPerUnit = 1.0,
    // Item 53 (permintaan user) — saklar "ikut harga satuan dasar". Harga
    // satuan dasar produk INDUK (`parentBasePrice`) dibutuhkan utk pratinjau
    // hasil kali (harga_induk × isi-per-satuan) saat saklar aktif.
    bool followsParentPrice = false,
    required int parentBasePrice,
    // HPP (costPrice) varian INI SENDIRI (bukan induk) — acuan 'Modal' saat
    // assign salah satu baris Harga Lain ke Kategori Harga. Dialog ini tidak
    // punya field HPP terpisah (costPrice varian ikut costPrice induk saat
    // dibuat, lihat `_addVariant`), jadi cukup nilai pra-hitung dari pemanggil.
    int costPrice = 0,
  }) async {
    final nameCtrl = TextEditingController(text: name);
    final priceCtrl =
        TextEditingController(text: ThousandsSeparatorFormatter.format(price));
    final barcodeCtrl = TextEditingController(text: barcode ?? '');
    // Susulan (permintaan user): varian ikut punya pilihan satuan (mis. Ret,
    // Dus) + isi per satuan — jangkarnya TETAP satuan dasar produk induk,
    // yang diisi di sini adalah berapa satuan dasar per satu satuan jual.
    var unitType = unitTypeId;
    final contentCtrl = TextEditingController(
        text: contentPerUnit % 1 == 0
            ? contentPerUnit.toInt().toString()
            : contentPerUnit.toString());
    var track = trackStock;
    var follow = followsParentPrice;
    final altLabelCtrls = [
      for (final a in altPrices) TextEditingController(text: a.label)
    ];
    final altPriceCtrls = [
      for (final a in altPrices)
        TextEditingController(text: ThousandsSeparatorFormatter.format(a.price))
    ];
    // Jalur "assign ke Kategori Harga" — 4 daftar paralel dgn altLabelCtrls/
    // altPriceCtrls (indeks sama), non-null berarti baris itu category-linked.
    final altCategoryIds = <String?>[for (final a in altPrices) a.priceCategoryId];
    final altAnchors = <String?>[for (final a in altPrices) a.marginAnchor];
    final altTypes = <String?>[for (final a in altPrices) a.marginType];
    final altValues = <double?>[for (final a in altPrices) a.marginValue];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
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
                  readOnly: follow,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsSeparatorFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Harga',
                    prefixText: 'Rp ',
                    helperText: follow
                        ? 'Otomatis: harga satuan dasar × isi per satuan'
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _unitTypes.any((t) => t.id == unitType)
                            ? unitType
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Jenis Satuan', isDense: true),
                        items: _unitTypes
                            .map((t) => DropdownMenuItem(
                                value: t.id, child: Text(t.name)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setDialog(() => unitType = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: contentCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Isi per Satuan',
                          isDense: true,
                          hintText: 'Contoh: 10',
                        ),
                        onChanged: (_) {
                          if (follow) {
                            setDialog(() => priceCtrl.text =
                                ThousandsSeparatorFormatter.format(
                                    _followPreviewPrice(
                                        parentBasePrice, contentCtrl.text)));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Isi = berapa satuan dasar induk dalam 1 satuan varian '
                    '(1 = sama dengan satuan dasar).',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 4),
                // Item 53 (permintaan user) — begitu dinyalakan, harga
                // satuan dasar produk INDUK (yang jenisnya jadi jangkar
                // varian ini) berubah, harga varian ikut disesuaikan
                // otomatis (dikali isi per satuan) — tidak perlu buka
                // dialog ini lagi tiap kali harga induk berubah.
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: follow,
                  onChanged: (v) => setDialog(() {
                    follow = v;
                    if (v) {
                      priceCtrl.text = ThousandsSeparatorFormatter.format(
                          _followPreviewPrice(
                              parentBasePrice, contentCtrl.text));
                    }
                  }),
                  title: const Text('Ikut harga satuan dasar',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                      'Harga varian ikut berubah otomatis kalau harga '
                      'satuan dasar produk diubah',
                      style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: barcodeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Barcode (opsional)',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner, size: 20),
                      tooltip: 'Scan barcode',
                      onPressed: () async {
                        final bc = await _scanBarcodeDialog(context);
                        if (bc != null) barcodeCtrl.text = bc;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: track,
                  onChanged: (v) => setDialog(() => track = v),
                  title: const Text('Lacak stok varian',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                      'Aktifkan bila varian punya stok terpisah',
                      style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Harga Lain (opsional)',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(height: 6),
                for (var i = 0; i < altLabelCtrls.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.sell_outlined,
                              size: 18,
                              color: altCategoryIds[i] != null
                                  ? Theme.of(ctx).colorScheme.primary
                                  : Theme.of(ctx).colorScheme.onSurfaceVariant),
                          visualDensity: VisualDensity.compact,
                          tooltip: altCategoryIds[i] != null
                              ? 'Kategori: ${altLabelCtrls[i].text}'
                              : 'Assign ke Kategori Harga',
                          onPressed: () async {
                            final currentPrice =
                                ThousandsSeparatorFormatter.parseValue(
                                    priceCtrl.text);
                            final unitName = _unitTypes
                                    .where((t) => t.id == unitType)
                                    .map((t) => t.name)
                                    .firstOrNull ??
                                'Satuan';
                            final outcome = await pickPriceCategoryForRow(
                              context: context,
                              ref: ref,
                              productName: nameCtrl.text.trim().isEmpty
                                  ? 'Varian'
                                  : nameCtrl.text.trim(),
                              unitName: unitName,
                              basePrice: currentPrice,
                              costPrice: costPrice,
                              currentCategoryId: altCategoryIds[i],
                              currentAnchor: altAnchors[i],
                              currentType: altTypes[i],
                              currentValue: altValues[i],
                            );
                            if (outcome == null) return;
                            setDialog(() {
                              if (outcome.unassign) {
                                // KEPUTUSAN: bekukan nilai terakhir (bukan
                                // dikosongkan) — pola sama dgn baris utama
                                // (lihat `_onTapCategoryIcon` di `_UnitCard`).
                                altCategoryIds[i] = null;
                                altAnchors[i] = null;
                                altTypes[i] = null;
                                altValues[i] = null;
                              } else {
                                altLabelCtrls[i].text = outcome.categoryName!;
                                altPriceCtrls[i].text =
                                    ThousandsSeparatorFormatter.format(
                                        outcome.margin!.computedPrice);
                                altCategoryIds[i] = outcome.categoryId;
                                altAnchors[i] = outcome.margin!.marginAnchor;
                                altTypes[i] = outcome.margin!.marginType;
                                altValues[i] = outcome.margin!.marginValue;
                              }
                            });
                          },
                        ),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: altLabelCtrls[i],
                            readOnly: altCategoryIds[i] != null,
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: 'Label',
                              helperText: altCategoryIds[i] != null
                                  ? 'Kategori Harga'
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: altPriceCtrls[i],
                            readOnly: altCategoryIds[i] != null,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [
                              ThousandsSeparatorFormatter()
                            ],
                            decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'Harga',
                                prefixText: 'Rp '),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setDialog(() {
                            altLabelCtrls[i].dispose();
                            altPriceCtrls[i].dispose();
                            altLabelCtrls.removeAt(i);
                            altPriceCtrls.removeAt(i);
                            altCategoryIds.removeAt(i);
                            altAnchors.removeAt(i);
                            altTypes.removeAt(i);
                            altValues.removeAt(i);
                          }),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setDialog(() {
                      altLabelCtrls.add(TextEditingController());
                      altPriceCtrls.add(TextEditingController());
                      altCategoryIds.add(null);
                      altAnchors.add(null);
                      altTypes.add(null);
                      altValues.add(null);
                    }),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Tambah Harga Lain'),
                  ),
                ),
              ],
            ),
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
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    final content =
        double.tryParse(contentCtrl.text.trim().replaceAll(',', '.'));
    return (
      name: nameCtrl.text.trim(),
      price: ThousandsSeparatorFormatter.parseValue(priceCtrl.text),
      barcode: barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
      trackStock: track,
      unitTypeId: unitType,
      // Kosong/tidak valid/<= 0 → 1 (varian dijual dalam satuan dasarnya
      // sendiri), bukan error — biar staf tidak terhalang saat tidak peduli.
      contentPerUnit: (content == null || content <= 0) ? 1.0 : content,
      followsParentPrice: follow,
      altPrices: [
        for (var i = 0; i < altLabelCtrls.length; i++)
          if (altLabelCtrls[i].text.trim().isNotEmpty)
            (
              label: altLabelCtrls[i].text.trim(),
              price: ThousandsSeparatorFormatter.parseValue(
                  altPriceCtrls[i].text),
              priceCategoryId: altCategoryIds[i],
              marginAnchor: altAnchors[i],
              marginType: altTypes[i],
              marginValue: altValues[i],
            ),
      ],
    );
  }

  /// Item 53 — pratinjau harga hasil kali "harga satuan dasar induk" ×
  /// "isi per satuan" (dipakai saat saklar "Ikut harga satuan dasar"
  /// aktif). Isi tidak valid/<=0 diperlakukan sbg 1 (persis aturan simpan).
  int _followPreviewPrice(int parentBasePrice, String contentText) {
    final content =
        double.tryParse(contentText.trim().replaceAll(',', '.'));
    final ratio = (content == null || content <= 0) ? 1.0 : content;
    return (parentBasePrice * ratio).round();
  }

  Future<void> _addVariant() async {
    // Varian butuh induk yang sudah tersimpan. Untuk produk baru, simpan dulu
    // (di tempat) lalu lanjut menambah varian.
    if (_productId == null) {
      final saved = await _persistProduct();
      if (!saved || !mounted) return;
    }
    final base =
        _units.firstWhere((u) => u.isBaseUnit, orElse: () => _units.first);
    // Harga default mengikuti induk.
    final res = await _variantDialog(
      title: 'Tambah Varian',
      confirmLabel: 'Tambah',
      price: base.price,
      unitTypeId: base.unitTypeId,
      parentBasePrice: base.price,
      // Varian baru ikut costPrice induk (lihat `createVariant`) — dipakai
      // sbg acuan 'Modal' bila salah satu baris Harga Lain di-assign ke
      // Kategori Harga.
      costPrice: base.costPrice,
    );
    if (res == null) return;
    final db = ref.read(databaseProvider);
    try {
      final variantId = await db.createVariant(
        parentProductId: _productId!,
        name: res.name,
        price: res.price,
        costPrice: base.costPrice,
        unitTypeId: res.unitTypeId,
        // Jangkar: satuan dasar varian selalu ikut satuan dasar induk —
        // baru terpakai kalau varian dijual dalam satuan lain (isi != 1).
        baseUnitTypeId: base.unitTypeId,
        contentPerUnit: res.contentPerUnit,
        followsParentPrice: res.followsParentPrice,
        barcode: res.barcode,
        isNonStock: !res.trackStock,
        altPrices: res.altPrices,
      );
      // Item 40 — usulan harga/produk dari device non-owner (lihat catatan
      // sama di _persistProduct).
      if (!ref.read(deviceProvider).isOwner) {
        await db.markProductLocallyModified(variantId);
      }
      // Lacak agar bisa diurungkan bila edit dibatalkan; tandai dirty supaya
      // dialog konfirmasi muncul saat menekan kembali.
      _sessionVariantIds.add(variantId);
      _markDirty();
      if (mounted) {
        _showBanner(
            'Varian "${res.name}" ditambahkan', InlineBannerType.success);
      }
    } catch (e) {
      // Barcode unik di seluruh katalog (tabel product_barcodes) — kalau
      // sudah dipakai produk/varian lain, insert gagal & seluruh transaksi
      // (produk+unit+tier+barcode varian) di-rollback total, TIDAK ada
      // varian tersimpan sama sekali. Sebelumnya exception ini tidak
      // ditangkap sama sekali di sini, jadi varian "hilang begitu saja"
      // tanpa pesan apa pun ke user.
      if (mounted) {
        _showBanner(_friendlyBarcodeError(e, res.barcode));
      }
    }
  }

  /// Pesan error yang jelas utk kasus barcode bentrok (paling sering
  /// terjadi), fallback ke pesan mentah utk error lain.
  String _friendlyBarcodeError(Object e, String? barcode) {
    // Bentrok yang terdeteksi eksplisit oleh DB: pesannya sudah menyebut
    // produk pemegangnya, lebih berguna dari pesan generik di bawah.
    if (e is BarcodeConflictException) return e.toString();
    final msg = e.toString();
    if (barcode != null &&
        barcode.isNotEmpty &&
        msg.contains('UNIQUE constraint failed') &&
        msg.contains('barcode')) {
      return 'Barcode "$barcode" sudah dipakai produk/varian lain — '
          'gunakan barcode berbeda atau kosongkan.';
    }
    return 'Gagal menyimpan varian: $e';
  }

  Future<void> _editVariant(Product v) async {
    final db = ref.read(databaseProvider);
    // Ambil nilai varian saat ini untuk pra-isi dialog.
    final units = await db.getProductUnits(v.id);
    // Satuan JUAL varian (lihat `AppDatabase.variantSaleUnit`) — harga,
    // barcode & Harga Lain menempel di situ, bukan di satuan dasar.
    final baseUnit = AppDatabase.variantSaleUnit(units);
    var curPrice = 0;
    String? curBarcode;
    var trackStock = false;
    var curAltPrices = const <AltPriceInput>[];
    // HPP varian INI SENDIRI (bukan induk) — acuan 'Modal' saat assign salah
    // satu baris Harga Lain ke Kategori Harga (spek: costPrice varian yg
    // relevan, bukan costPrice induk).
    var curCostPrice = 0;
    var curUnitTypeId = _units.isNotEmpty
        ? _units.firstWhere((u) => u.isBaseUnit, orElse: () => _units.first)
            .unitTypeId
        : 1;
    var curContent = 1.0;
    var curFollow = false;
    if (baseUnit != null) {
      curUnitTypeId = baseUnit.unitTypeId ?? curUnitTypeId;
      // Satuan dasar selalu rasio 1 (dan `_baseUnitOf` memang mengabaikan
      // nilai kolomnya) — hanya satuan jual non-dasar yang punya isi nyata.
      curContent = baseUnit.isBaseUnit ? 1.0 : baseUnit.ratioToBase;
      curFollow = baseUnit.followsParentPrice;
      final tiers = await db.getPriceTiers(baseUnit.id);
      final baseTier =
          tiers.where((t) => t.minQty == 1).firstOrNull ?? tiers.lastOrNull;
      curPrice = baseTier?.price ?? 0;
      curCostPrice = baseTier?.costPrice ?? 0;
      final bcs = await db.getProductBarcodes(baseUnit.id);
      curBarcode =
          bcs.where((b) => b.isPrimary).map((b) => b.barcode).firstOrNull;
      trackStock = !baseUnit.isNonStock;
      final alts = await db.getAltPrices(baseUnit.id);
      curAltPrices = [
        for (final a in alts)
          (
            label: a.label,
            price: a.price,
            priceCategoryId: a.priceCategoryId,
            marginAnchor: a.marginAnchor,
            marginType: a.marginType,
            marginValue: a.marginValue,
          ),
      ];
    }
    if (!mounted) return;
    final parentBase = _units.isNotEmpty
        ? _units.firstWhere((u) => u.isBaseUnit, orElse: () => _units.first)
            .price
        : 0;
    final res = await _variantDialog(
      title: 'Edit Varian',
      confirmLabel: 'Simpan',
      name: v.name,
      price: curPrice,
      barcode: curBarcode,
      trackStock: trackStock,
      altPrices: curAltPrices,
      unitTypeId: curUnitTypeId,
      contentPerUnit: curContent,
      followsParentPrice: curFollow,
      parentBasePrice: parentBase,
      costPrice: curCostPrice,
    );
    if (res == null) return;
    try {
      await db.updateVariant(
        variantProductId: v.id,
        name: res.name,
        price: res.price,
        barcode: res.barcode,
        isNonStock: !res.trackStock,
        altPrices: res.altPrices,
        unitTypeId: res.unitTypeId,
        contentPerUnit: res.contentPerUnit,
        followsParentPrice: res.followsParentPrice,
      );
      // Item 40 — usulan harga/produk dari device non-owner.
      if (!ref.read(deviceProvider).isOwner) {
        await db.markProductLocallyModified(v.id);
      }
      ref.read(productUpdateCountProvider.notifier).state++;
      if (mounted) {
        _showBanner(
            'Varian "${res.name}" diperbarui', InlineBannerType.success);
      }
    } catch (e) {
      if (mounted) {
        _showBanner(_friendlyBarcodeError(e, res.barcode));
      }
    }
  }

  /// Susulan (permintaan user) — "bagaimana cara atur stok varian? Masih
  /// belum ada UI-nya" — sebelumnya stok varian cuma DITAMPILKAN
  /// (`_VariantStockLabel`), tidak bisa DIUBAH sama sekali dari layar
  /// manapun. Reuse `_adjustStockDialog` (persis dialog "Sesuaikan Stok"
  /// milik satuan produk utama) — cukup butuh unitId+label, tidak
  /// bergantung ke state `_units` produk utama.
  Future<void> _adjustVariantStock(Product v) async {
    final db = ref.read(databaseProvider);
    final units = await db.getProductUnits(v.id);
    if (!mounted) return;
    if (units.isEmpty) {
      _showBanner('Varian ini belum punya satuan');
      return;
    }
    final unit = AppDatabase.variantSaleUnit(units)!;
    if (unit.isNonStock) {
      _showBanner(
          'Varian "${v.name}" tidak melacak stok (aktifkan dulu di Edit Varian)');
      return;
    }
    final adjusted = await _adjustStockDialog(unit.id, v.name);
    if (adjusted) {
      // `_VariantStockLabel` pakai FutureBuilder sekali-jalan (bukan
      // stream) — paksa rebuild list Varian spy angka stok baru langsung
      // kelihatan tanpa perlu tutup-buka layar.
      setState(() {});
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
    // Sudah dihapus manual → tak perlu diurungkan lagi saat discard.
    _sessionVariantIds.remove(v.id);
  }

  /// Hapus varian yang ditambahkan selama sesi edit ini (dipanggil saat
  /// pengguna memilih "Buang"). Varian dibuat langsung di DB, jadi tanpa ini
  /// varian akan tetap tertambah meski perubahan dibatalkan.
  Future<void> _discardSessionVariants() async {
    if (_sessionVariantIds.isEmpty) return;
    final db = ref.read(databaseProvider);
    for (final id in _sessionVariantIds) {
      await db.deleteVariant(id);
    }
    _sessionVariantIds.clear();
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
              onPressed: () => ctx.pop(false), child: const Text('Batal')),
          FilledButton(
              onPressed: () => ctx.pop(true), child: const Text('Nonaktifkan')),
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

/// Harga alternatif berlabel bebas (mis. "Harga Toko A" = 3000) — bukan
/// tier qty seperti [_TierEntry], murni pilihan cepat tap-untuk-pakai di
/// kasir (`ItemEntrySheet`).
///
/// 4 field kategori di bawah opsional (jalur "assign ke Kategori Harga"
/// langsung dari Edit Produk) — non-null berarti baris ini category-linked:
/// [label] & [price] jadi terkunci (readonly di UI, hanya berubah lewat
/// picker kategori), [price] adalah snapshot harga live-computed terakhir.
/// Null berarti baris manual biasa seperti semula, tidak berubah.
class _AltPriceEntry {
  _AltPriceEntry({
    required this.id,
    required this.label,
    required this.price,
    this.priceCategoryId,
    this.marginAnchor,
    this.marginType,
    this.marginValue,
  });

  final String id;
  String label;
  int price;
  String? priceCategoryId;
  String? marginAnchor;
  String? marginType;
  double? marginValue;

  bool get isCategoryLinked => priceCategoryId != null;
}

class _UnitEntry {
  _UnitEntry({
    required this.id,
    required this.unitTypeId,
    required this.isBaseUnit,
    required this.ratioToBase,
    required this.price,
    required this.costPrice,
    this.isNonStock = false,
    this.requiresDeposit = false,
    List<_TierEntry>? extraTiers,
    List<_AltPriceEntry>? altPrices,
    this.barcode,
  })  : extraTiers = extraTiers ?? [],
        altPrices = altPrices ?? [];

  final String id;
  int unitTypeId;
  bool isBaseUnit;
  double ratioToBase;
  int price;
  int costPrice;
  bool isNonStock;

  /// Item 52 ("Laci Meja") — produk model tukar-wadah (LPG, galon, dst):
  /// antri stok kosong WAJIB titip wadah fisik sbg jaminan.
  bool requiresDeposit;
  List<_TierEntry> extraTiers;
  List<_AltPriceEntry> altPrices;
  String? barcode;

  _UnitEntry copyWith({
    int? unitTypeId,
    bool? isBaseUnit,
    double? ratioToBase,
    int? price,
    int? costPrice,
    bool? isNonStock,
    bool? requiresDeposit,
    List<_TierEntry>? extraTiers,
    List<_AltPriceEntry>? altPrices,
    String? barcode,
  }) =>
      _UnitEntry(
        id: id,
        unitTypeId: unitTypeId ?? this.unitTypeId,
        isBaseUnit: isBaseUnit ?? this.isBaseUnit,
        ratioToBase: ratioToBase ?? this.ratioToBase,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        isNonStock: isNonStock ?? this.isNonStock,
        requiresDeposit: requiresDeposit ?? this.requiresDeposit,
        extraTiers: extraTiers ?? this.extraTiers,
        altPrices: altPrices ?? this.altPrices,
        barcode: barcode ?? this.barcode,
      );
}

// ─── Unit Card ───────────────────────────────────────────────────────────────

class _UnitCard extends ConsumerStatefulWidget {
  const _UnitCard({
    super.key,
    required this.entry,
    required this.index,
    required this.unitTypes,
    required this.canRemove,
    required this.readOnly,
    required this.onChanged,
    required this.onRemove,
    required this.productName,
    required this.unitLabel,
    this.showStock = false,
    this.canAdjustStock = false,
    this.loadStock,
    this.onAdjustStock,
    this.autofocusFirstField = false,
    this.onGenerateBarcode,
  });

  final _UnitEntry entry;
  final int index;
  final List<UnitType> unitTypes;
  final bool canRemove;
  final bool readOnly;
  final ValueChanged<_UnitEntry> onChanged;
  final VoidCallback onRemove;

  /// Nama produk & label satuan ini — dipakai judul sheet picker Kategori
  /// Harga (jalur "assign ke Kategori Harga" dari baris Harga Lain).
  final String productName;
  final String unitLabel;

  /// Item 51 — generate barcode internal (EAN-13 prefix 29) langsung dari
  /// field input, tanpa perlu ke layar Barcode terpisah.
  final Future<String> Function()? onGenerateBarcode;

  /// Tampilkan baris stok (hanya untuk satuan yang sudah tersimpan).
  final bool showStock;
  final bool canAdjustStock;
  final Future<double> Function()? loadStock;

  /// Buka dialog penyesuaian; true bila stok berubah → kartu menyegarkan.
  final Future<bool> Function()? onAdjustStock;

  /// Item 49e — true HANYA untuk kartu yang baru saja ditambahkan lewat
  /// "Tambah Satuan". `key: ValueKey(unitId)` di parent menjamin kartu ini
  /// betul-betul instance BARU (bukan rebuild kartu lama) begitu ditambahkan,
  /// jadi `initState` di bawah cuma jalan sekali persis saat kartu ini
  /// pertama kali muncul — pas dipakai utk scroll-into-view + autofocus.
  final bool autofocusFirstField;

  @override
  ConsumerState<_UnitCard> createState() => _UnitCardState();
}

class _UnitCardState extends ConsumerState<_UnitCard> {
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _ratioCtrl;
  late final TextEditingController _barcodeCtrl;

  late List<_TierEntry> _extraTiers;
  late List<TextEditingController> _tierMinCtrl;
  late List<TextEditingController> _tierPriceCtrl;

  late List<_AltPriceEntry> _altPrices;
  late List<TextEditingController> _altLabelCtrl;
  late List<TextEditingController> _altPriceCtrl;

  Future<double>? _stockFuture;

  void _refreshStock() {
    if (widget.loadStock != null) {
      setState(() => _stockFuture = widget.loadStock!());
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.loadStock != null) _stockFuture = widget.loadStock!();
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
    _barcodeCtrl = TextEditingController(text: widget.entry.barcode ?? '');

    _extraTiers = List.from(widget.entry.extraTiers);
    _tierMinCtrl = _extraTiers
        .map((t) => TextEditingController(text: t.minQty.toString()))
        .toList();
    _tierPriceCtrl = _extraTiers
        .map((t) =>
            TextEditingController(text: t.price > 0 ? t.price.toString() : ''))
        .toList();

    _altPrices = List.from(widget.entry.altPrices);
    _altLabelCtrl =
        _altPrices.map((a) => TextEditingController(text: a.label)).toList();
    _altPriceCtrl = _altPrices
        .map((a) =>
            TextEditingController(text: a.price > 0 ? a.price.toString() : ''))
        .toList();

    // Item 49e — kartu satuan baru langsung digulir ke pandangan (form bisa
    // panjang, kartu baru ada di paling bawah). Autofocus field-nya sendiri
    // dipasang lewat `autofocus:` di TextFormField terkait (lihat build()).
    if (widget.autofocusFirstField) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(context,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: 0.1);
        }
      });
    }
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
    for (final c in _altLabelCtrl) {
      c.dispose();
    }
    for (final c in _altPriceCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  void _addTier() {
    final newTier = _TierEntry(
      id: _uuid.v4(),
      minQty: _extraTiers.isNotEmpty ? (_extraTiers.last.minQty + 10) : 10,
      price: 0,
      costPrice: 0,
    );
    setState(() {
      _extraTiers.add(newTier);
      _tierMinCtrl.add(TextEditingController(text: newTier.minQty.toString()));
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

  void _addAltPrice() {
    final newAlt = _AltPriceEntry(id: _uuid.v4(), label: '', price: 0);
    setState(() {
      _altPrices.add(newAlt);
      _altLabelCtrl.add(TextEditingController());
      _altPriceCtrl.add(TextEditingController());
    });
    widget.onChanged(widget.entry.copyWith(altPrices: List.from(_altPrices)));
  }

  void _removeAltPrice(int i) {
    _altLabelCtrl[i].dispose();
    _altPriceCtrl[i].dispose();
    setState(() {
      _altPrices.removeAt(i);
      _altLabelCtrl.removeAt(i);
      _altPriceCtrl.removeAt(i);
    });
    widget.onChanged(widget.entry.copyWith(altPrices: List.from(_altPrices)));
  }

  void _syncAltPrice(int i) {
    _altPrices[i] = _AltPriceEntry(
      id: _altPrices[i].id,
      label: _altLabelCtrl[i].text,
      price: int.tryParse(_altPriceCtrl[i].text) ?? 0,
    );
    widget.onChanged(widget.entry.copyWith(altPrices: List.from(_altPrices)));
  }

  void _reorderAltPrice(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      _altPrices.insert(newIndex, _altPrices.removeAt(oldIndex));
      _altLabelCtrl.insert(newIndex, _altLabelCtrl.removeAt(oldIndex));
      _altPriceCtrl.insert(newIndex, _altPriceCtrl.removeAt(oldIndex));
    });
    widget.onChanged(widget.entry.copyWith(altPrices: List.from(_altPrices)));
  }

  /// Jalur "assign ke Kategori Harga" langsung dari baris Harga Lain satuan
  /// produk utama — ikon `Icons.sell_outlined` di tiap baris. TIDAK menulis
  /// ke DB sendiri (sama seperti Harga Lain manual): hasilnya cuma
  /// memperbarui state lokal `_altPrices`, ditulis nanti saat tombol Simpan
  /// form ditekan (lihat `saveProduct`).
  Future<void> _onTapCategoryIcon(int i) async {
    final current = _altPrices[i];
    final outcome = await pickPriceCategoryForRow(
      context: context,
      ref: ref,
      productName: widget.productName,
      unitName: widget.unitLabel,
      basePrice: widget.entry.price,
      costPrice: widget.entry.costPrice,
      currentCategoryId: current.priceCategoryId,
      currentAnchor: current.marginAnchor,
      currentType: current.marginType,
      currentValue: current.marginValue,
    );
    if (outcome == null || !mounted) return;
    setState(() {
      if (outcome.unassign) {
        // KEPUTUSAN: bekukan ke nilai live-computed TERAKHIR (bukan
        // dikosongkan) — user langsung lihat angka wajar tanpa dipaksa isi
        // ulang, konsisten dgn `deletePriceCategory` (massal) yg juga
        // membekukan, bukan menghapus/mengosongkan.
        _altPrices[i] = _AltPriceEntry(
          id: current.id,
          label: current.label,
          price: current.price,
        );
      } else {
        _altPrices[i] = _AltPriceEntry(
          id: current.id,
          label: outcome.categoryName!,
          price: outcome.margin!.computedPrice,
          priceCategoryId: outcome.categoryId,
          marginAnchor: outcome.margin!.marginAnchor,
          marginType: outcome.margin!.marginType,
          marginValue: outcome.margin!.marginValue,
        );
      }
      _altLabelCtrl[i].text = _altPrices[i].label;
      _altPriceCtrl[i].text =
          _altPrices[i].price > 0 ? _altPrices[i].price.toString() : '';
    });
    widget.onChanged(widget.entry.copyWith(altPrices: List.from(_altPrices)));
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

            // ── Stok terkini + tombol sesuaikan ──────────────────────────────
            if (widget.showStock) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text('Stok: ',
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                    FutureBuilder<double>(
                      future: _stockFuture,
                      builder: (_, snap) {
                        final s = snap.data;
                        final txt = s == null
                            ? '…'
                            : (s % 1 == 0
                                ? s.toInt().toString()
                                : s.toString());
                        return Text(txt,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700));
                      },
                    ),
                    const Spacer(),
                    if (widget.canAdjustStock)
                      TextButton.icon(
                        onPressed: () async {
                          final changed =
                              await widget.onAdjustStock?.call() ?? false;
                          if (changed) _refreshStock();
                        },
                        icon: const Icon(Icons.tune, size: 15),
                        label: const Text('Sesuaikan'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                  ],
                ),
              ),
            ],

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
                    autofocus: widget.autofocusFirstField && !widget.readOnly,
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
                    decoration: InputDecoration(
                      labelText: 'Barcode',
                      isDense: true,
                      suffixIcon: widget.readOnly
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.onGenerateBarcode != null)
                                  IconButton(
                                    icon: const Icon(Icons.qr_code_2_outlined,
                                        size: 18),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Generate barcode',
                                    onPressed: () async {
                                      final bc =
                                          await widget.onGenerateBarcode!();
                                      if (mounted) {
                                        _barcodeCtrl.text = bc;
                                        widget.onChanged(widget.entry
                                            .copyWith(barcode: bc));
                                      }
                                    },
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.qr_code_scanner,
                                      size: 18),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Scan barcode',
                                  onPressed: () async {
                                    final bc = await _scanBarcodeDialog(context);
                                    if (bc != null && mounted) {
                                      _barcodeCtrl.text = bc;
                                      widget.onChanged(
                                          widget.entry.copyWith(barcode: bc));
                                    }
                                  },
                                ),
                              ],
                            ),
                    ),
                    onChanged: widget.readOnly
                        ? null
                        : (v) {
                            widget.onChanged(widget.entry.copyWith(
                                barcode: v.trim().isEmpty ? null : v.trim()));
                          },
                  ),
                ),
              ],
            ),

            // ── Lacak stok ───────────────────────────────────────────────────
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: !widget.entry.isNonStock,
              onChanged: widget.readOnly
                  ? null
                  : (v) => widget.onChanged(
                      widget.entry.copyWith(isNonStock: !v)),
              title: const Text('Lacak stok', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                  'Matikan bila satuan ini tidak perlu dihitung stok (mis. jasa)',
                  style: TextStyle(fontSize: 11)),
            ),

            // ── Butuh Jaminan Fisik (Item 52 — Laci Meja/Pre-order) ──────────
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: widget.entry.requiresDeposit,
              onChanged: widget.readOnly
                  ? null
                  : (v) => widget.onChanged(
                      widget.entry.copyWith(requiresDeposit: v)),
              title: const Text('Butuh Jaminan Fisik saat Antri',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                  'Aktifkan utk produk tukar-wadah (mis. LPG, galon) — antri '
                  'stok kosong wajib titip wadah, bukan cuma nomor urut',
                  style: TextStyle(fontSize: 11)),
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
                        onChanged: widget.readOnly ? null : (_) => _syncTier(i),
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
                        onChanged: widget.readOnly ? null : (_) => _syncTier(i),
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

            // ── Harga alternatif berlabel ───────────────────────────────────
            if (_altPrices.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Harga Lain',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              // Drag-handle untuk reorder — cukup ditaruh di dalam Column
              // form yang sudah scrollable (SingleChildScrollView/ListView
              // ancestor), auto-scroll saat drag mendekati tepi layar
              // otomatis ditangani Flutter lewat Scrollable ancestor itu.
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _altPrices.length,
                onReorder: widget.readOnly ? (_, __) {} : _reorderAltPrice,
                itemBuilder: (context, i) {
                  final linked = _altPrices[i].isCategoryLinked;
                  return Padding(
                    key: ValueKey(_altPrices[i].id),
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (!widget.readOnly)
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(Icons.drag_handle,
                                  size: 18, color: scheme.onSurfaceVariant),
                            ),
                          ),
                        IconButton(
                          icon: Icon(Icons.sell_outlined,
                              size: 18,
                              color:
                                  linked ? scheme.primary : scheme.onSurfaceVariant),
                          visualDensity: VisualDensity.compact,
                          tooltip: linked
                              ? 'Kategori: ${_altPrices[i].label}'
                              : 'Assign ke Kategori Harga',
                          onPressed: widget.readOnly
                              ? null
                              : () => _onTapCategoryIcon(i),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: _altLabelCtrl[i],
                            readOnly: widget.readOnly || linked,
                            decoration: InputDecoration(
                              labelText: 'Nama Harga',
                              hintText: 'mis. Harga Toko A',
                              isDense: true,
                              helperText: linked ? 'Kategori Harga' : null,
                            ),
                            onChanged: widget.readOnly || linked
                                ? null
                                : (_) => _syncAltPrice(i),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 110,
                          child: TextFormField(
                            controller: _altPriceCtrl[i],
                            readOnly: widget.readOnly || linked,
                            decoration: const InputDecoration(
                              labelText: 'Nominal',
                              isDense: true,
                              prefixText: 'Rp ',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            onChanged: widget.readOnly || linked
                                ? null
                                : (_) => _syncAltPrice(i),
                          ),
                        ),
                        if (!widget.readOnly) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(Icons.remove_circle_outline,
                                size: 18, color: scheme.error),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _removeAltPrice(i),
                            tooltip: 'Hapus harga',
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],

            if (!widget.readOnly) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _addAltPrice,
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Tambah Harga Lain'),
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
                          // Satuan dasar WAJIB rasio 1.0 (basis konversi stok
                          // — `currentStock` membagi stok base dgn ratioToBase,
                          // jadi base unit ber-rasio != 1 merusak hitungan).
                          // Sinkron controller-nya juga supaya field "Isi per
                          // Satuan" langsung menampilkan 1.
                          _ratioCtrl.text = '1';
                          widget.onChanged(widget.entry
                              .copyWith(isBaseUnit: true, ratioToBase: 1.0));
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

/// Susulan (permintaan user) — status stok varian ditampilkan di Edit
/// Produk. Stok SUDAH dilacak di DB (tiap varian punya `stock_ledger`
/// sendiri via unitId-nya) sejak awal, tapi sebelumnya TIDAK PERNAH
/// ditampilkan sama sekali di mana pun — owner tidak bisa tahu varian mana
/// yang kosong tanpa cek manual ke DB.
class _VariantStockLabel extends ConsumerWidget {
  const _VariantStockLabel({required this.variantProductId});
  final String variantProductId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    return FutureBuilder<({double stock, bool isNonStock})>(
      future: () async {
        final units = await db.getProductUnits(variantProductId);
        if (units.isEmpty) return (stock: 0.0, isNonStock: true);
        // Satuan JUAL, bukan satuan dasar — stok ditampilkan dalam satuan
        // yang dipakai jual (mis. "Stok 3" renteng, bukan 30 pcs).
        final unit = AppDatabase.variantSaleUnit(units)!;
        if (unit.isNonStock) return (stock: 0.0, isNonStock: true);
        final stock = await db.currentStock(unit.id);
        return (stock: stock, isNonStock: false);
      }(),
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        if (data.isNonStock) {
          return Text('Non-stok',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant));
        }
        final habis = data.stock <= 0;
        final stockText =
            data.stock % 1 == 0 ? data.stock.toInt().toString() : data.stock;
        return Text(
          habis ? 'Habis' : 'Stok $stockText',
          style: TextStyle(
              fontSize: 11,
              fontWeight: habis ? FontWeight.w700 : FontWeight.normal,
              color: habis ? scheme.error : scheme.onSurfaceVariant),
        );
      },
    );
  }
}
