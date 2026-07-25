import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/inline_banner.dart';

/// Item 36 — Stock Opname (hitung fisik & rekonsiliasi stok).
///
/// Alur: (1) pilih kategori/Semua → (2) hitung BUTA (stok sistem TIDAK
/// ditampilkan, cuma input qty fisik kosong) → (3) review selisih (baru di
/// sini stok sistem vs fisik dibandingkan) → (4) commit sekaligus lewat
/// [AppDatabase.commitOpname]. Riwayat sesi lihat [StockOpnameHistoryScreen].
class StockOpnameScreen extends ConsumerStatefulWidget {
  const StockOpnameScreen({super.key});

  @override
  ConsumerState<StockOpnameScreen> createState() => _StockOpnameScreenState();
}

final _opnameGroupsProvider = FutureProvider<List<ProductGroup>>((ref) {
  return ref.watch(databaseProvider).getAllProductGroups();
});

class _StockOpnameScreenState extends ConsumerState<StockOpnameScreen> {
  int? _selectedGroupId;
  String? _selectedGroupLabel;

  Future<void> _startCount() async {
    final db = ref.read(databaseProvider);
    final rows = await db
        .watchStockOverview(groupId: _selectedGroupId)
        .first;
    if (!mounted) return;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada produk berstok di kategori ini')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _OpnameCountScreen(
        rows: rows,
        categoryLabel: _selectedGroupLabel,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(_opnameGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Opname'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_outlined),
            tooltip: 'Riwayat Opname',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const StockOpnameHistoryScreen(),
            )),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pilih kategori untuk opname sebagian, atau "Semua" untuk '
              'opname seluruh produk. Hitungan dilakukan BUTA — stok sistem '
              'baru ditampilkan saat review, sebelum disimpan.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            groupsAsync.when(
              data: (groups) {
                final named = groups.where((g) => g.name != null).toList();
                return Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _GroupChip(
                      label: 'Semua',
                      selected: _selectedGroupId == null,
                      onTap: () => setState(() {
                        _selectedGroupId = null;
                        _selectedGroupLabel = null;
                      }),
                    ),
                    ...named.map((g) => _GroupChip(
                          label: g.name!,
                          selected: _selectedGroupId == g.id,
                          onTap: () => setState(() {
                            _selectedGroupId = g.id;
                            _selectedGroupLabel = g.name;
                          }),
                        )),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startCount,
                icon: const Icon(Icons.checklist_rounded),
                label: const Text('Mulai Hitung'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Step 2 — hitung BUTA: input qty fisik kosong per produk, TANPA
/// menampilkan stok sistem sama sekali (menghindari bias konfirmasi).
class _OpnameCountScreen extends ConsumerStatefulWidget {
  const _OpnameCountScreen({required this.rows, required this.categoryLabel});
  final List<StockOverviewRow> rows;
  final String? categoryLabel;

  @override
  ConsumerState<_OpnameCountScreen> createState() => _OpnameCountScreenState();
}

/// Item 3 (usulan user) — produk bersatuan berjenjang (>1 satuan, mis.
/// Kg/Dus) boleh dihitung dalam satuan yang lebih nyaman ("10 dus"), bukan
/// wajib satuan dasar ("500 biji"). Konversi ke satuan dasar (`ratioToBase`)
/// terjadi saat lanjut ke review — produk bersatuan tunggal TIDAK berubah
/// tampilannya sama sekali (field polos seperti sebelumnya).
class _UnitChoice {
  _UnitChoice({required this.unit, required this.unitName});
  final ProductUnit unit;
  final String unitName;
}

class _OpnameCountScreenState extends ConsumerState<_OpnameCountScreen> {
  late final Map<String, TextEditingController> _ctrls = {
    for (final r in widget.rows) r.productId: TextEditingController(),
  };
  final Map<String, List<_UnitChoice>> _unitsByProduct = {};
  final Map<String, int> _selectedUnitIdx = {};
  bool _loadingUnits = true;

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    final db = ref.read(databaseProvider);
    for (final r in widget.rows) {
      final units = await db.getProductUnits(r.productId);
      if (units.length <= 1) continue;
      final choices = <_UnitChoice>[];
      for (final u in units) {
        final unitType = await (db.select(db.unitTypes)
              ..where((t) => t.id.equals(u.unitTypeId ?? 1)))
            .getSingleOrNull();
        choices.add(_UnitChoice(unit: u, unitName: unitType?.name ?? 'Satuan'));
      }
      _unitsByProduct[r.productId] = choices;
      _selectedUnitIdx[r.productId] =
          choices.indexWhere((c) => c.unit.isBaseUnit).clamp(0, choices.length - 1);
    }
    if (mounted) setState(() => _loadingUnits = false);
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _goToReview() {
    final entries = <_OpnameEntry>[];
    for (final r in widget.rows) {
      final text = _ctrls[r.productId]!.text.trim().replaceAll(',', '.');
      if (text.isEmpty) continue;
      final entered = double.tryParse(text);
      if (entered == null || entered < 0) continue;

      final choices = _unitsByProduct[r.productId];
      double baseQty = entered;
      double? enteredQty;
      String? enteredUnitName;
      if (choices != null) {
        final idx = _selectedUnitIdx[r.productId] ?? 0;
        final chosen = choices[idx];
        if (chosen.unit.ratioToBase != 1.0) {
          baseQty = entered * chosen.unit.ratioToBase;
          enteredQty = entered;
          enteredUnitName = chosen.unitName;
        }
      }
      entries.add(_OpnameEntry(
        row: r,
        counted: baseQty,
        enteredQty: enteredQty,
        enteredUnitName: enteredUnitName,
      ));
    }
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Isi minimal 1 hitungan sebelum lanjut review')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _OpnameReviewScreen(
        entries: entries,
        categoryLabel: widget.categoryLabel,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryLabel == null
            ? 'Hitung Fisik — Semua'
            : 'Hitung Fisik — ${widget.categoryLabel}'),
      ),
      body: _loadingUnits
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              itemCount: widget.rows.length,
              itemBuilder: (context, i) {
                final r = widget.rows[i];
                final choices = _unitsByProduct[r.productId];
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: choices == null
                        ? Row(
                            children: [
                              Expanded(
                                child: Text(r.name,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                              SizedBox(
                                width: 90,
                                child: _qtyField(r.productId),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Text(r.name,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                              SizedBox(
                                width: 76,
                                child: _qtyField(r.productId),
                              ),
                              const SizedBox(width: 6),
                              DropdownButton<int>(
                                value: _selectedUnitIdx[r.productId] ?? 0,
                                isDense: true,
                                underline: const SizedBox.shrink(),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black87),
                                items: [
                                  for (var j = 0; j < choices.length; j++)
                                    DropdownMenuItem(
                                      value: j,
                                      child: Text(choices[j].unitName),
                                    ),
                                ],
                                onChanged: (v) => setState(() =>
                                    _selectedUnitIdx[r.productId] = v ?? 0),
                              ),
                            ],
                          ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _goToReview,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Review Selisih'),
          ),
        ),
      ),
    );
  }

  Widget _qtyField(String productId) => TextField(
        controller: _ctrls[productId],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
          hintText: '0',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
      );
}

class _OpnameEntry {
  _OpnameEntry({
    required this.row,
    required this.counted,
    this.enteredQty,
    this.enteredUnitName,
  });
  final StockOverviewRow row;

  /// SELALU dalam satuan DASAR (dipakai diff & commit) — kalau dihitung
  /// dalam satuan berjenjang (mis. dus), nilai ini sudah dikonversi.
  final double counted;

  /// Qty & nama satuan APA ADANYA yang diketik user, sebelum dikonversi —
  /// null kalau dihitung langsung dalam satuan dasar (tampilan review sama
  /// seperti sebelumnya, tidak ada info tambahan).
  final double? enteredQty;
  final String? enteredUnitName;

  double get selisih => counted - row.stock;
}

/// Step 3 — review: baru di sini stok sistem vs hasil hitung fisik
/// dibandingkan berdampingan, sebelum benar-benar commit ke database.
class _OpnameReviewScreen extends ConsumerStatefulWidget {
  const _OpnameReviewScreen(
      {required this.entries, required this.categoryLabel});
  final List<_OpnameEntry> entries;
  final String? categoryLabel;

  @override
  ConsumerState<_OpnameReviewScreen> createState() =>
      _OpnameReviewScreenState();
}

class _OpnameReviewScreenState extends ConsumerState<_OpnameReviewScreen>
    with InlineBannerStateMixin<_OpnameReviewScreen> {
  bool _saving = false;

  String _fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  Future<void> _commit() async {
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final changed =
        widget.entries.where((e) => e.selisih != 0).toList();
    if (changed.isEmpty) {
      setState(() => _saving = false);
      showBanner('Tidak ada selisih — tidak ada yang perlu disimpan',
          type: InlineBannerType.info);
      return;
    }
    final note = AppDatabase.buildOpnameNote(DateTime.now(),
        categoryLabel: widget.categoryLabel);
    try {
      await db.commitOpname(
        entries: changed
            .map((e) => (
                  productUnitId: e.row.unitId,
                  newQty: e.counted,
                ))
            .toList(),
        note: note,
        kasirId: device.deviceCode,
      );
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == '/');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Opname disimpan (${changed.length} produk disesuaikan)')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError('Gagal menyimpan opname: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final diffCount = widget.entries.where((e) => e.selisih != 0).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Review Selisih')),
      body: Column(
        children: [
          inlineBanner(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: widget.entries.length,
              itemBuilder: (context, i) {
                final e = widget.entries[i];
                final hasDiff = e.selisih != 0;
                final Color fg = e.selisih > 0
                    ? AppTheme.changeFg(isDark)
                    : (e.selisih < 0
                        ? AppTheme.debtFg(isDark)
                        : scheme.onSurfaceVariant);
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(e.row.name,
                                  style: const TextStyle(fontSize: 13)),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text('Sistem: ${_fmt(e.row.stock)}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant)),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text('Fisik: ${_fmt(e.counted)}',
                                  style: const TextStyle(fontSize: 11)),
                            ),
                            SizedBox(
                              width: 64,
                              child: Text(
                                hasDiff
                                    ? '${e.selisih > 0 ? '+' : ''}${_fmt(e.selisih)}'
                                    : '-',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: fg),
                              ),
                            ),
                          ],
                        ),
                        // Item 3 (usulan user) — dihitung dlm satuan
                        // berjenjang (mis. dus), tampilkan apa yg diketik
                        // user apa adanya di samping hasil konversinya.
                        if (e.enteredQty != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'diketik: ${_fmt(e.enteredQty!)} ${e.enteredUnitName}',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontStyle: FontStyle.italic,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _commit,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(diffCount == 0
                ? 'Simpan (tidak ada selisih)'
                : 'Simpan ($diffCount produk beda)'),
          ),
        ),
      ),
    );
  }
}

/// Riwayat sesi opname (Item 36, poin "perlu riwayat, catat ke task").
class StockOpnameHistoryScreen extends ConsumerWidget {
  const StockOpnameHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Opname')),
      body: FutureBuilder<List<OpnameSessionSummary>>(
        future: ref.read(databaseProvider).getOpnameSessions(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snap.data!;
          if (sessions.isEmpty) {
            return const Center(child: Text('Belum ada sesi opname'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sessions.length,
            itemBuilder: (context, i) {
              final s = sessions[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  title: Text(s.note, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                      '${s.itemCount} produk disesuaikan',
                      style: const TextStyle(fontSize: 11)),
                  trailing: Text(
                    '${s.createdAt.day.toString().padLeft(2, '0')}/'
                    '${s.createdAt.month.toString().padLeft(2, '0')}/'
                    '${s.createdAt.year} '
                    '${s.createdAt.hour.toString().padLeft(2, '0')}:'
                    '${s.createdAt.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _OpnameSessionDetailScreen(session: s),
                  )),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _OpnameSessionDetailScreen extends ConsumerWidget {
  const _OpnameSessionDetailScreen({required this.session});
  final OpnameSessionSummary session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(session.note)),
      body: FutureBuilder<List<OpnameSessionDetailRow>>(
        future: ref.read(databaseProvider).getOpnameSessionDetail(
            createdAt: session.createdAt, note: session.note),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final r = rows[i];
              final v = r.qtyChange;
              final label = v % 1 == 0 ? v.toInt().toString() : v.toString();
              return ListTile(
                dense: true,
                title: Text(r.productName, style: const TextStyle(fontSize: 13)),
                trailing: Text(
                  '${v > 0 ? '+' : ''}$label',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
