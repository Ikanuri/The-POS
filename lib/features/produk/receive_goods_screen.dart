import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/services/receive_text_parser.dart';
import '../../core/theme/app_theme.dart';

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

/// Satu baris di layar review, dgn hasil pencocokannya.
class _Row {
  _Row({required this.parsed, this.unitId, this.label});
  final ParsedReceiveLine parsed;

  /// null = belum ketemu / ambigu → user wajib memilih dulu.
  String? unitId;

  /// Nama produk + satuan terpilih, untuk ditampilkan.
  String? label;

  /// true kalau user memilih manual (bukan hasil pencocokan otomatis) —
  /// dipakai memutuskan apakah pilihannya perlu disimpan ke kamus.
  bool pickedManually = false;
}

class _ReceiveGoodsScreenState extends ConsumerState<ReceiveGoodsScreen> {
  final _textCtrl = TextEditingController();
  List<_Row>? _rows;
  List<String> _unparsed = const [];
  bool _busy = false;

  @override
  void dispose() {
    _textCtrl.dispose();
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

  Future<void> _process() async {
    final text = _textCtrl.text;
    if (text.trim().isEmpty) return;
    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final parsed = ReceiveTextParser.parse(text);
    final rows = <_Row>[];
    for (final line in parsed.lines) {
      final unitId =
          await db.resolveReceiveUnit(name: line.name, unit: line.unit);
      rows.add(_Row(
        parsed: line,
        unitId: unitId,
        label: unitId == null ? null : await _labelFor(unitId),
      ));
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _unparsed = parsed.unparsed;
      _busy = false;
    });
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
        initialQuery: row.parsed.name,
      ),
    );
    if (picked == null || !mounted) return;
    final label = await _labelFor(picked);
    if (!mounted) return;
    setState(() {
      row.unitId = picked;
      row.label = label;
      row.pickedManually = true;
    });
  }

  Future<void> _commit() async {
    final rows = _rows;
    if (rows == null) return;
    final ready = rows.where((r) => r.unitId != null).toList();
    if (ready.isEmpty) return;

    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);

    // Simpan pilihan manual ke kamus DULU — supaya kalau commit stok gagal
    // di tengah, pembelajaran teksnya tetap tidak hilang (user tidak perlu
    // memilih ulang barang yang sama).
    for (final r in ready.where((r) => r.pickedManually)) {
      await db.learnReceiveAlias(
        name: r.parsed.name,
        unit: r.parsed.unit,
        productUnitId: r.unitId!,
      );
    }

    await db.commitReceive(
      entries: [
        for (final r in ready) (productUnitId: r.unitId!, qty: r.parsed.qty),
      ],
      note: AppDatabase.buildReceiveNote(DateTime.now()),
      kasirId: device.deviceCode,
    );

    if (!mounted) return;
    setState(() => _busy = false);
    final skipped = rows.length - ready.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(skipped == 0
          ? '${ready.length} barang masuk ke stok'
          : '${ready.length} barang masuk · $skipped baris dilewati '
              '(belum dipilih produknya)'),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _rows;
    final readyCount = rows?.where((r) => r.unitId != null).length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Penerimaan Barang'),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'Kamus Produk',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const ReceiveAliasScreen(),
            )),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                if (rows != null) ...[
                  const SizedBox(height: 18),
                  Text('Hasil (${rows.length} baris)',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final r in rows) _rowTile(r, scheme),
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

  Widget _rowTile(_Row r, ColorScheme scheme) {
    final matched = r.unitId != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(
          matched ? Icons.check_circle_outline : Icons.help_outline,
          color: matched ? scheme.tertiary : scheme.error,
          size: 20,
        ),
        title: Text(
          matched ? r.label! : r.parsed.name,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          matched
              ? 'Dari teks: "${r.parsed.raw}"'
              : 'Tidak ketemu — pilih produknya',
          style: TextStyle(
              fontSize: 11,
              color: matched ? scheme.onSurfaceVariant : scheme.error),
        ),
        trailing: Text(
          '+${r.parsed.qty % 1 == 0 ? r.parsed.qty.toInt() : r.parsed.qty}'
          '${r.parsed.unit.isEmpty ? '' : ' ${r.parsed.unit}'}',
          style: AppTheme.numStyle(context, size: 13),
        ),
        onTap: () => _pickProduct(r),
      ),
    );
  }
}

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
      'WHERE p.is_active = 1 AND LOWER(p.name) LIKE ? '
      'ORDER BY p.name LIMIT 80',
      variables: [Variable.withString('%$term%')],
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
