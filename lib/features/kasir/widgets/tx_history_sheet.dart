import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_formatters.dart';
import '../merged_receipt_screen.dart';

const _txUuid = Uuid();

/// Parameter query riwayat. Saat tidak ada filter aktif → 100 terakhir;
/// saat ada filter aktif → sampai 1000 agar pencarian menjangkau data lama.
class _HistoryQuery {
  const _HistoryQuery({
    this.date,
    this.product = '',
    this.loadAll = false,
    this.status = 'semua',
  });
  final DateTimeRange? date;
  final String product;
  final bool loadAll;
  final String status; // 'semua' | 'lunas' | 'hutang'

  @override
  bool operator ==(Object other) =>
      other is _HistoryQuery &&
      other.date == date &&
      other.product == product &&
      other.loadAll == loadAll &&
      other.status == status;

  @override
  int get hashCode => Object.hash(date, product, loadAll, status);
}

final _txHistoryProvider =
    FutureProvider.family<List<Transaction>, _HistoryQuery>((ref, q) async {
  final db = ref.watch(databaseProvider);

  Set<String>? productTxIds;
  if (q.product.trim().isNotEmpty) {
    productTxIds = await db.findTxIdsWithProduct(q.product);
    if (productTxIds.isEmpty) return const [];
  }

  final sel = db.select(db.transactions)
    ..where((t) => t.status.isNotValue('void'));
  if (q.status == 'lunas') {
    sel.where((t) => t.status.equals('lunas'));
  } else if (q.status == 'hutang') {
    sel.where((t) =>
        t.status.equals('kurang_bayar') | t.status.equals('tempo'));
  }
  if (q.date != null) {
    final start = DateTime(
        q.date!.start.year, q.date!.start.month, q.date!.start.day);
    final end = DateTime(
        q.date!.end.year, q.date!.end.month, q.date!.end.day, 23, 59, 59, 999);
    sel.where((t) =>
        t.createdAt.isBiggerOrEqualValue(start) &
        t.createdAt.isSmallerOrEqualValue(end));
  }
  sel
    ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
    ..limit(q.loadAll ? 1000 : 100);

  var rows = await sel.get();
  if (productTxIds != null) {
    rows = rows.where((t) => productTxIds!.contains(t.id)).toList();
  }
  return rows;
});

/// Nama pelanggan terdaftar (id → nama) untuk accent & label di riwayat.
final _custNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final db = ref.watch(databaseProvider);
  final cs = await db.searchCustomers('');
  return {for (final c in cs) c.id: c.name};
});

/// Detail produk yang cocok per transaksi saat filter produk aktif.
final _productMatchProvider = FutureProvider.family<
    Map<String, List<({String name, double qty, int price})>>,
    String>((ref, query) async {
  if (query.trim().isEmpty) return {};
  final db = ref.watch(databaseProvider);
  return db.findProductMatchesForQuery(query);
});

/// Sheet riwayat transaksi di kasir: cari, filter status/tanggal/produk,
/// aksi Lunasi · Batalkan · Struk.
class TxHistorySheet extends ConsumerStatefulWidget {
  const TxHistorySheet({super.key});

  @override
  ConsumerState<TxHistorySheet> createState() => _TxHistorySheetState();
}

class _TxHistorySheetState extends ConsumerState<TxHistorySheet> {
  String _query = '';
  String _filter = 'semua'; // semua | lunas | hutang
  String? _expandedId;
  DateTimeRange? _dateFilter;
  String _productQuery = '';
  Timer? _productDebounce;

  // ── Mode gabung nota ──────────────────────────────────────────────────
  bool _selectMode = false;
  final Set<String> _selectedIds = {};
  bool _showSum = false; // toggle "Jumlahkan Semua"

  bool get _hasActiveFilter =>
      _query.isNotEmpty ||
      _filter != 'semua' ||
      _dateFilter != null ||
      _productQuery.isNotEmpty;

  @override
  void dispose() {
    _productDebounce?.cancel();
    super.dispose();
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
      _showSum = false;
    });
  }

  /// Nota retur (total negatif) tidak bisa digabung — tidak ada tagihan untuk
  /// dijumlahkan/dilunasi. Void sudah tidak muncul di riwayat.
  bool _isReturTx(Transaction tx) =>
      tx.internalNote?.startsWith('RETUR:') ?? false;

  /// Toggle seleksi satu nota dengan aturan pelanggan: nota terdaftar hanya
  /// bisa digabung dengan customerId sama; nota umum (customerId null) hanya
  /// dengan sesama umum (boleh beda nama). Kesetaraan customerId menegakkan
  /// kedua aturan sekaligus.
  void _toggleSelect(Transaction tx, List<Transaction> loaded) {
    if (_isReturTx(tx)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nota retur tidak bisa digabung')));
      return;
    }
    if (_selectedIds.contains(tx.id)) {
      setState(() => _selectedIds.remove(tx.id));
      return;
    }
    final selectedTxs =
        loaded.where((t) => _selectedIds.contains(t.id)).toList();
    if (selectedTxs.isNotEmpty &&
        selectedTxs.first.customerId != tx.customerId) {
      final umum = selectedTxs.first.customerId == null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(umum
              ? 'Hanya nota pelanggan umum yang bisa digabung di sini'
              : 'Hanya nota pelanggan yang sama yang bisa digabung')));
      return;
    }
    setState(() => _selectedIds.add(tx.id));
  }

  void _onProductChanged(String v) {
    _productDebounce?.cancel();
    _productDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _productQuery = v.trim());
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _dateFilter,
    );
    if (picked != null) setState(() => _dateFilter = picked);
  }

  @override
  Widget build(BuildContext context) {
    final query = _HistoryQuery(
      date: _dateFilter,
      product: _productQuery,
      loadAll: _hasActiveFilter,
      status: _filter,
    );
    final txAsync = ref.watch(_txHistoryProvider(query));
    final namesAsync = ref.watch(_custNamesProvider);
    final names = namesAsync.valueOrNull ?? const <String, String>{};
    final scheme = Theme.of(context).colorScheme;

    // Produk yang cocok per transaksi (hanya saat filter produk aktif).
    final productMatches = _productQuery.isNotEmpty
        ? ref.watch(_productMatchProvider(_productQuery)).valueOrNull
        : null;

    // Statistik nota terpilih (gabung nota) dari hasil provider, sehingga tetap
    // utuh meski filter teks menyembunyikan baris yang sudah dipilih.
    final loadedTxs = txAsync.valueOrNull ?? const <Transaction>[];
    final selectedTxs =
        loadedTxs.where((t) => _selectedIds.contains(t.id)).toList();
    final sumTotal = selectedTxs.fold<int>(0, (s, t) => s + t.total);
    final sumPaid = selectedTxs.fold<int>(0, (s, t) => s + t.paid);
    final sumSisa = sumTotal - sumPaid;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  _selectMode
                      ? '${_selectedIds.length} nota dipilih'
                      : 'Riwayat Transaksi',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (_selectMode)
                  TextButton(
                    onPressed: _exitSelectMode,
                    child: const Text('Selesai'),
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.playlist_add_check, size: 22),
                    tooltip: 'Gabung Nota',
                    onPressed: () => setState(() => _selectMode = true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Muat ulang',
                    onPressed: () => ref.invalidate(_txHistoryProvider),
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Cari pelanggan atau no. transaksi…',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Filter produk…',
                prefixIcon: Icon(Icons.inventory_2_outlined, size: 18),
                isDense: true,
              ),
              onChanged: _onProductChanged,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final (id, label) in [
                  ('semua', 'Semua'),
                  ('lunas', 'Lunas'),
                  ('hutang', 'Belum Lunas'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: _filter == id,
                      onSelected: (_) => setState(() => _filter = id),
                      visualDensity: VisualDensity.compact,
                      selectedColor: scheme.primaryContainer,
                      side: BorderSide.none,
                    ),
                  ),
                InputChip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: Text(
                    _dateFilter == null
                        ? 'Semua Tanggal'
                        : '${_dateFilter!.start.day}/${_dateFilter!.start.month} – ${_dateFilter!.end.day}/${_dateFilter!.end.month}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _dateFilter != null,
                  showCheckmark: false,
                  onSelected: (_) => _pickDateRange(),
                  onDeleted: _dateFilter != null
                      ? () => setState(() => _dateFilter = null)
                      : null,
                  visualDensity: VisualDensity.compact,
                  selectedColor: scheme.primaryContainer,
                  side: BorderSide.none,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1),
          Expanded(
            child: txAsync.when(
              data: (txs) {
                final filtered = txs.where((tx) {
                  if (_query.isEmpty) return true;
                  final q = _query.toLowerCase();
                  final name = tx.customerName ??
                      (tx.customerId != null
                          ? (names[tx.customerId] ?? '')
                          : '');
                  return tx.localId.toLowerCase().contains(q) ||
                      name.toLowerCase().contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text('Tidak ada transaksi.',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 13)),
                  );
                }

                // Kelompokkan per hari untuk separator tanggal.
                final grouped = <Object>[];
                DateTime? lastDay;
                for (final tx in filtered) {
                  final day = DateTime(tx.createdAt.year,
                      tx.createdAt.month, tx.createdAt.day);
                  if (lastDay == null || day != lastDay) {
                    grouped.add(day);
                    lastDay = day;
                  }
                  grouped.add(tx);
                }

                return ListView.builder(
                  controller: scrollCtrl,
                  itemCount: grouped.length,
                  itemBuilder: (_, i) {
                    final item = grouped[i];
                    if (item is DateTime) {
                      return _DaySeparator(date: item, scheme: scheme);
                    }
                    final t = item as Transaction;
                    return Column(
                      children: [
                        _TxRow(
                          tx: t,
                          names: names,
                          expanded: !_selectMode && _expandedId == t.id,
                          selectMode: _selectMode,
                          selected: _selectedIds.contains(t.id),
                          selectable: !_isReturTx(t),
                          productMatches: productMatches?[t.id],
                          onToggle: () {
                            if (_selectMode) {
                              _toggleSelect(t, loadedTxs);
                            } else {
                              setState(() => _expandedId =
                                  _expandedId == t.id ? null : t.id);
                            }
                          },
                          onChanged: () => ref.invalidate(_txHistoryProvider),
                        ),
                        const Divider(height: 1),
                      ],
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
          if (_selectMode && _selectedIds.isNotEmpty)
            _buildMergeBar(scheme, selectedTxs.length, sumTotal, sumPaid,
                sumSisa),
        ],
      ),
    );
  }

  /// Bar aksi gabung nota: ringkasan akumulatif + cetak/bayar.
  Widget _buildMergeBar(ColorScheme scheme, int count, int sumTotal,
      int sumPaid, int sumSisa) {
    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('$count nota dipilih',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  FilterChip(
                    label: const Text('Jumlahkan Semua',
                        style: TextStyle(fontSize: 11)),
                    selected: _showSum,
                    onSelected: (v) => setState(() => _showSum = v),
                    visualDensity: VisualDensity.compact,
                    selectedColor: scheme.primaryContainer,
                    side: BorderSide.none,
                    showCheckmark: true,
                  ),
                ],
              ),
              if (_showSum) ...[
                const SizedBox(height: 6),
                _sumRow('Total Tagihan', sumTotal, scheme.onSurface),
                _sumRow('Terbayar', sumPaid, scheme.onSurfaceVariant),
                _sumRow('Sisa', sumSisa,
                    sumSisa > 0 ? scheme.error : scheme.primary,
                    bold: true),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Sisa Bayar',
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant)),
                      Text(formatRupiah(sumSisa),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: sumSisa > 0
                                  ? scheme.error
                                  : scheme.primary)),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _cetakGabungan(),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('Cetak Gabungan',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: sumSisa > 0 ? () => _bayarSisa(sumSisa) : null,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Bayar Sisa',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sumRow(String label, int value, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
          Text(formatRupiah(value),
              style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
        ],
      ),
    );
  }

  void _cetakGabungan() {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MergedReceiptScreen(txIds: ids),
    ));
  }

  Future<void> _bayarSisa(int sumSisa) async {
    final ctrl = TextEditingController(
        text: ThousandsSeparatorFormatter.format(sumSisa));
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bayar Sisa Gabungan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total sisa: ${formatRupiah(sumSisa)}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            const Text(
                'Pembayaran dialokasikan ke nota terlama lebih dulu (FIFO).',
                style: TextStyle(fontSize: 11)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: const [ThousandsSeparatorFormatter()],
              decoration: const InputDecoration(
                  prefixText: 'Rp ', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.of(ctx)
                .pop(ThousandsSeparatorFormatter.parseValue(ctrl.text)),
            child: const Text('Bayar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result <= 0 || !mounted) return;

    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final (applied, change) = await db.settleMergedDebt(
      txIds: _selectedIds.toList(),
      amount: result,
      method: 'tunai',
      kasirId: device.deviceCode,
    );
    if (!mounted) return;
    ref.invalidate(_txHistoryProvider);
    final msg = change > 0
        ? 'Dibayar ${formatRupiah(applied)} · kembalian ${formatRupiah(change)}'
        : 'Dibayar ${formatRupiah(applied)}';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
    _exitSelectMode();
  }
}

class _TxRow extends ConsumerWidget {
  const _TxRow({
    required this.tx,
    required this.names,
    required this.expanded,
    required this.onToggle,
    required this.onChanged,
    this.selectMode = false,
    this.selected = false,
    this.selectable = true,
    this.productMatches,
  });

  final Transaction tx;
  final Map<String, String> names;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onChanged;
  final bool selectMode;
  final bool selected;
  final bool selectable;
  final List<({String name, double qty, int price})>? productMatches;

  bool get _isRetur => tx.internalNote?.startsWith('RETUR:') ?? false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isHutang = tx.status == 'kurang_bayar' || tx.status == 'tempo';
    final isRegistered = tx.customerId != null;
    final time =
        '${tx.createdAt.hour.toString().padLeft(2, '0')}:${tx.createdAt.minute.toString().padLeft(2, '0')}';

    return Column(
      children: [
        ListTile(
          dense: true,
          leading: selectMode
              ? Checkbox(
                  value: selected,
                  onChanged: selectable ? (_) => onToggle() : null,
                  visualDensity: VisualDensity.compact,
                )
              : null,
          title: Row(
            children: [
              Text(tx.localId,
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant)),
              if (_isRetur) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('Retur',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: scheme.onTertiaryContainer)),
                ),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _customerLabel(tx),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isRegistered ? scheme.primary : null),
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(time, style: const TextStyle(fontSize: 11)),
              if (productMatches != null && productMatches!.isNotEmpty)
                ...productMatches!.map((m) {
                  final qtyStr = m.qty % 1 == 0
                      ? m.qty.toInt().toString()
                      : '${m.qty}';
                  return Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 12, color: scheme.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${m.name} · $qtyStr × ${formatRupiah(m.price)}',
                            style: TextStyle(
                                fontSize: 11, color: scheme.primary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatRupiah(tx.total),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tx.total < 0 ? scheme.error : null)),
              if (!_isRetur)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isHutang
                        ? scheme.errorContainer
                        : scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isHutang ? 'Belum Lunas' : 'Lunas',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: isHutang
                          ? scheme.onErrorContainer
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                ),
            ],
          ),
          onTap: onToggle,
        ),
        if (expanded)
          _TxDetail(tx: tx, isRetur: _isRetur, onChanged: onChanged),
      ],
    );
  }

  String _customerLabel(Transaction tx) {
    if (tx.customerName != null) return tx.customerName!;
    if (tx.customerId != null) return names[tx.customerId] ?? 'Pelanggan';
    return 'Umum';
  }
}

class _TxDetail extends ConsumerWidget {
  const _TxDetail({
    required this.tx,
    required this.isRetur,
    required this.onChanged,
  });
  final Transaction tx;
  final bool isRetur;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isHutang = tx.status == 'kurang_bayar' || tx.status == 'tempo';
    final names = ref.watch(_custNamesProvider).valueOrNull ?? const <String, String>{};
    final custLabel = tx.customerName ??
        (tx.customerId != null ? (names[tx.customerId] ?? 'Pelanggan') : 'Umum');

    return Container(
      color: scheme.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baris pelanggan — ketuk untuk edit
          InkWell(
            onTap: () => _editCustomer(context, ref),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      custLabel,
                      style: TextStyle(
                          fontSize: 12,
                          color: tx.customerId != null
                              ? scheme.primary
                              : scheme.onSurfaceVariant),
                    ),
                  ),
                  Icon(Icons.edit_outlined, size: 13, color: scheme.primary),
                ],
              ),
            ),
          ),
          if (isHutang)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Dibayar: ${formatRupiah(tx.paid)}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                  Text('Sisa ${formatRupiah(tx.total - tx.paid)}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.error)),
                ],
              ),
            ),
          Row(
            children: [
              if (isHutang) ...[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _lunasi(context, ref),
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: const Text('Lunasi',
                        style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (!isRetur) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showVoidConfirm(context, ref),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Batalkan',
                        style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: scheme.error),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/kasir/struk/${tx.id}');
                  },
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label:
                      const Text('Struk', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editCustomer(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final ctrl = TextEditingController(text: tx.customerName ?? '');
    String? selId = tx.customerId;
    List<Customer> suggestions = [];

    try {
      final result = await showDialog<({String? name, String? id})>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: const Text('Pelanggan'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nama pelanggan',
                    hintText: 'Ketik nama atau cari dari daftar',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) async {
                    selId = null;
                    final found = await db.searchCustomers(v.trim());
                    setSt(() => suggestions = found.take(5).toList());
                  },
                ),
                if (suggestions.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: suggestions.length,
                      itemBuilder: (_, i) {
                        final c = suggestions[i];
                        return ListTile(
                          dense: true,
                          leading:
                              const Icon(Icons.person_outline, size: 18),
                          title: Text(c.name,
                              style: const TextStyle(fontSize: 13)),
                          selected: selId == c.id,
                          onTap: () {
                            ctrl.text = c.name;
                            setSt(() {
                              selId = c.id;
                              suggestions = [];
                            });
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Batal')),
              if (tx.customerId != null || tx.customerName != null)
                TextButton(
                  onPressed: () => Navigator.of(ctx)
                      .pop((name: null, id: null)),
                  child: const Text('Umum'),
                ),
              FilledButton(
                onPressed: () {
                  final name = ctrl.text.trim();
                  Navigator.of(ctx).pop(
                      (name: name.isEmpty ? null : name, id: selId));
                },
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      );

      if (result == null || !context.mounted) return;
      await (db.update(db.transactions)..where((t) => t.id.equals(tx.id)))
          .write(TransactionsCompanion(
        customerName: Value(result.name),
        customerId: Value(result.id),
      ));
      onChanged();
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _lunasi(BuildContext context, WidgetRef ref) async {
    final remaining = tx.total - tx.paid;
    if (remaining <= 0) return;
    final ctrl = TextEditingController(
        text: ThousandsSeparatorFormatter.format(remaining));
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lunasi Transaksi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sisa tagihan: ${formatRupiah(remaining)}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: const [ThousandsSeparatorFormatter()],
              decoration: const InputDecoration(
                  prefixText: 'Rp ', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.of(ctx)
                .pop(ThousandsSeparatorFormatter.parseValue(ctrl.text)),
            child: const Text('Bayar'),
          ),
        ],
      ),
    );

    ctrl.dispose();
    if (result == null || result <= 0 || !context.mounted) return;
    // Uang yang diterima boleh melebihi sisa tagihan → sisanya jadi kembalian.
    final applied = result.clamp(1, remaining); // yang masuk ke tagihan
    final change = result > remaining ? result - remaining : 0; // kembalian

    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
            id: _txUuid.v4(),
            transactionId: tx.id,
            amount: applied,
            method: 'tunai',
            paidAt: Value(DateTime.now()),
            kasirId: Value(device.deviceCode),
          ),
        );
    final newPaid = tx.paid + applied;
    final lunas = newPaid >= tx.total;
    await (db.update(db.transactions)..where((t) => t.id.equals(tx.id)))
        .write(TransactionsCompanion(
      paid: Value(newPaid),
      status: Value(lunas ? 'lunas' : 'kurang_bayar'),
      // Akumulasi kembalian agar tercatat di struk.
      changeAmount: Value(tx.changeAmount + change),
    ));
    onChanged();
    if (context.mounted) {
      final msg = lunas
          ? (change > 0
              ? '${tx.localId} lunas · kembalian ${formatRupiah(change)}'
              : '${tx.localId} lunas')
          : 'Pembayaran dicatat, sisa ${formatRupiah(tx.total - newPaid)}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _showVoidConfirm(BuildContext context, WidgetRef ref) async {
    final confirmed = await showVoidTransactionDialog(context, ref, tx);
    if (confirmed) onChanged();
  }
}

/// Konfirmasi & eksekusi pembatalan transaksi. Mengembalikan true jika benar
/// dibatalkan. Dipakai bersama oleh riwayat & struk.
///
/// Kasir/asisten wajib punya izin `batal_transaksi`; owner selalu boleh.
Future<bool> showVoidTransactionDialog(
    BuildContext context, WidgetRef ref, Transaction tx) async {
  final device = ref.read(deviceProvider);
  final db = ref.read(databaseProvider);

  if (device.deviceRole == 'kasir') {
    final allowed = await db.isPermissionEnabled('batal_transaksi');
    if (!allowed) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tidak punya izin membatalkan transaksi')));
      }
      return false;
    }
  }
  if (!context.mounted) return false;

  final scheme = Theme.of(context).colorScheme;
  final isKurangBayar = tx.status == 'kurang_bayar' || tx.status == 'tempo';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Batalkan Transaksi?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Transaksi ${tx.localId} akan dibatalkan.',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          const Text('• Stok barang akan dikembalikan',
              style: TextStyle(fontSize: 12)),
          const Text('• Poin loyalitas akan dibalik',
              style: TextStyle(fontSize: 12)),
          if (tx.paid > 0 && !isKurangBayar)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  '• Kembalikan ${formatRupiah(tx.paid)} ke pelanggan secara manual',
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            ),
          if (isKurangBayar && tx.paid > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  '• Uang ${formatRupiah(tx.paid)} yang sudah masuk dianggap hangus',
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Tidak Jadi')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Batalkan Transaksi'),
        ),
      ],
    ),
  );

  if (confirmed != true) return false;
  await db.voidTransaction(tx.id, device.deviceCode);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transaksi ${tx.localId} dibatalkan')));
  }
  return true;
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.date, required this.scheme});
  final DateTime date;
  final ColorScheme scheme;

  static const _dayNames = [
    '', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'
  ];
  static const _monthNames = [
    '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    String label;
    if (date == today) {
      label = 'Hari Ini';
    } else if (date == yesterday) {
      label = 'Kemarin';
    } else {
      label =
          '${_dayNames[date.weekday]}, ${date.day} ${_monthNames[date.month]} ${date.year}';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      color: scheme.surfaceContainerHighest.withOpacity(0.4),
      child: Text(label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          )),
    );
  }
}
