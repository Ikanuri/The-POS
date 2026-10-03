import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/widgets/labeled_tool_button.dart';
import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/services/crash_log_service.dart';
import '../../core/services/purchase_ai_format.dart';
import '../../core/services/receive_text_parser.dart';
import '../../core/utils/purchase_calc.dart';
import '../../core/theme/app_theme.dart';
import 'purchase_history_screen.dart';

/// Penerimaan Barang — tempel daftar barang yang datang, qty MENAMBAH stok.
///
/// Sengaja BUKAN bagian Stock Opname: opname MENIMPA stok jadi hasil hitung
/// fisik, sedangkan di sini qty adalah barang yang baru datang sehingga
/// ditambahkan ke stok yang sudah ada (keputusan user 11 Agt 2026 setelah
/// contoh teks dari tools cek-stok eksternalnya ditinjau).
///
/// Pencocokan PERSIS saja — tidak ada fuzzy. Baris yang tidak ketemu/ambigu
/// diselesaikan user lewat dropdown berpencarian, dan pilihannya diingat di
/// kamus ([AppDatabase.learnReceiveAlias]) supaya tidak ditanya lagi.
class ReceiveGoodsScreen extends ConsumerStatefulWidget {
  const ReceiveGoodsScreen({super.key});

  @override
  ConsumerState<ReceiveGoodsScreen> createState() => _ReceiveGoodsScreenState();
}

/// Satu baris di layar review, dgn hasil pencocokannya + (Item 90) harga
/// beli/potongan/perlakuan PPN & pratinjau HPP.
class _Row {
  _Row({
    required this.sourceName,
    required this.sourceUnit,
    required this.raw,
    required double qty,
    this.unitId,
    this.label,
    int unitPrice = 0,
    int discount = 0,
    this.aiSuggested = false,
    this.problems = const [],
  })  : qtyCtrl = TextEditingController(text: _fmtNum(qty)),
        priceCtrl =
            TextEditingController(text: unitPrice > 0 ? '$unitPrice' : ''),
        discountCtrl =
            TextEditingController(text: discount > 0 ? '$discount' : '');

  /// Nama & satuan apa adanya dari sumber (teks/faktur) — kunci kamus alias.
  final String sourceName;
  final String sourceUnit;

  /// Baris mentah utk ditampilkan ("Dari teks: ...").
  final String raw;

  /// null = belum ketemu / ambigu → user wajib memilih dulu.
  String? unitId;

  /// Nama produk + satuan terpilih, untuk ditampilkan.
  String? label;

  /// true kalau user memilih manual (bukan hasil pencocokan otomatis) —
  /// dipakai memutuskan apakah pilihannya perlu disimpan ke kamus.
  bool pickedManually = false;

  /// Item 90 tahap 5 — produk hasil SARAN AI (bukan kamus): wajib
  /// dikonfirmasi pengguna sebelum ikut disimpan (aturan "tidak fuzzy
  /// otomatis"); setelah dikonfirmasi dipelajari jadi alias.
  bool aiSuggested;
  bool confirmed = false;

  /// Masalah validasi dari parser AI (kosong = aman).
  final List<String> problems;

  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController discountCtrl;

  /// Perlakuan PPN baris (null = belum dimuat, ikut default).
  PurchaseTaxTreatment? treatment;
  bool applyCost = true;

  /// Info satuan dari DB (HPP/harga jual saat ini, isi, dst).
  PurchaseUnitInfo? info;

  /// Item 90 tahap 4 — dampak ke harga Kategori Harga (pratinjau).
  List<({String label, String unitName, int oldPrice, int newPrice})> impact =
      const [];

  double get qty =>
      double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0;
  int get unitPrice => int.tryParse(priceCtrl.text.trim()) ?? 0;
  int get discount => int.tryParse(discountCtrl.text.trim()) ?? 0;
  bool get ready => unitId != null && qty > 0 && (!aiSuggested || confirmed);

  void dispose() {
    qtyCtrl.dispose();
    priceCtrl.dispose();
    discountCtrl.dispose();
  }
}

String _fmtNum(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

/// Satu faktur (atau satu "sesi" penerimaan teks/manual).
class _Invoice {
  _Invoice({
    String? invoiceNo,
    String? supplier,
    this.invoiceDate,
    this.priceIncludesTax = true,
    int invoiceDiscount = 0,
    this.problems = const [],
  })  : noCtrl = TextEditingController(text: invoiceNo ?? ''),
        supplierCtrl = TextEditingController(text: supplier ?? ''),
        discountCtrl = TextEditingController(
            text: invoiceDiscount > 0 ? '$invoiceDiscount' : '');

  final TextEditingController noCtrl;
  final TextEditingController supplierCtrl;
  final TextEditingController discountCtrl;
  DateTime? invoiceDate;
  bool priceIncludesTax;
  final List<String> problems;
  final List<_Row> rows = [];

  int get invoiceDiscount => int.tryParse(discountCtrl.text.trim()) ?? 0;

  void dispose() {
    noCtrl.dispose();
    supplierCtrl.dispose();
    discountCtrl.dispose();
    for (final r in rows) {
      r.dispose();
    }
  }
}

/// Alias tipe hasil [AppDatabase.getPurchaseUnitInfo].
typedef PurchaseUnitInfo = ({
  String baseUnitId,
  double ratio,
  String baseUnitName,
  String unitName,
  String productName,
  int currentCost,
  int basePrice,
  bool isNonStock,
  PurchaseTaxTreatment? lastTreatment,
});

final _pendingPurchasesProvider = StreamProvider<List<Purchase>>((ref) => ref
    .watch(databaseProvider)
    .watchPurchases()
    .map((l) => l.where((p) => p.status == 'pending').toList()));

class _ReceiveGoodsScreenState extends ConsumerState<ReceiveGoodsScreen> {
  final _textCtrl = TextEditingController();
  final _aiCtrl = TextEditingController();

  /// 0 = tempel teks, 1 = hasil AI (Item 90 tahap 5).
  int _source = 0;
  List<_Invoice>? _invoices;
  List<String> _unparsed = const [];
  String? _aiError;
  bool _busy = false;

  /// Item 90 — boleh mengisi harga beli? Owner selalu; HP lain butuh izin
  /// `input_pembelian` (perubahan HPP-nya jadi usulan owner).
  bool _canPrice = false;
  ({PurchaseTaxTreatment treatment, double taxRate, double warnPct})
      _settings = (
    treatment: PurchaseTaxTreatment.pisah,
    taxRate: 11,
    warnPct: 30,
  );

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  Future<void> _loadContext() async {
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final canPrice =
        device.isOwner || await db.isPermissionEnabled('input_pembelian');
    final settings = await db.getPurchaseSettings();
    if (!mounted) return;
    setState(() {
      _canPrice = canPrice;
      _settings = settings;
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _aiCtrl.dispose();
    for (final inv in _invoices ?? const <_Invoice>[]) {
      inv.dispose();
    }
    super.dispose();
  }

  Future<String> _labelFor(String unitId) async {
    final db = ref.read(databaseProvider);
    final rows = await db.customSelect(
      'SELECT p.name AS pname, ut.name AS uname FROM product_units pu '
      'JOIN products p ON p.id = pu.product_id '
      'LEFT JOIN unit_types ut ON ut.id = pu.unit_type_id '
      'WHERE pu.id = ?',
      variables: [Variable.withString(unitId)],
    ).get();
    if (rows.isEmpty) return unitId;
    final pname = rows.first.data['pname'] as String? ?? unitId;
    final uname = rows.first.data['uname'] as String?;
    return uname == null ? pname : '$pname · $uname';
  }

  /// Muat info satuan + perlakuan PPN default (diingat per barang) baris
  /// [r], lalu hitung ulang pratinjau.
  Future<void> _attachInfo(_Row r) async {
    final id = r.unitId;
    if (id == null) {
      r.info = null;
      r.impact = const [];
      return;
    }
    final db = ref.read(databaseProvider);
    r.info = await db.getPurchaseUnitInfo(id);
    r.treatment ??= r.info?.lastTreatment ?? _settings.treatment;
    await _refreshImpact(r);
  }

  Future<void> _refreshImpact(_Row r) async {
    final info = r.info;
    final cost = _newCost(r);
    if (info == null || cost == null || !r.applyCost) {
      r.impact = const [];
      return;
    }
    r.impact = await ref
        .read(databaseProvider)
        .getCategoryPriceImpact(info.baseUnitId, cost);
  }

  void _replaceInvoices(List<_Invoice> next) {
    for (final inv in _invoices ?? const <_Invoice>[]) {
      inv.dispose();
    }
    _invoices = next;
  }

  /// Jalankan [body] dgn spinner; GALAT APA PUN dicatat & ditampilkan (bukan
  /// membiarkan spinner berputar selamanya) lalu spinner dimatikan.
  Future<void> _guarded(String what, Future<void> Function() body) async {
    try {
      await body();
    } catch (e, st) {
      await CrashLogService.record(e, st, context: 'receive_goods_$what');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal ($what): $e'),
        duration: const Duration(seconds: 8),
      ));
    }
  }

  Future<void> _process() => _guarded('proses daftar', _processImpl);

  Future<void> _processImpl() async {
    final text = _textCtrl.text;
    if (text.trim().isEmpty) return;
    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final parsed = ReceiveTextParser.parse(text);
    final inv = _Invoice();
    for (final line in parsed.lines) {
      final unitId =
          await db.resolveReceiveUnit(name: line.name, unit: line.unit);
      final r = _Row(
        sourceName: line.name,
        sourceUnit: line.unit,
        raw: line.raw,
        qty: line.qty,
        unitId: unitId,
        label: unitId == null ? null : await _labelFor(unitId),
      );
      await _attachInfo(r);
      inv.rows.add(r);
    }
    if (!mounted) return;
    setState(() {
      _replaceInvoices([inv]);
      _unparsed = parsed.unparsed;
      _aiError = null;
      _busy = false;
    });
  }

  /// Item 90 tahap 5 — proses balasan AI yang ditempel.
  Future<void> _processAi() => _guarded('proses hasil AI', _processAiImpl);

  Future<void> _processAiImpl() async {
    final text = _aiCtrl.text;
    if (text.trim().isEmpty) return;
    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final known = (await db.getPurchaseAiCsvRows())
        .map((r) => r.productUnitId)
        .toSet();
    final res = parsePurchaseAiResponse(text,
        knownUnitIds: known, taxRate: _settings.taxRate);
    if (!res.ok) {
      if (mounted) {
        setState(() {
          _aiError = res.error;
          _busy = false;
        });
      }
      return;
    }
    final invoices = <_Invoice>[];
    for (final ai in res.invoices) {
      final inv = _Invoice(
        invoiceNo: ai.invoiceNo,
        supplier: ai.supplier,
        invoiceDate: ai.invoiceDate,
        priceIncludesTax: ai.priceIncludesTax,
        invoiceDiscount: ai.invoiceDiscount,
        problems: ai.problems,
      );
      for (final l in ai.lines) {
        // Kamus (pencocokan PERSIS yang pernah dikonfirmasi) menang atas
        // saran AI — saran AI hanya dipakai bila kamus tidak tahu.
        final fromAlias =
            await db.resolveReceiveUnit(name: l.name, unit: l.unit);
        final unitId = fromAlias ?? l.productUnitId;
        final r = _Row(
          sourceName: l.name,
          sourceUnit: l.unit,
          raw: '${_fmtNum(l.qty)} ${l.unit} ${l.name}',
          qty: l.qty,
          unitId: unitId,
          label: unitId == null ? null : await _labelFor(unitId),
          unitPrice: l.unitPrice,
          discount: l.discount,
          aiSuggested: fromAlias == null && l.productUnitId != null,
          problems: [
            ...l.problems,
            if (!l.confident) 'AI kurang yakin membaca baris ini — cek ulang',
          ],
        );
        await _attachInfo(r);
        inv.rows.add(r);
      }
      invoices.add(inv);
    }
    if (!mounted) return;
    setState(() {
      _replaceInvoices(invoices);
      _unparsed = const [];
      _aiError = null;
      _busy = false;
    });
  }

  Future<void> _copyPrompt() async {
    await Clipboard.setData(
        ClipboardData(text: buildPurchaseAiPrompt(taxRate: _settings.taxRate)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Prompt disalin — tempel ke AI bersama foto faktur '
            '& file CSV produk')));
  }

  Future<void> _shareCsv() async {
    final db = ref.read(databaseProvider);
    final csv = buildPurchaseAiCsv(await db.getPurchaseAiCsvRows());
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/produk_ai_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv);
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')],
        text: 'Daftar produk untuk pencocokan faktur');
  }

  Future<void> _pickProduct(_Row row) async {
    final db = ref.read(databaseProvider);
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPickerSheet(
        db: db,
        // Teks baris jadi kata kunci awal — kebanyakan kasus tinggal
        // memilih dari hasil yang sudah tersaring, tanpa mengetik lagi.
        initialQuery: row.sourceName,
      ),
    );
    if (picked == null || !mounted) return;
    final label = await _labelFor(picked);
    if (!mounted) return;
    row
      ..unitId = picked
      ..label = label
      ..pickedManually = true
      ..aiSuggested = false
      ..treatment = null;
    await _attachInfo(row);
    if (mounted) setState(() {});
  }

  /// Tambah barang manual (cari nama/barcode) ke faktur pertama.
  Future<void> _addManual() async {
    final db = ref.read(databaseProvider);
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPickerSheet(db: db, initialQuery: ''),
    );
    if (picked == null || !mounted) return;
    final label = await _labelFor(picked);
    final r = _Row(
      sourceName: label,
      sourceUnit: '',
      raw: label,
      qty: 1,
      unitId: picked,
      label: label,
    );
    await _attachInfo(r);
    if (!mounted) return;
    setState(() {
      _invoices ??= [_Invoice()];
      if (_invoices!.isEmpty) _invoices!.add(_Invoice());
      _invoices!.first.rows.add(r);
    });
  }

  /// Hasil hitung baris (dgn alokasi potongan faktur) — null bila belum
  /// siap/ tanpa harga.
  PurchaseLineResult? _calc(_Row r) {
    final info = r.info;
    if (info == null || r.qty <= 0 || r.unitPrice <= 0) return null;
    final inv = _invoices?.firstWhere((i) => i.rows.contains(r),
        orElse: () => _Invoice());
    var alloc = 0;
    if (inv != null && inv.invoiceDiscount > 0) {
      final nets = [
        for (final x in inv.rows) (x.qty * x.unitPrice).round() - x.discount
      ];
      alloc = allocateInvoiceDiscount(nets, inv.invoiceDiscount)[
          inv.rows.indexOf(r)];
    }
    return computePurchaseLine(
      qty: r.qty,
      unitPrice: r.unitPrice,
      discount: r.discount + alloc,
      priceIncludesTax: inv?.priceIncludesTax ?? true,
      treatment: r.treatment ?? _settings.treatment,
      taxRate: _settings.taxRate,
      ratioToBase: info.ratio,
    );
  }

  int? _newCost(_Row r) => r.applyCost ? _calc(r)?.costPerBaseUnit : null;

  bool _overThreshold(_Row r) {
    final c = _newCost(r);
    final info = r.info;
    return c != null &&
        info != null &&
        exceedsCostChangeThreshold(info.currentCost, c, _settings.warnPct);
  }

  bool _belowSellPrice(_Row r) {
    final c = _newCost(r);
    final info = r.info;
    return c != null && info != null && info.basePrice > 0 && info.basePrice < c;
  }

  Future<void> _commit() => _guarded('simpan pembelian', _commitImpl);

  Future<void> _commitImpl() async {
    final invoices = _invoices;
    if (invoices == null) return;
    final ready = [
      for (final inv in invoices) ...inv.rows.where((r) => r.ready)
    ];
    if (ready.isEmpty) return;
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);

    if (_canPrice) {
      // Peringatan sebelum simpan: faktur ganda, perubahan HPP besar, harga
      // jual di bawah modal baru.
      final warnings = <String>[];
      for (final inv in invoices) {
        final no = inv.noCtrl.text.trim();
        if (no.isNotEmpty && await db.purchaseInvoiceExists(no)) {
          warnings.add('Faktur $no sudah pernah dicatat');
        }
      }
      for (final r in ready) {
        final name = r.label ?? r.sourceName;
        if (_overThreshold(r)) {
          final p = costChangePercent(r.info!.currentCost, _newCost(r)!)!;
          warnings.add('$name: HPP berubah ${p.toStringAsFixed(1)}%');
        }
        if (_belowSellPrice(r)) {
          warnings.add('$name: harga jual di bawah HPP baru');
        }
      }
      if (warnings.isNotEmpty) {
        if (!mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Periksa dulu'),
            content: SingleChildScrollView(
              child: Text(warnings.map((w) => '• $w').join('\n')),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cek lagi')),
              FilledButton(
                  key: const ValueKey('purchase-warn-continue'),
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Tetap simpan')),
            ],
          ),
        );
        if (go != true || !mounted) return;
      }
    }

    setState(() => _busy = true);

    // Simpan pilihan manual / saran AI yang dikonfirmasi ke kamus DULU —
    // supaya kalau commit stok gagal di tengah, pembelajaran teksnya tetap
    // tidak hilang (user tidak perlu memilih ulang barang yang sama).
    for (final r in ready.where((r) => r.pickedManually || r.confirmed)) {
      await db.learnReceiveAlias(
        name: r.sourceName,
        unit: r.sourceUnit,
        productUnitId: r.unitId!,
      );
    }

    for (final inv in invoices) {
      final rows = inv.rows.where((r) => r.ready).toList();
      if (rows.isEmpty) continue;
      await db.applyPurchase(
        lines: [
          for (final r in rows)
            PurchaseLineInput(
              productUnitId: r.unitId!,
              qty: r.qty,
              unitPrice: _canPrice ? r.unitPrice : 0,
              discount: _canPrice ? r.discount : 0,
              priceIncludesTax: inv.priceIncludesTax,
              treatment: r.treatment ?? _settings.treatment,
              taxRate: _settings.taxRate,
              applyCost: _canPrice && r.applyCost,
            ),
        ],
        invoiceNo:
            inv.noCtrl.text.trim().isEmpty ? null : inv.noCtrl.text.trim(),
        invoiceDate: inv.invoiceDate,
        supplierName: inv.supplierCtrl.text.trim().isEmpty
            ? null
            : inv.supplierCtrl.text.trim(),
        invoiceDiscount: _canPrice ? inv.invoiceDiscount : 0,
        kasirId: device.deviceCode,
        note: AppDatabase.buildReceiveNote(DateTime.now()),
        costAsProposal: !device.isOwner,
      );
    }

    if (!mounted) return;
    setState(() => _busy = false);
    final total = invoices.fold<int>(0, (s, i) => s + i.rows.length);
    final skipped = total - ready.length;
    final proposal = !device.isOwner &&
        ready.any((r) => _canPrice && r.applyCost && r.unitPrice > 0);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text([
        skipped == 0
            ? '${ready.length} barang masuk ke stok'
            : '${ready.length} barang masuk · $skipped baris dilewati '
                '(belum dipilih/dikonfirmasi produknya)',
        if (proposal) 'HPP menunggu persetujuan owner',
      ].join(' · ')),
    ));
    Navigator.of(context).pop();
  }

  Future<void> _openSettings() async {
    final db = ref.read(databaseProvider);
    var treatment = _settings.treatment;
    final rateCtrl = TextEditingController(text: _fmtNum(_settings.taxRate));
    final warnCtrl = TextEditingController(text: _fmtNum(_settings.warnPct));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Pengaturan Pembelian'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Perlakuan PPN default',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                for (final t in PurchaseTaxTreatment.values)
                  RadioListTile<PurchaseTaxTreatment>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: t,
                    groupValue: treatment,
                    title: Text(_treatmentLong(t)),
                    onChanged: (v) => setD(() => treatment = v ?? treatment),
                  ),
                TextField(
                  controller: rateCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Tarif PPN', suffixText: '%', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('purchase-warn-pct'),
                  controller: warnCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Peringatkan bila HPP berubah lebih dari',
                      suffixText: '%',
                      isDense: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok == true) {
      final rate = double.tryParse(rateCtrl.text.replaceAll(',', '.'));
      final warn = double.tryParse(warnCtrl.text.replaceAll(',', '.'));
      await db.setSetting(kPurchaseTaxTreatmentKey, treatment.code);
      if (rate != null && rate >= 0) {
        await db.setSetting(kPurchaseTaxRateKey, _fmtNum(rate));
      }
      if (warn != null && warn > 0) {
        await db.setSetting(kPurchaseCostWarnPctKey, _fmtNum(warn));
      }
      await _loadContext();
    }
    rateCtrl.dispose();
    warnCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final device = ref.watch(deviceProvider);
    final invoices = _invoices;
    final allRows = [for (final i in invoices ?? const <_Invoice>[]) ...i.rows];
    final readyCount = allRows.where((r) => r.ready).length;
    final pending = device.isOwner
        ? (ref.watch(_pendingPurchasesProvider).valueOrNull ?? const [])
        : const <Purchase>[];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kLabeledToolbarHeight,
        title: const Text('Penerimaan Barang'),
        actions: [
          LabeledToolbarActions(children: [
            LabeledToolButton(
              icon: Icons.receipt_long_outlined,
              label: 'Riwayat Pembelian',
              tooltip: 'Riwayat Pembelian',
              labelWidth: 50,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const PurchaseHistoryScreen(),
              )),
            ),
            LabeledToolButton(
              icon: Icons.menu_book_outlined,
              label: 'Kamus Produk',
              tooltip: 'Kamus Produk',
              labelWidth: 50,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const ReceiveAliasScreen(),
              )),
            ),
            if (device.isOwner)
              LabeledToolButton(
                icon: Icons.tune_rounded,
                label: 'Pengaturan',
                tooltip: 'Pengaturan Pembelian',
                labelWidth: 50,
                onTap: _openSettings,
              ),
          ]),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (pending.isNotEmpty) ...[
                  Card(
                    key: const ValueKey('purchase-pending-card'),
                    color: Colors.amber.withOpacity(0.12),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Menunggu persetujuan HPP (${pending.length})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          for (final p in pending)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                  (p.invoiceNo ?? '').isEmpty
                                      ? 'Pembelian dari ${p.kasirId ?? '-'}'
                                      : 'Faktur ${p.invoiceNo} · ${p.kasirId ?? '-'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(purchaseDateLabel(
                                  p.invoiceDate ?? p.createdAt)),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  showPurchaseDetailSheet(context, ref, p),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_canPrice)
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Tempel teks')),
                      ButtonSegment(value: 1, label: Text('Hasil AI')),
                    ],
                    selected: {_source},
                    onSelectionChanged: (s) =>
                        setState(() => _source = s.first),
                  ),
                if (_canPrice) const SizedBox(height: 12),
                if (_source == 0) ...[
                  Text(
                    'Tempel daftar barang yang datang. Satu baris = '
                    '"jumlah satuan nama", misalnya "5 pcs Indomie Goreng". '
                    'Baris pemisah tanggal otomatis diabaikan. Jumlahnya akan '
                    'DITAMBAHKAN ke stok (bukan menimpa seperti opname).',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _textCtrl,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '5 pcs Indomie Goreng\n2 dus Aqua',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _process,
                      icon: const Icon(Icons.playlist_add_check),
                      label: const Text('Proses Daftar'),
                    ),
                  ),
                ] else
                  ..._aiSection(scheme),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const ValueKey('purchase-add-manual'),
                    onPressed: _addManual,
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah barang (cari nama/barcode)'),
                  ),
                ),
                if (_unparsed.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: scheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Baris tidak dikenali (dilewati):',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onErrorContainer)),
                          const SizedBox(height: 4),
                          for (final u in _unparsed)
                            Text('• $u',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onErrorContainer)),
                        ],
                      ),
                    ),
                  ),
                ],
                if (invoices != null && allRows.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text('Hasil (${allRows.length} baris)',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final inv in invoices) ...[
                    if (_canPrice) _invoiceHeader(inv, scheme),
                    for (final r in inv.rows) _rowTile(r, scheme),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: readyCount == 0 ? null : _commit,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text('Tambahkan $readyCount Barang ke Stok'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  List<Widget> _aiSection(ColorScheme scheme) => [
        Text(
          '1) Salin prompt & bagikan file CSV produk ke AI (Claude/Meta AI), '
          'lampirkan foto faktur. 2) Salin SELURUH balasan AI, tempel di '
          'bawah. Aplikasi yang menghitung HPP — hasil tetap dicek dulu.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('purchase-ai-copy-prompt'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: _copyPrompt,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Salin prompt'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('purchase-ai-share-csv'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: _shareCsv,
                icon: const Icon(Icons.table_view_outlined, size: 16),
                label: const Text('CSV produk'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('purchase-ai-input'),
          controller: _aiCtrl,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Tempel balasan AI di sini',
            isDense: true,
          ),
        ),
        if (_aiError != null) ...[
          const SizedBox(height: 6),
          Text(_aiError!,
              style: TextStyle(fontSize: 12, color: scheme.error)),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('purchase-ai-process'),
            onPressed: _processAi,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Proses hasil AI'),
          ),
        ),
      ];

  Widget _invoiceHeader(_Invoice inv, ColorScheme scheme) {
    final title = [
      if (inv.noCtrl.text.trim().isNotEmpty) 'Faktur ${inv.noCtrl.text.trim()}',
      if (inv.supplierCtrl.text.trim().isNotEmpty) inv.supplierCtrl.text.trim(),
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 6, top: 6),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Text(title.isEmpty ? 'Info faktur (opsional)' : title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: inv.problems.isEmpty
            ? null
            : Text(inv.problems.join('\n'),
                style: TextStyle(fontSize: 11, color: scheme.error)),
        children: [
          TextField(
            controller: inv.noCtrl,
            decoration:
                const InputDecoration(labelText: 'No. faktur', isDense: true),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: inv.supplierCtrl,
            decoration:
                const InputDecoration(labelText: 'Supplier', isDense: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                    inv.invoiceDate == null
                        ? 'Tanggal faktur: hari ini'
                        : 'Tanggal faktur: ${purchaseDateLabel(inv.invoiceDate!)}',
                    style: const TextStyle(fontSize: 12)),
              ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: inv.invoiceDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (d != null) setState(() => inv.invoiceDate = d);
                },
                child: const Text('Ubah'),
              ),
            ],
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Harga di faktur sudah termasuk PPN',
                style: TextStyle(fontSize: 12.5)),
            value: inv.priceIncludesTax,
            onChanged: (v) async {
              setState(() => inv.priceIncludesTax = v);
              for (final r in inv.rows) {
                await _refreshImpact(r);
              }
              if (mounted) setState(() {});
            },
          ),
          TextField(
            controller: inv.discountCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
                labelText: 'Potongan faktur (dibagi ke semua baris)',
                prefixText: 'Rp ',
                isDense: true),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _rowTile(_Row r, ColorScheme scheme) {
    final matched = r.unitId != null;
    final needsConfirm = r.aiSuggested && !r.confirmed;
    final info = r.info;
    final unitName = info?.unitName ?? (r.sourceUnit.isEmpty ? 'satuan' : r.sourceUnit);
    final calc = _canPrice ? _calc(r) : null;
    final newCost = _canPrice ? _newCost(r) : null;
    Future<void> changed() async {
      await _refreshImpact(r);
      if (mounted) setState(() {});
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 8),
              leading: Icon(
                !matched
                    ? Icons.help_outline
                    : needsConfirm
                        ? Icons.auto_awesome_outlined
                        : Icons.check_circle_outline,
                color: !matched
                    ? scheme.error
                    : needsConfirm
                        ? Colors.amber.shade800
                        : scheme.tertiary,
                size: 20,
              ),
              title: Text(
                matched ? r.label! : r.sourceName,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                !matched
                    ? 'Tidak ketemu — pilih produknya'
                    : needsConfirm
                        ? 'Saran AI dari "${r.sourceName}" — konfirmasi atau ganti'
                        : 'Dari teks: "${r.raw}"',
                style: TextStyle(
                    fontSize: 11,
                    color: !matched
                        ? scheme.error
                        : needsConfirm
                            ? Colors.amber.shade800
                            : scheme.onSurfaceVariant),
              ),
              trailing: _canPrice
                  ? null
                  : Text(
                      '+${_fmtNum(r.qty)}'
                      '${r.sourceUnit.isEmpty ? '' : ' ${r.sourceUnit}'}',
                      style: AppTheme.numStyle(context, size: 13),
                    ),
              onTap: () => _pickProduct(r),
            ),
            if (needsConfirm)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: TextButton.icon(
                  key: ValueKey('purchase-ai-confirm-${r.sourceName}'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 36)),
                  onPressed: () => setState(() => r.confirmed = true),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Benar, ini produknya'),
                ),
              ),
            for (final p in r.problems)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 2),
                child: Text('⚠ $p',
                    style: TextStyle(fontSize: 11, color: scheme.error)),
              ),
            if (_canPrice) ...[
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: r.qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Jumlah', isDense: true),
                        onChanged: (_) => changed(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: r.priceCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: InputDecoration(
                            labelText: 'Harga per $unitName',
                            prefixText: 'Rp ',
                            isDense: true),
                        onChanged: (_) => changed(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 84,
                      child: TextField(
                        controller: r.discountCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                            labelText: 'Potongan', isDense: true),
                        onChanged: (_) => changed(),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final t in PurchaseTaxTreatment.values)
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(_treatmentShort(t),
                            style: const TextStyle(fontSize: 11)),
                        selected: (r.treatment ?? _settings.treatment) == t,
                        onSelected: (_) {
                          r.treatment = t;
                          changed();
                        },
                      ),
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('Perbarui HPP',
                          style: TextStyle(fontSize: 11)),
                      selected: r.applyCost,
                      onSelected: (v) {
                        r.applyCost = v;
                        changed();
                      },
                    ),
                  ],
                ),
              ),
              if (info != null && newCost != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HPP per ${info.baseUnitName}: '
                        '${formatRupiah(info.currentCost)} → '
                        '${formatRupiah(newCost)}'
                        '${costChangePercent(info.currentCost, newCost) == null ? '' : ' (${costChangePercent(info.currentCost, newCost)! >= 0 ? '+' : ''}${costChangePercent(info.currentCost, newCost)!.toStringAsFixed(1)}%)'}',
                        key: ValueKey('purchase-preview-${r.sourceName}'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _overThreshold(r)
                              ? Colors.amber.shade800
                              : scheme.primary,
                        ),
                      ),
                      if ((calc?.inputTax ?? 0) > 0)
                        Text('PPN masukan ${formatRupiah(calc!.inputTax)}',
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant)),
                      if (_belowSellPrice(r))
                        Text(
                          'Harga jual ${formatRupiah(info.basePrice)} di bawah '
                          'HPP baru!',
                          key: ValueKey('purchase-below-${r.sourceName}'),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.error),
                        ),
                      for (final c in r.impact)
                        Text(
                          'Harga ${c.label} (${c.unitName}): '
                          '${formatRupiah(c.oldPrice)} → '
                          '${formatRupiah(c.newPrice)}',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      if (!ref.read(deviceProvider).isOwner)
                        Text('Perubahan HPP menunggu persetujuan owner',
                            style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _treatmentShort(PurchaseTaxTreatment t) => switch (t) {
      PurchaseTaxTreatment.modal => 'PPN ke modal',
      PurchaseTaxTreatment.pisah => 'PPN dipisah',
      PurchaseTaxTreatment.bebas => 'Bebas PPN',
    };

String _treatmentLong(PurchaseTaxTreatment t) => switch (t) {
      PurchaseTaxTreatment.modal =>
        'PPN masuk modal (HPP termasuk PPN)',
      PurchaseTaxTreatment.pisah =>
        'PPN dipisah (HPP tanpa PPN, PPN masukan dicatat)',
      PurchaseTaxTreatment.bebas => 'Barang bebas PPN',
    };

/// Dropdown pemilih produk BERPENCARIAN (permintaan user: "ada opsi search
/// di modal dropdown tersebut").
class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.db, required this.initialQuery});
  final AppDatabase db;
  final String initialQuery;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  late final TextEditingController _q =
      TextEditingController(text: widget.initialQuery);
  List<({String unitId, String label})> _results = const [];

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final term = _q.text.trim().toLowerCase();
    final rows = await widget.db.customSelect(
      'SELECT pu.id AS uid, p.name AS pname, ut.name AS uname '
      'FROM product_units pu '
      'JOIN products p ON p.id = pu.product_id '
      'LEFT JOIN unit_types ut ON ut.id = pu.unit_type_id '
      // Item 90 — juga cocokkan barcode persis (scan dari scanner eksternal
      // mengetik ke kolom cari ini).
      'WHERE p.is_active = 1 AND (LOWER(p.name) LIKE ? OR EXISTS ('
      '  SELECT 1 FROM product_barcodes pb WHERE pb.product_unit_id = pu.id '
      '  AND pb.barcode = ?)) '
      'ORDER BY p.name LIMIT 80',
      variables: [Variable.withString('%$term%'), Variable.withString(term)],
    ).get();
    if (!mounted) return;
    setState(() {
      _results = [
        for (final r in rows)
          (
            unitId: r.data['uid'] as String,
            label: (r.data['uname'] as String?) == null
                ? (r.data['pname'] as String)
                : '${r.data['pname']} · ${r.data['uname']}',
          ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: (_) => _search(),
                decoration: const InputDecoration(
                  labelText: 'Cari produk',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text('Tidak ada produk cocok'))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        title: Text(_results[i].label,
                            style: const TextStyle(fontSize: 13)),
                        onTap: () =>
                            Navigator.of(context).pop(_results[i].unitId),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kelola isi kamus — supaya pemetaan yang pernah salah bisa dihapus.
class ReceiveAliasScreen extends ConsumerStatefulWidget {
  const ReceiveAliasScreen({super.key});

  @override
  ConsumerState<ReceiveAliasScreen> createState() => _ReceiveAliasScreenState();
}

class _ReceiveAliasScreenState extends ConsumerState<ReceiveAliasScreen> {
  List<ReceiveAliasRow>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(databaseProvider).getReceiveAliases();
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('Kamus Produk')),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Kamus masih kosong. Setiap kali kamu memilih produk '
                    'untuk baris yang tidak dikenali di Penerimaan Barang, '
                    'pilihannya otomatis diingat di sini.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final a = rows[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        a.normalizedUnit.isEmpty
                            ? a.normalizedName
                            : '${a.normalizedName} (${a.normalizedUnit})',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        a.productName ?? '(produk sudah dihapus)',
                        style: TextStyle(
                          fontSize: 11,
                          color: a.productName == null
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline,
                            size: 20, color: scheme.error),
                        onPressed: () async {
                          await ref
                              .read(databaseProvider)
                              .deleteReceiveAlias(a.id);
                          await _load();
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
