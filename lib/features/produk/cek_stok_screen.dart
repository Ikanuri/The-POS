import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
import 'stock_opname_screen.dart';

/// Item 30(b) — layar kontrol stok terpisah dari daftar Produk (fokus
/// triase, bukan manajemen). Filter kategori → list produk stok riil
/// diurut tertipis → checkbox yang SEKALIGUS: (1) update `markedOutOfStock`
/// sungguhan di DB (state nyata, langsung dibaca katalog HTML Item 29 &
/// item_entry_sheet.dart kasir), DAN (2) menyusun teks order restock ke
/// supplier di panel bawah. Reuse untuk Item 30(a): dibuka dgn parameter
/// [initialGroupId] dari kartu ringkas Ringkasan Harian.
class CekStokScreen extends ConsumerStatefulWidget {
  const CekStokScreen({super.key, this.initialGroupId});
  final int? initialGroupId;

  @override
  ConsumerState<CekStokScreen> createState() => _CekStokScreenState();
}

final _cekStokGroupProvider = StateProvider<int?>((ref) => null);

final _cekStokGroupsProvider = FutureProvider<List<ProductGroup>>((ref) {
  return ref.watch(databaseProvider).getAllProductGroups();
});

final _cekStokOverviewProvider =
    StreamProvider.family<List<StockOverviewRow>, int?>((ref, groupId) {
  return ref.watch(databaseProvider).watchStockOverview(groupId: groupId);
});

class _CekStokScreenState extends ConsumerState<CekStokScreen> {
  // Item 4 (revisi 25 Juli, setelah user membandingkan dgn HTML acuannya) —
  // baris "Order Restock" adalah JUMLAH YANG MAU DIORDER, diisi owner, BUKAN
  // stok saat ini dikonversi. Versi pertama memakai stok → hasilnya tidak
  // masuk akal utk order (stok -104 jadi "-104 Pres Lawet Ijo") dan angkanya
  // sama sekali tidak bisa diubah. Sekarang meniru acuan: tiap produk
  // tercentang dapat baris `[−] [qty] [+] [satuan ▾]`, qty awal 1, ketuk
  // angkanya utk mengetik lewat dialog, dan teks order-nya bisa diedit
  // langsung (dua arah).

  /// Pilihan satuan per produk: satuan milik produk itu DULU (paling
  /// relevan), lalu sisa nama satuan umum dari tabel `unit_types` — supaya
  /// produk bersatuan tunggal pun tetap bisa diorder dlm satuan lain
  /// (keputusan user: "satuan produk + daftar umum").
  final Map<String, List<String>> _unitOptions = {};
  final Map<String, String> _selectedUnit = {};
  final Map<String, double> _orderQty = {};

  /// Nama satuan umum (seluruh `unit_types`), dimuat sekali.
  List<String> _genericUnits = const [];

  /// Teks order yang bisa diedit user + sinkronisasi dua arah.
  final _orderCtrl = TextEditingController();
  final _orderFocus = FocusNode();
  Timer? _parseDebounce;

  /// Menahan regenerasi teks saat kita sendiri yang baru menulisnya (dan
  /// sebaliknya) — tanpa ini, tulis-baca saling memicu tanpa henti.
  bool _suppressSync = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialGroupId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(_cekStokGroupProvider.notifier).state =
            widget.initialGroupId;
      });
    }
    _orderFocus.addListener(() {
      // Begitu user selesai menyunting, rapikan teksnya kembali ke bentuk
      // kanonik hasil state (mis. baris tanpa qty jadi "1 <satuan> <nama>").
      if (!_orderFocus.hasFocus) _syncOrderText(force: true);
    });
    ref.read(databaseProvider).getAllUnitTypes().then((types) {
      if (!mounted) return;
      setState(() => _genericUnits =
          types.map((t) => t.name).where((n) => n.isNotEmpty).toList());
    });
  }

  @override
  void dispose() {
    _parseDebounce?.cancel();
    _orderCtrl.dispose();
    _orderFocus.dispose();
    super.dispose();
  }

  Future<void> _toggle(String productId, bool value) async {
    final db = ref.read(databaseProvider);
    await db.setMarkedOutOfStock(productId, value);
    if (value) await _ensureUnitsLoaded(productId);
  }

  Future<void> _ensureUnitsLoaded(String productId) =>
      _loadUnitsFor([productId]);

  /// Muat pilihan satuan untuk sekumpulan produk sekaligus (satu query
  /// batch). Produk yang sudah pernah dimuat dilewati.
  ///
  /// Daftarnya = satuan MILIK produk itu dulu (urut satuan dasar lebih
  /// dahulu, karena itu default & paling sering benar), lalu nama satuan
  /// umum lain dari `unit_types` yang belum tercakup. Jadi produk bersatuan
  /// tunggal pun tetap dapat pemilih satuan — di acuan user setiap item
  /// tercentang SELALU punya qty & satuan, tidak pernah "- Nama" polos.
  Future<void> _loadUnitsFor(List<String> productIds) async {
    final missing = [
      for (final id in productIds)
        if (!_unitOptions.containsKey(id)) id,
    ];
    if (missing.isEmpty) return;
    final byProduct =
        await ref.read(databaseProvider).getUnitsWithTypeNamesFor(missing);
    for (final id in missing) {
      final units = byProduct[id] ?? const [];
      final own = <String>[];
      // Satuan dasar didahulukan, sisanya mengikuti urutan aslinya.
      for (final u in units.where((u) => u.unit.isBaseUnit)) {
        own.add(u.unitName);
      }
      for (final u in units.where((u) => !u.unit.isBaseUnit)) {
        if (!own.contains(u.unitName)) own.add(u.unitName);
      }
      final options = [
        ...own,
        for (final g in _genericUnits)
          if (!own.contains(g)) g,
      ];
      _unitOptions[id] = options.isEmpty ? const ['Pcs'] : options;
      _selectedUnit[id] ??= _unitOptions[id]!.first;
      _orderQty[id] ??= 1;
    }
    if (mounted) setState(() {});
  }

  // ── qty order (meniru acuan: awal 1, +/- , ketuk angka utk mengetik) ──

  void _adjustQty(String productId, double delta) {
    final cur = _orderQty[productId] ?? 1;
    // Minus MEMBEKU di 1 — di acuan qty tidak pernah turun ke bawah 1 atau
    // jadi desimal lewat tombol.
    if (delta < 0 && cur <= 1) return;
    final next = cur + delta;
    setState(() => _orderQty[productId] = next < 1 ? 1 : next);
    _syncOrderText();
  }

  Future<void> _promptQty(String productId, String productName) async {
    final unit = _selectedUnit[productId] ?? '';
    final ctrl = TextEditingController(text: _fmtQty(_orderQty[productId] ?? 1));
    // Select-all supaya ketikan MENGGANTI angka lama, bukan menempel di
    // belakangnya (pelajaran dari dialog "Sesuaikan Stok").
    ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(productName, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Jumlah order',
            suffixText: unit,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.pop(
              ctx, double.tryParse(v.trim().replaceAll(',', '.'))),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx,
                double.tryParse(ctrl.text.trim().replaceAll(',', '.'))),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (result == null || result <= 0) return;
    setState(() => _orderQty[productId] = result);
    _syncOrderText();
  }

  void _setUnit(String productId, String unitName) {
    setState(() => _selectedUnit[productId] = unitName);
    _syncOrderText();
  }

  /// Produk yang SUDAH ditandai habis SEBELUM layar ini dibuka tidak pernah
  /// lewat [_toggle], jadi satuannya dulu tidak pernah dimuat sama sekali —
  /// pemilih satuan tidak muncul & teks order-nya jatuh ke "- {nama}" polos,
  /// walaupun produknya berjenjang (dilaporkan user 25 Juli: produk
  /// tercentang tapi "satuan tidak ada"). Dipanggil tiap kali daftar datang;
  /// satu query batch untuk semua yang tercentang, bukan per produk.
  void _ensureUnitsForChecked(List<StockOverviewRow> rows) {
    final checked = [
      for (final r in rows)
        if (r.markedOutOfStock) r.productId,
    ];
    if (checked.isNotEmpty) _loadUnitsFor(checked);
  }

  void _copyOrderText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teks order disalin')));
  }

  void _shareOrderText(String text) {
    Share.share(text, subject: 'Order Restock');
  }

  @override
  Widget build(BuildContext context) {
    final groupId = ref.watch(_cekStokGroupProvider);
    final groupsAsync = ref.watch(_cekStokGroupsProvider);
    final rowsAsync = ref.watch(_cekStokOverviewProvider(groupId));

    // Dibaca dari nilai yang sudah di-watch (BUKAN `ref.listen`, yang di
    // `WidgetRef` tidak punya `fireImmediately`) supaya emisi PERTAMA —
    // yang justru berisi produk tercentang dari sesi sebelumnya — ikut
    // tertangani. Aman dipanggil tiap build: [_loadUnitsFor] keluar
    // seketika kalau tidak ada yang perlu dimuat, dan `setState`-nya baru
    // terjadi setelah await (bukan di tengah build).
    final loadedRows = rowsAsync.valueOrNull;
    if (loadedRows != null) {
      _lastRows = loadedRows;
      _ensureUnitsForChecked(loadedRows);
      // Teks disusun ulang setelah frame — `_syncOrderText` menulis ke
      // controller, dan itu tidak boleh dilakukan di tengah build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncOrderText();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cek Stok'),
        actions: [
          IconButton(
            icon: const Icon(Icons.checklist_rounded),
            tooltip: 'Stock Opname',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const StockOpnameScreen(),
            )),
          ),
        ],
      ),
      body: Column(
        children: [
          groupsAsync.when(
            data: (groups) {
              final named = groups.where((g) => g.name != null).toList();
              return SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    _GroupChip(
                      label: 'Semua',
                      selected: groupId == null,
                      onTap: () =>
                          ref.read(_cekStokGroupProvider.notifier).state =
                              null,
                    ),
                    ...named.map((g) => _GroupChip(
                          label: g.name!,
                          selected: groupId == g.id,
                          onTap: () =>
                              ref.read(_cekStokGroupProvider.notifier).state =
                                  g.id,
                        )),
                  ],
                ),
              );
            },
            loading: () => const SizedBox(height: 44),
            error: (_, __) => const SizedBox(height: 44),
          ),
          const Divider(height: 1),
          Expanded(
            child: rowsAsync.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return const Center(
                      child: Text('Tidak ada produk berstok di kategori ini'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _StockRow(
                    row: rows[i],
                    onToggle: (v) => _toggle(rows[i].productId, v),
                    unitOptions: _unitOptions[rows[i].productId],
                    selectedUnit: _selectedUnit[rows[i].productId],
                    qty: _orderQty[rows[i].productId] ?? 1,
                    fmtQty: _fmtQty,
                    onQtyDelta: (d) => _adjustQty(rows[i].productId, d),
                    onQtyTap: () =>
                        _promptQty(rows[i].productId, rows[i].name),
                    onUnitChanged: (u) => _setUnit(rows[i].productId, u),
                  ),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
          rowsAsync.maybeWhen(
            data: (rows) {
              final checked = rows.where((r) => r.markedOutOfStock).toList();
              if (checked.isEmpty) return const SizedBox.shrink();
              return _OrderTextPanel(
                controller: _orderCtrl,
                focusNode: _orderFocus,
                onChanged: (_) => _onOrderTextChanged(),
                onCopy: () => _copyOrderText(_orderCtrl.text.trim()),
                onShare: () => _shareOrderText(_orderCtrl.text.trim()),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // Item 4 (usulan user) — baris output "{qty} {satuan} {nama}" (format
  // sama dgn contoh yg dikirim user) kalau produk itu punya satuan
  // berjenjang & sudah dipilih satuannya; selain itu tetap "- {nama}"
  // polos spt sebelumnya (tidak ada qty krn stok satuan tunggal biasanya
  // sudah jelas dari angka di badge kartu produknya sendiri).
  /// Satu baris per produk tercentang, SELALU `{qty} {satuan} {nama}` —
  /// tidak ada lagi cabang "- {nama}" polos (di acuan user tidak pernah ada
  /// bentuk itu). Qty di sini JUMLAH ORDER milik owner, bukan stok.
  String _buildOrderText(List<StockOverviewRow> checked) {
    final buf = StringBuffer('Order Restock:\n');
    for (final r in checked) {
      final qty = _orderQty[r.productId] ?? 1;
      final unit = _selectedUnit[r.productId];
      if (unit == null || unit.isEmpty) {
        // Satuan belum selesai dimuat — jangan tampilkan baris setengah jadi.
        buf.writeln('${_fmtQty(qty)} ${r.name}');
      } else {
        buf.writeln('${_fmtQty(qty)} $unit ${r.name}');
      }
    }
    return buf.toString().trim();
  }

  String _fmtQty(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  // ─────────── sinkronisasi dua arah teks order ⇄ daftar produk ───────────

  /// Tulis ulang teks dari state. Tidak dilakukan saat user sedang mengetik
  /// (fokus di textarea) supaya kursor & ketikannya tidak dirampas — kecuali
  /// [force] (dipakai saat fokus baru dilepas, utk merapikan bentuknya).
  void _syncOrderText({bool force = false}) {
    if (_suppressSync) return;
    if (!force && _orderFocus.hasFocus) return;
    final rows = _lastRows;
    if (rows == null) return;
    final checked = rows.where((r) => r.markedOutOfStock).toList();
    final text = checked.isEmpty ? '' : _buildOrderText(checked);
    if (_orderCtrl.text == text) return;
    _suppressSync = true;
    _orderCtrl.text = text;
    _suppressSync = false;
  }

  /// Baris terakhir yang diterima dari stream — dipakai [_syncOrderText] &
  /// parser (keduanya berjalan di luar `build`).
  List<StockOverviewRow>? _lastRows;

  void _onOrderTextChanged() {
    if (_suppressSync) return;
    // Di-debounce: tiap baris yang cocok berarti tulis `markedOutOfStock` ke
    // DB, dan tiap tulis memicu stream ini emit ulang. Tanpa debounce, satu
    // ketikan = beberapa tulis DB + rebuild yang berebut dgn ketikan user.
    _parseDebounce?.cancel();
    _parseDebounce = Timer(const Duration(milliseconds: 600), _applyOrderText);
  }

  /// Parse teks yang diedit user → centang, qty, & satuan ikut berubah
  /// (pola sama dgn `skOnOutputChange` di acuan). Baris yang produknya tidak
  /// ada di daftar diabaikan; produk yang barisnya DIHAPUS ikut di-uncheck.
  Future<void> _applyOrderText() async {
    final rows = _lastRows;
    if (rows == null || !mounted) return;
    final db = ref.read(databaseProvider);

    final parsed = <String, ({double qty, String? unit})>{};
    for (final line in _orderCtrl.text.split('\n')) {
      final p = _parseOrderLine(line);
      if (p != null) parsed[_norm(p.name)] = (qty: p.qty, unit: p.unit);
    }

    var changed = false;
    for (final r in rows) {
      final hit = parsed[_norm(r.name)];
      if (hit != null) {
        if (!r.markedOutOfStock) {
          await db.setMarkedOutOfStock(r.productId, true);
          await _ensureUnitsLoaded(r.productId);
          changed = true;
        }
        if (_orderQty[r.productId] != hit.qty) {
          _orderQty[r.productId] = hit.qty;
          changed = true;
        }
        final u = hit.unit;
        if (u != null && _selectedUnit[r.productId] != u) {
          // Satuan yang diketik user diterima walau belum ada di daftar
          // pilihan — jangan memaksa dia memakai nama yang kita kenal saja.
          final opts = _unitOptions[r.productId];
          if (opts != null && !opts.contains(u)) {
            _unitOptions[r.productId] = [u, ...opts];
          }
          _selectedUnit[r.productId] = u;
          changed = true;
        }
      } else if (r.markedOutOfStock) {
        await db.setMarkedOutOfStock(r.productId, false);
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  /// `{qty} {satuan} {nama}` — kalau bagian depannya bukan angka + satuan
  /// yang dikenal, seluruh baris dianggap NAMA (qty 1), persis
  /// `skParseLine` di acuan. Baris "Order Restock:" (judul) diabaikan.
  ({double qty, String? unit, String name})? _parseOrderLine(String line) {
    final t = line.trim();
    if (t.isEmpty) return null;
    if (t.endsWith(':')) return null; // judul
    final parts = t.split(RegExp(r'\s+'));
    if (parts.length >= 3) {
      final q = double.tryParse(parts[0].replaceAll(',', '.'));
      if (q != null && q > 0 && _isKnownUnit(parts[1])) {
        return (qty: q, unit: parts[1], name: parts.sublist(2).join(' '));
      }
    }
    // Bentuk lama "- Nama" tetap dimengerti supaya teks yang sudah pernah
    // disalin user masih bisa ditempel balik.
    final name = t.startsWith('- ') ? t.substring(2).trim() : t;
    return (qty: 1, unit: null, name: name);
  }

  bool _isKnownUnit(String s) {
    final n = _norm(s);
    if (_genericUnits.any((g) => _norm(g) == n)) return true;
    return _unitOptions.values
        .any((opts) => opts.any((o) => _norm(o) == n));
  }

  String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}


class _GroupChip extends StatelessWidget {
  const _GroupChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.row,
    required this.onToggle,
    required this.qty,
    required this.fmtQty,
    this.unitOptions,
    this.selectedUnit,
    this.onQtyDelta,
    this.onQtyTap,
    this.onUnitChanged,
  });
  final StockOverviewRow row;
  final ValueChanged<bool> onToggle;

  /// Jumlah yang mau DIORDER (bukan stok). Awal 1, seperti acuan.
  final double qty;
  final String Function(double) fmtQty;

  /// Pilihan satuan produk ini — null selama belum dimuat (lazy, baru saat
  /// produk dicentang). Setiap produk tercentang PASTI dapat satuan; tidak
  /// ada lagi kasus "tanpa satuan" seperti versi pertama.
  final List<String>? unitOptions;
  final String? selectedUnit;
  final ValueChanged<double>? onQtyDelta;
  final VoidCallback? onQtyTap;
  final ValueChanged<String>? onUnitChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final checked = row.markedOutOfStock;

    final Color badgeFg;
    final Color badgeBg;
    if (row.stock <= 0) {
      badgeFg = AppTheme.debtFg(isDark);
      badgeBg = AppTheme.debtBg(isDark);
    } else if (row.minStock != null && row.stock < row.minStock!) {
      badgeFg = AppTheme.stockWarnFg(isDark);
      badgeBg = AppTheme.stockWarnBg(isDark);
    } else {
      badgeFg = AppTheme.changeFg(isDark);
      badgeBg = AppTheme.changeBg(isDark);
    }

    final stockLabel =
        row.stock % 1 == 0 ? row.stock.toInt().toString() : row.stock.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: checked ? badgeBg.withOpacity(0.3) : null,
      shape: checked
          ? RoundedRectangleBorder(
              side: BorderSide(color: badgeFg, width: 1),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: CheckboxListTile(
        value: checked,
        onChanged: (v) => onToggle(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          row.name,
          style: TextStyle(
            fontSize: 13,
            decoration: checked ? TextDecoration.lineThrough : null,
          ),
        ),
        // Baris qty order, meniru acuan: [−] [angka] [+] [satuan ▾].
        // Angkanya diketuk utk mengetik lewat dialog. Muncul untuk SETIAP
        // produk tercentang (bukan hanya produk berjenjang).
        subtitle: (checked && unitOptions != null && unitOptions!.isNotEmpty)
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    _QtyBtn(
                        icon: Icons.remove_rounded,
                        onTap: () => onQtyDelta?.call(-1)),
                    // Lebar tetap supaya tombol +/- tidak bergeser saat
                    // angkanya berubah panjang.
                    SizedBox(
                      width: 52,
                      child: InkWell(
                        onTap: onQtyTap,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            fmtQty(qty),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                    _QtyBtn(
                        icon: Icons.add_rounded,
                        onTap: () => onQtyDelta?.call(1)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: DropdownButton<String>(
                        value: unitOptions!.contains(selectedUnit)
                            ? selectedUnit
                            : unitOptions!.first,
                        isDense: true,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        // Warna dari tema — hardcode `Colors.black87` dulu
                        // membuatnya nyaris tak terbaca di mode gelap.
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        items: [
                          for (final u in unitOptions!)
                            DropdownMenuItem(value: u, child: Text(u)),
                        ],
                        onChanged: (v) {
                          if (v != null) onUnitChanged?.call(v);
                        },
                      ),
                    ),
                  ],
                ),
              )
            : null,
        secondary: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: badgeBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            stockLabel,
            style: TextStyle(
                color: badgeFg, fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      ),
    );
  }
}

/// Tombol kecil −/+ untuk qty order. Sengaja bukan `OutlinedButton`/
/// `FilledButton`: keduanya default `minimumSize` lebar-penuh di `AppTheme`
/// dan akan mendesak dropdown satuan keluar layar di HP sempit.
class _QtyBtn extends StatelessWidget {
  const _QtyBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: scheme.onSurface),
      ),
    );
  }
}

class _OrderTextPanel extends StatelessWidget {
  const _OrderTextPanel({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onCopy,
    required this.onShare,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Teks Order Restock',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            // Bisa diedit langsung & dua arah (spt acuan): menyunting baris
            // di sini ikut mengubah centang, jumlah, dan satuan di daftar
            // atas — termasuk menghapus baris = produknya ter-uncheck.
            TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              maxLines: 5,
              minLines: 3,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'Item tercentang muncul di sini — bisa diedit '
                    'langsung, dua arah',
                hintStyle: TextStyle(fontSize: 11),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Salin'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.send_outlined, size: 16),
                    label: const Text('Kirim ke Supplier'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
