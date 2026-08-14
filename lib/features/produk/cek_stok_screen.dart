import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
import 'receive_goods_screen.dart';
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

/// Filter status centang (usulan user) — TEGAK LURUS dgn filter kategori:
/// keduanya bisa dipakai bersamaan (mis. kategori Sembako + hanya yang
/// belum dicentang). Sengaja hanya menyaring DAFTAR yang tampil, TIDAK teks
/// order: kalau teks ikut disaring, memilih "Belum" bikin teksnya kosong dan
/// parser dua-arah akan membatalkan SEMUA centang yang sudah dikumpulkan.
enum _StockFilter { all, checked, unchecked }

final _cekStokFilterProvider =
    StateProvider<_StockFilter>((ref) => _StockFilter.all);

/// Kategori yang DIKECUALIKAN dari teks output (usulan user 25 Juli,
/// meniru `skCatExcluded`/`sk-outcat-bar` di HTML acuan) — produk kategori
/// itu TETAP boleh dicentang & tampil di daftar seperti biasa, HANYA tidak
/// ikut ditulis ke teks "Order Restock". Dipakai utk kategori yang memang
/// tidak pernah dipesan lewat teks ini (mis. LPG dipesan lewat jalur lain).
///
/// Disimpan sbg blob JSON id kategori di tabel settings — pola yang sama
/// dgn `saved_catalogs` (lihat CLAUDE.md): tanpa migrasi skema.
const _kExcludedGroupsSettingKey = 'cek_stok_excluded_output_groups';

class _ExcludedGroupsNotifier extends StateNotifier<Set<int>> {
  _ExcludedGroupsNotifier(this._db) : super(const {}) {
    _load();
  }
  final AppDatabase _db;

  Future<void> _load() async {
    final raw = await _db.getSetting(_kExcludedGroupsSettingKey);
    if (raw == null || raw.isEmpty) return;
    try {
      state = (jsonDecode(raw) as List).map((e) => e as int).toSet();
    } catch (_) {
      // Data lama/rusak — abaikan, jangan sampai layar gagal terbuka.
    }
  }

  Future<void> toggle(int groupId) async {
    final next = Set<int>.from(state);
    if (!next.remove(groupId)) next.add(groupId);
    state = next;
    await _db.setSetting(
        _kExcludedGroupsSettingKey, jsonEncode(next.toList()));
  }
}

final _cekStokExcludedGroupsProvider =
    StateNotifierProvider<_ExcludedGroupsNotifier, Set<int>>(
        (ref) => _ExcludedGroupsNotifier(ref.watch(databaseProvider)));

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
    final statusFilter = ref.watch(_cekStokFilterProvider);
    final excludedGroups = ref.watch(_cekStokExcludedGroupsProvider);
    final groupsAsync = ref.watch(_cekStokGroupsProvider);
    final rowsAsync = ref.watch(_cekStokOverviewProvider(groupId));
    _lastExcluded = excludedGroups;
    final namedGroups =
        groupsAsync.valueOrNull?.where((g) => g.name != null).toList() ??
            const <ProductGroup>[];

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
          // Penerimaan Barang sengaja bertetangga dgn Stock Opname (dua-duanya
          // menyesuaikan stok) tapi TETAP terpisah: penerimaan MENAMBAH,
          // opname MENIMPA jadi hasil hitung fisik.
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Penerimaan Barang',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ReceiveGoodsScreen(),
            )),
          ),
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
          // Filter status centang — berlaku bersamaan dgn filter kategori di
          // atas ("Sembako" + "Belum" = produk Sembako yang belum dicentang).
          //
          // `Row` + `Expanded`, BUKAN ListView horizontal seperti baris
          // kategori: jumlah opsinya tetap 3, jadi membaginya rata membuat
          // ketiganya PASTI muat di lebar apa pun. Versi ListView-nya
          // terukur mendorong chip terakhir ~90px ke luar layar 430px
          // (dgn label berangka) dan masih 3,75px lewat di 360px walau
          // labelnya sudah dipendekkan — chip di luar layar tidak bisa
          // diketuk sama sekali, jadi opsinya seakan tidak ada.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                for (final f in _StockFilter.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _GroupChip(
                        // Label pendek tanpa angka: hitungan yang berguna
                        // (berapa produk masuk order) ada di judul panel teks.
                        label: switch (f) {
                          _StockFilter.all => 'Semua',
                          _StockFilter.checked => 'Dicentang',
                          _StockFilter.unchecked => 'Belum',
                        },
                        selected: statusFilter == f,
                        onTap: () =>
                            ref.read(_cekStokFilterProvider.notifier).state = f,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: rowsAsync.when(
              data: (allRows) {
                if (allRows.isEmpty) {
                  return const Center(
                      child: Text('Tidak ada produk berstok di kategori ini'));
                }
                final rows = switch (statusFilter) {
                  _StockFilter.all => allRows,
                  _StockFilter.checked =>
                    allRows.where((r) => r.markedOutOfStock).toList(),
                  _StockFilter.unchecked =>
                    allRows.where((r) => !r.markedOutOfStock).toList(),
                };
                if (rows.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        statusFilter == _StockFilter.checked
                            ? 'Belum ada produk yang dicentang di sini.'
                            : 'Semua produk di sini sudah dicentang.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  );
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
              // Visibilitas panel pakai centang MENTAH (bukan yg sudah
              // disaring kategori) — kalau tidak, produk yang SEMUA
              // kategorinya kebetulan dikecualikan bikin panel (dan tombol
              // sertakan/kecualikan di dalamnya) hilang total, user jadi
              // tidak bisa menyertakan kategorinya balik.
              final rawChecked =
                  rows.where((r) => r.markedOutOfStock).toList();
              if (rawChecked.isEmpty) return const SizedBox.shrink();
              final visibleChecked = rawChecked
                  .where((r) => !_isExcludedFromOutput(r))
                  .toList();
              return _OrderTextPanel(
                itemCount: visibleChecked.length,
                namedGroups: namedGroups,
                excludedGroupIds: excludedGroups,
                onToggleGroup: (id) => ref
                    .read(_cekStokExcludedGroupsProvider.notifier)
                    .toggle(id),
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
    final checked = rows
        .where((r) => r.markedOutOfStock && !_isExcludedFromOutput(r))
        .toList();
    final text = checked.isEmpty ? '' : _buildOrderText(checked);
    if (_orderCtrl.text == text) return;
    _suppressSync = true;
    _orderCtrl.text = text;
    _suppressSync = false;
  }

  /// Baris terakhir yang diterima dari stream — dipakai [_syncOrderText] &
  /// parser (keduanya berjalan di luar `build`).
  List<StockOverviewRow>? _lastRows;

  /// Kategori yang dikecualikan dari output — disalin dari provider tiap
  /// `build` (sama pola dgn [_lastRows]) supaya [_syncOrderText] &
  /// [_applyOrderText] (jalan di luar `build`) bisa memakainya.
  Set<int> _lastExcluded = const {};

  bool _isExcludedFromOutput(StockOverviewRow r) =>
      r.groupId != null && _lastExcluded.contains(r.groupId);

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
      // Kategori dikecualikan: baris ini TIDAK PERNAH muncul di teks, jadi
      // parser tidak boleh menyentuh centangnya sama sekali — kalau tidak,
      // produk ini akan ke-uncheck begitu saja krn "tidak ada di teks",
      // padahal memang sengaja disembunyikan dari teks (pola sama dgn
      // `if (skCatExcluded(cat)) return;` di acuan).
      if (_isExcludedFromOutput(r)) continue;
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
        label: Text(label,
          style: const TextStyle(fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center),
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
    final scheme = Theme.of(context).colorScheme;
    final checked = row.markedOutOfStock;

    // Badge stok TETAP semantik keparahan (merah kritis/amber menipis/hijau
    // aman) — tidak berubah. Yang berubah: keadaan "terpilih" (di bawah)
    // TIDAK LAGI meminjam warna ini.
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

    // Redesain 25 Juli (mockup, Opsi A dipilih user): dulu baris tercentang
    // memakai `badgeBg`/`badgeFg` — warna KEPARAHAN STOK — utk menandai
    // "terpilih". Efeknya produk kritis (merah) yang dicentang jadi
    // merah-di-atas-merah, dua makna berbeda berbagi satu warna. Sekarang
    // "terpilih" SELALU accent terracotta, badge stok tetap independen.
    final cardColor =
        Theme.of(context).cardTheme.color ?? scheme.surface;
    final selBg = Color.alphaBlend(
        AppTheme.accent.withOpacity(isDark ? 0.16 : 0.07), cardColor);
    final selBorder = AppTheme.accent.withOpacity(isDark ? 0.55 : 0.45);

    return Card(
      key: ValueKey('stock-row-${row.productId}'),
      margin: const EdgeInsets.only(bottom: 6),
      color: checked ? selBg : null,
      shape: checked
          ? RoundedRectangleBorder(
              side: BorderSide(color: selBorder, width: 1),
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
            fontWeight: FontWeight.w600,
            decoration: checked ? TextDecoration.lineThrough : null,
            color: checked ? scheme.onSurfaceVariant : null,
          ),
        ),
        // Baris qty order Opsi A — satu jalur menyatu ber-latar token
        // `field` aplikasi. Muncul untuk SETIAP produk tercentang.
        subtitle: (checked && unitOptions != null && unitOptions!.isNotEmpty)
            ? Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _QtyUnitStepper(
                      qty: qty,
                      fmtQty: fmtQty,
                      unitOptions: unitOptions!,
                      selectedUnit: selectedUnit,
                      onQtyDelta: (d) => onQtyDelta?.call(d),
                      onQtyTap: () => onQtyTap?.call(),
                      onUnitChanged: (u) => onUnitChanged?.call(u),
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
          // Newsreader + tabular figures — token numerik WAJIB aplikasi
          // (`AppTheme.numStyle`) yang sebelumnya diabaikan di layar ini.
          child: Text(stockLabel,
              style: AppTheme.numStyle(context,
                  size: 15, weight: FontWeight.w700, color: badgeFg)),
        ),
      ),
    );
  }
}

/// Stepper jumlah order — Opsi A dari mockup desain (dipilih user 25 Juli):
/// −, angka, +, dan satuan duduk dalam SATU jalur ber-latar token `field`
/// aplikasi (permukaan masukan cekung, dipakai semua `TextField`), dipisah
/// garis 1px per segmen — dibaca sbg satu kontrol, bukan 3 tombol lepas.
/// Paling hemat lebar di antara 3 opsi mockup, penting krn baris ini harus
/// muat bersama checkbox + nama + badge stok di HP 360px.
class _QtyUnitStepper extends StatelessWidget {
  const _QtyUnitStepper({
    required this.qty,
    required this.fmtQty,
    required this.unitOptions,
    required this.selectedUnit,
    required this.onQtyDelta,
    required this.onQtyTap,
    required this.onUnitChanged,
  });

  final double qty;
  final String Function(double) fmtQty;
  final List<String> unitOptions;
  final String? selectedUnit;
  final ValueChanged<double> onQtyDelta;
  final VoidCallback onQtyTap;
  final ValueChanged<String> onUnitChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = scheme.outlineVariant;
    // `inputDecorationTheme.fillColor` PERSIS token `field` aplikasi (dipakai
    // semua TextField) — bukan warna baru, sengaja diambil dari tema supaya
    // otomatis benar di kedua mode tanpa kode terpisah.
    final fieldColor =
        Theme.of(context).inputDecorationTheme.fillColor ?? scheme.surface;
    // Minus MEMBEKU di qty<=1 (lihat `_adjustQty`) — dulu tombolnya tetap
    // tampak aktif walau ditekan tidak berefek. Sekarang diredupkan.
    final canDecrement = qty > 1;
    final unit =
        unitOptions.contains(selectedUnit) ? selectedUnit! : unitOptions.first;

    Widget divider() => Container(width: 1, height: 22, color: line);

    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: fieldColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepGlyph(
            // `onTap` SELALU non-null, walau `!canDecrement` — `_adjustQty`
            // di pemanggil sudah membekukan qty<=1 (no-op). `onTap: null`
            // sempat dipakai di sini & ternyata BUG NYATA: `InkWell` dgn
            // `onTap: null` tidak menyerap gesture-nya, jadi tap MENEMBUS
            // ke `CheckboxListTile` pembungkus & MEMBATALKAN CENTANG
            // seluruh baris — ketahuan lewat test (ikon minus "hilang" di
            // iterasi ke-3 krn baris jadi tak-tercentang). Absorpsi tap
            // (onTap non-null yg jadi no-op) WAJIB dipertahankan.
            icon: Icons.remove_rounded,
            enabled: canDecrement,
            onTap: () => onQtyDelta(-1),
          ),
          divider(),
          InkWell(
            onTap: onQtyTap,
            child: Container(
              constraints: const BoxConstraints(minWidth: 40),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              child: Text(fmtQty(qty),
                  style: AppTheme.numStyle(context, size: 15)),
            ),
          ),
          divider(),
          _StepGlyph(
            icon: Icons.add_rounded,
            enabled: true,
            onTap: () => onQtyDelta(1),
          ),
          divider(),
          PopupMenuButton<String>(
            tooltip: 'Ganti satuan',
            onSelected: onUnitChanged,
            itemBuilder: (_) => [
              for (final u in unitOptions)
                PopupMenuItem(value: u, child: Text(u)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(unit,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent)),
                  const SizedBox(width: 3),
                  Icon(Icons.arrow_drop_down_rounded,
                      size: 16, color: AppTheme.accent.withOpacity(.75)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepGlyph extends StatelessWidget {
  const _StepGlyph(
      {required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;

  /// SENGAJA tidak nullable — [enabled] cuma boleh mempengaruhi TAMPILAN
  /// (redup), bukan `onTap`. `InkWell(onTap: null)` tidak menyerap gesture,
  /// jadi tap-nya menembus ke `CheckboxListTile` pembungkus & membatalkan
  /// centang baris — kelas bug nyata yg ketahuan lewat test, bukan cuma
  /// hipotetis. Pemanggil yg "menonaktifkan" harus tetap memberi callback
  /// (no-op di sisi logika), bukan `null`.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 32,
        height: 34,
        child: Icon(icon,
            size: 16,
            color: scheme.onSurfaceVariant.withOpacity(enabled ? 1 : .38)),
      ),
    );
  }
}

class _OrderTextPanel extends StatelessWidget {
  const _OrderTextPanel({
    required this.itemCount,
    required this.namedGroups,
    required this.excludedGroupIds,
    required this.onToggleGroup,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onCopy,
    required this.onShare,
  });
  final int itemCount;

  /// Kategori (bernama) yang ada di toko — dipakai merender chip
  /// sertakan/kecualikan. Cuma ditampilkan kalau ≥2 kategori (satu kategori
  /// tak ada gunanya dikecualikan — sama spt acuan `skState.cats.length<2`).
  final List<ProductGroup> namedGroups;
  final Set<int> excludedGroupIds;
  final ValueChanged<int> onToggleGroup;
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
            // Hitungan ditaruh di sini, bukan di chip filter: di chip,
            // labelnya jadi terlalu lebar & opsi ketiga terdorong ke luar
            // layar. Di sini justru angka yang paling berguna — berapa
            // produk yang akan ikut terkirim ke supplier.
            Text('Teks Order Restock — $itemCount produk',
                style: Theme.of(context).textTheme.titleSmall),
            if (namedGroups.length >= 2) ...[
              const SizedBox(height: 6),
              _OutputCategoryToggleRow(
                namedGroups: namedGroups,
                excludedGroupIds: excludedGroupIds,
                onToggle: onToggleGroup,
              ),
            ],
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

/// Chip sertakan/kecualikan kategori dari teks output — meniru
/// `sk-outcat-bar`/`skRenderOutCats` di HTML acuan user persis: satu chip
/// per kategori (✓ = ikut, ✕ = dikecualikan), plus hint jumlah yang
/// dikecualikan (centangnya sendiri TETAP aman, cuma tidak ikut teks).
class _OutputCategoryToggleRow extends StatelessWidget {
  const _OutputCategoryToggleRow({
    required this.namedGroups,
    required this.excludedGroupIds,
    required this.onToggle,
  });
  final List<ProductGroup> namedGroups;
  final Set<int> excludedGroupIds;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nExcluded =
        namedGroups.where((g) => excludedGroupIds.contains(g.id)).length;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final g in namedGroups)
          _OutCatChip(
            // Key eksplisit — label chip ini SAMA dengan label chip filter
            // kategori di baris atas (nama kategori yang sama), jadi
            // `find.text(nama)` ambigu antara keduanya; Key membedakannya
            // tanpa bergantung urutan/posisi widget.
            key: ValueKey('outcat-${g.id}'),
            label: g.name!,
            excluded: excludedGroupIds.contains(g.id),
            onTap: () => onToggle(g.id),
          ),
        if (nExcluded > 0)
          Text(
            '$nExcluded kategori dikecualikan dari output (centangnya tetap aman)',
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _OutCatChip extends StatelessWidget {
  const _OutCatChip(
      {super.key,
      required this.label,
      required this.excluded,
      required this.onTap});
  final String label;
  final bool excluded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = excluded ? scheme.onSurfaceVariant : AppTheme.accent;
    return Tooltip(
      message: excluded
          ? 'Dikecualikan dari output — ketuk untuk sertakan'
          : 'Ikut di output — ketuk untuk kecualikan',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: excluded ? scheme.outlineVariant : fg),
            color: excluded
                ? null
                : AppTheme.accent.withOpacity(
                    Theme.of(context).brightness == Brightness.dark
                        ? 0.16
                        : 0.08),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(excluded ? Icons.close_rounded : Icons.check_rounded,
                  size: 12, color: fg),
              const SizedBox(width: 3),
              Text(label, style: TextStyle(fontSize: 11, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
