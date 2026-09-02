import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/laci_meja_provider.dart';
import '../../core/theme/app_theme.dart';
import 'laci_meja_date_utils.dart';
import 'laci_meja_expandable_search.dart';
import 'product_picker_dropdown.dart';

/// Layar "Riwayat Laci Meja" (permintaan user) — BEDA dari
/// `LaciMejaDashboardScreen`: dashboard cuma menampilkan entri yang MASIH
/// TERBUKA (perlu ditindaklanjuti sekarang), layar ini menampilkan SEMUA
/// entri ketiga kategori — terbuka MAUPUN sudah selesai (diambil/
/// dikembalikan/dipenuhi/dibatalkan) — sbg arsip yang bisa dicari & difilter.
///
/// 3 kategori dipisah lewat TabBar (pola sama persis `laporan_screen.dart`),
/// bukan dicampur satu daftar spt log gabungan lama (`_buildEventLog` di
/// dashboard) — permintaan user eksplisit "pisahkan antara ketiga kategori".
///
/// Query DASAR dipakai ulang dari `AppDatabase` yang SUDAH ADA
/// (`watchLeftBehindItems(includeCollected: true)` dkk. — parameter ini
/// sudah lama tersedia, cuma belum pernah dipakai UI manapun), BUKAN query
/// baru. Pencarian/filter tanggal/filter produk dilakukan di sisi Dart
/// (pola sama dgn `_buildPreorderList` dashboard yang sudah lebih dulu
/// memfilter hasil stream client-side) — volume data toko ini kecil
/// (harian/toko tunggal), jadi tidak perlu query SQL terpisah per kombinasi
/// filter.
class RiwayatLaciMejaScreen extends ConsumerStatefulWidget {
  const RiwayatLaciMejaScreen({super.key});

  @override
  ConsumerState<RiwayatLaciMejaScreen> createState() =>
      _RiwayatLaciMejaScreenState();
}

class _RiwayatLaciMejaScreenState extends ConsumerState<RiwayatLaciMejaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 3, vsync: this);
  String _query = '';
  // Susulan (permintaan user, layout sempit HP 360-400dp) — status
  // expand/collapse field cari, lihat `LaciMejaExpandableSearch`.
  bool _searchExpanded = false;
  DateTimeRange? _dateFilter;
  String? _productFilter;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  bool _inRange(DateTime d) {
    final range = _dateFilter;
    if (range == null) return true;
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(
        range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    // Chip produk (khusus tab Pre-order) HANYA masuk akal saat tab itu aktif
    // — daftar produknya sendiri baru dihitung di build tab pre-order, tapi
    // kita perlu tahu tab mana yg aktif utk menampilkan barisnya di sini.
    final showProductFilter = _tabController.index == 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Laci Meja'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          onTap: (_) => setState(() {}), // refresh chip produk show/hide
          tabs: const [
            Tab(text: 'Titip/Ketinggalan'),
            Tab(text: 'Pinjaman'),
            Tab(text: 'Pre-order'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Susulan (permintaan user, screenshot: field cari full-width
          // bikin baris filter tanggal/produk di bawahnya sempit/terpotong
          // di HP 360-400dp) — field cari jadi expandable (pola SAMA PERSIS
          // dgn dashboard Laci Meja tab Pre-order, lihat `LaciMejaExpandableSearch`),
          // filter tanggal & produk jadi sejajar di baris yang sama saat
          // collapsed (bukan lagi baris terpisah di bawah field cari).
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                if (_searchExpanded)
                  Expanded(
                    child: LaciMejaExpandableSearch(
                      hintText: 'Cari nama, barang, atau catatan…',
                      expanded: _searchExpanded,
                      onExpandedChanged: (v) =>
                          setState(() => _searchExpanded = v),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  )
                else ...[
                  LaciMejaExpandableSearch(
                    hintText: 'Cari nama, barang, atau catatan…',
                    expanded: _searchExpanded,
                    onExpandedChanged: (v) =>
                        setState(() => _searchExpanded = v),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Filter tanggal — SUDAH satu tombol/chip tunggal
                          // (tap membuka date-range picker, "x" muncul
                          // kalau aktif utk membersihkan) sejak awal dibuat
                          // — TIDAK diubah, sudah sesuai permintaan user.
                          InputChip(
                            avatar: const Icon(Icons.date_range, size: 16),
                            label: Text(
                              _dateFilter == null
                                  ? 'Semua Tanggal'
                                  : '${_dateFilter!.start.day}/${_dateFilter!.start.month} – '
                                      '${_dateFilter!.end.day}/${_dateFilter!.end.month}',
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
                          // Filter produk (tab Pre-order) — dropdown pola
                          // SAMA PERSIS `ProductPickerDropdown` yang dipakai
                          // dashboard (permintaan user eksplisit "opsi
                          // dropdown design anda kemarin itu sudah paling
                          // pas"), BUKAN lagi chip `ChoiceChip`.
                          if (showProductFilter &&
                              _lastProductNames.length > 1) ...[
                            const SizedBox(width: 6),
                            ProductPickerDropdown(
                              entries: {
                                for (final e in _lastProductNames.entries)
                                  e.key: (name: e.value, badge: null),
                              },
                              selectedId: _productFilter,
                              allLabel: 'Semua Produk',
                              tooltip: 'Filter produk',
                              onSelected: (id) =>
                                  setState(() => _productFilter = id),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLeftBehindTab(isDark, scheme),
                _buildBorrowedTab(isDark, scheme),
                _buildPreorderTab(isDark, scheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Diisi tiap kali tab Pre-order dibangun — dipakai dropdown filter produk
  // di atas TabBarView.
  Map<String, String> _lastProductNames = const {};

  // ── Titip/Ketinggalan ──

  Widget _buildLeftBehindTab(bool isDark, ColorScheme scheme) {
    final itemsAsync = ref.watch(riwayatLeftBehindAllProvider);
    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        final liveNames =
            ref.watch(riwayatCustomerNamesProvider).valueOrNull ?? {};
        final taken = ref.watch(riwayatTakenQtyProvider).valueOrNull ?? {};
        final query = _query.trim().toLowerCase();
        final filtered = items.where((e) {
          if (!_inRange(e.createdAt)) return false;
          if (query.isEmpty) return true;
          final name = _customerLabel(
              txId: e.transactionId,
              liveNames: liveNames,
              fallback: e.customerNameText);
          return name.toLowerCase().contains(query) ||
              e.itemName.toLowerCase().contains(query) ||
              (e.note ?? '').toLowerCase().contains(query);
        }).toList();
        if (filtered.isEmpty) return _emptyState(scheme, items.isEmpty);
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final e = filtered[i];
            final name = _customerLabel(
                txId: e.transactionId,
                liveNames: liveNames,
                fallback: e.customerNameText);
            final done = e.collectedAt != null;
            final takenQty = taken[e.id] ?? 0;
            final total = e.qty;
            return _RiwayatCard(
              onTap: () => context.push('/kasir/struk/${e.transactionId}'),
              title: name,
              subtitle: e.itemName,
              statusText: done
                  ? 'Selesai · diambil ${_fmtDateTime(e.collectedAt!)}'
                  : 'Terbuka',
              statusColor:
                  done ? AppTheme.changeFg(isDark) : AppTheme.stockWarnFg(isDark),
              metaLeading: e.jenis == 'titip' ? 'Dititip' : 'Ketinggalan',
              createdAt: e.createdAt,
              progress: !done && total != null
                  ? _progressLine(
                      taken: takenQty, total: total, verb: 'Diambil', isDark: isDark)
                  : null,
              isDark: isDark,
            );
          },
        );
      },
    );
  }

  // ── Pinjaman ──

  Widget _buildBorrowedTab(bool isDark, ColorScheme scheme) {
    final itemsAsync = ref.watch(riwayatBorrowedAllProvider);
    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        final liveNames =
            ref.watch(riwayatCustomerNamesProvider).valueOrNull ?? {};
        final query = _query.trim().toLowerCase();
        final filtered = items.where((e) {
          if (!_inRange(e.createdAt)) return false;
          if (query.isEmpty) return true;
          final name = _customerLabel(
              txId: e.transactionId,
              liveNames: liveNames,
              fallback: e.customerNameText);
          return name.toLowerCase().contains(query) ||
              e.itemName.toLowerCase().contains(query) ||
              (e.note ?? '').toLowerCase().contains(query);
        }).toList();
        if (filtered.isEmpty) return _emptyState(scheme, items.isEmpty);
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final e = filtered[i];
            final name = _customerLabel(
                txId: e.transactionId,
                liveNames: liveNames,
                fallback: e.customerNameText);
            final done = e.fullyReturnedAt != null;
            return _RiwayatCard(
              onTap: () => context.push('/kasir/struk/${e.transactionId}'),
              title: name,
              subtitle: e.itemName,
              statusText: done
                  ? 'Selesai · kembali ${_fmtDateTime(e.fullyReturnedAt!)}'
                  : 'Terbuka',
              statusColor:
                  done ? AppTheme.changeFg(isDark) : AppTheme.stockWarnFg(isDark),
              metaLeading: 'Dipinjam',
              createdAt: e.createdAt,
              progress: !done
                  ? _progressLine(
                      taken: e.qtyReturned,
                      total: e.qty,
                      verb: 'Kembali',
                      isDark: isDark)
                  : null,
              isDark: isDark,
            );
          },
        );
      },
    );
  }

  // ── Pre-order ──

  Widget _buildPreorderTab(bool isDark, ColorScheme scheme) {
    final itemsAsync = ref.watch(riwayatPreorderAllProvider);
    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        final liveNames =
            ref.watch(riwayatCustomerNamesProvider).valueOrNull ?? {};
        final taken = ref.watch(riwayatTakenQtyProvider).valueOrNull ?? {};
        final labels =
            ref.watch(riwayatPreorderProductUnitLabelsProvider).valueOrNull ?? {};

        String productNameOf(PreorderEntry e) =>
            labels[e.productUnitId]?.productName ?? e.productId;

        // Daftar produk (utk chip filter) dihitung dari SELURUH riwayat
        // (bukan hasil tersaring) — supaya chipnya stabil begitu user
        // mengetik kata kunci pencarian.
        final productNames = <String, String>{};
        for (final e in items) {
          productNames[e.productId] = productNameOf(e);
        }
        // Dipakai chip filter produk yg dirender di atas TabBarView.
        _lastProductNames = productNames;

        final query = _query.trim().toLowerCase();
        final filtered = items.where((e) {
          if (_productFilter != null && e.productId != _productFilter) {
            return false;
          }
          if (!_inRange(e.createdAt)) return false;
          if (query.isEmpty) return true;
          final name = _customerLabel(
              txId: e.transactionId, liveNames: liveNames, fallback: e.customerName);
          return name.toLowerCase().contains(query) ||
              productNameOf(e).toLowerCase().contains(query) ||
              (e.note ?? '').toLowerCase().contains(query);
        }).toList();

        // Chip filter produk TIDAK lagi dirender di sini — sudah pindah jadi
        // dropdown (`ProductPickerDropdown`) sejajar dgn field cari & filter
        // tanggal di atas `TabBarView` (lihat `build`), supaya baris tab ini
        // tidak dobel dgn baris filter di atasnya.
        return Column(
          children: [
            Expanded(
              child: filtered.isEmpty
                  ? _emptyState(scheme, items.isEmpty)
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        final name = _customerLabel(
                            txId: e.transactionId,
                            liveNames: liveNames,
                            fallback: e.customerName);
                        final takenQty = taken[e.id] ?? 0;
                        String statusText;
                        Color statusColor;
                        if (e.cancelledAt != null) {
                          statusText = 'Dibatalkan ${_fmtDateTime(e.cancelledAt!)}';
                          statusColor = AppTheme.debtFg(isDark);
                        } else if (e.fulfilledAt != null) {
                          statusText = 'Dipenuhi ${_fmtDateTime(e.fulfilledAt!)}';
                          statusColor = AppTheme.changeFg(isDark);
                        } else {
                          statusText = e.paid ? 'Terbuka · Lunas' : 'Terbuka · Tempo';
                          statusColor = AppTheme.stockWarnFg(isDark);
                        }
                        final open =
                            e.cancelledAt == null && e.fulfilledAt == null;
                        return _RiwayatCard(
                          onTap: e.transactionId == null
                              ? null
                              : () => context
                                  .push('/kasir/struk/${e.transactionId}'),
                          title: name,
                          subtitle:
                              '${_n(e.qtyOrdered)} ${productNameOf(e)}'
                              '${e.depositQty > 0 ? ' - ${_n(e.depositQty)} jaminan' : ''}',
                          statusText: statusText,
                          statusColor: statusColor,
                          metaLeading: 'Dipesan',
                          createdAt: e.createdAt,
                          progress: open
                              ? _progressLine(
                                  taken: takenQty,
                                  total: e.qtyOrdered,
                                  verb: 'Dipenuhi',
                                  isDark: isDark)
                              : null,
                          isDark: isDark,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyState(ColorScheme scheme, bool noDataAtAll) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            noDataAtAll
                ? 'Belum ada riwayat di kategori ini.'
                : 'Tidak ada yang cocok dgn pencarian/filter saat ini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );

  static String _n(double v) => v % 1 == 0 ? v.toInt().toString() : '$v';

  static String _fmtDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Sama persis pola `_customerLabel` di `laci_meja_dashboard_screen.dart`
  /// (nama hidup dari nota > salinan beku > "Umum") — diduplikasi (bukan
  /// diimpor) krn versi dashboard itu `private` ke file itu.
  static String _customerLabel({
    required String? txId,
    required Map<String, String> liveNames,
    required String? fallback,
  }) {
    final live = txId == null ? null : liveNames[txId];
    if (live != null && live.isNotEmpty) return live;
    final fb = fallback?.trim();
    if (fb != null && fb.isNotEmpty) return fb;
    return 'Umum';
  }

  static Color _ageColor(int days, bool isDark) {
    if (days >= 30) return AppTheme.debtFg(isDark);
    if (days >= 7) return isDark ? const Color(0xFFF0B54A) : const Color(0xFFB8791A);
    return AppTheme.changeFg(isDark);
  }

  static Widget? _progressLine({
    required double taken,
    required double? total,
    required String verb,
    required bool isDark,
  }) {
    if (taken <= 0 || total == null || total <= 0) return null;
    final ratio = (taken / total).clamp(0.0, 1.0);
    final done = taken >= total;
    final color = done ? AppTheme.changeFg(isDark) : AppTheme.stockWarnFg(isDark);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$verb ${_n(taken)} dari ${_n(total)}',
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: color.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu kartu baris riwayat — dipakai ketiga tab (Titip/Ketinggalan,
/// Pinjaman, Pre-order), lebih ringkas dari kartu dashboard (tanpa grouping
/// per-nota) krn riwayat menampilkan entri terbuka+selesai bercampur.
class _RiwayatCard extends StatelessWidget {
  const _RiwayatCard({
    required this.title,
    required this.subtitle,
    required this.statusText,
    required this.statusColor,
    required this.metaLeading,
    required this.createdAt,
    required this.isDark,
    this.onTap,
    this.progress,
  });

  final String title;
  final String subtitle;
  final String statusText;
  final Color statusColor;
  final String metaLeading;
  final DateTime createdAt;
  final bool isDark;
  final VoidCallback? onTap;
  final Widget? progress;

  @override
  Widget build(BuildContext context) {
    final days = calendarDaysSince(createdAt);
    final card = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 6),
                Text(statusText,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: statusColor)),
              ],
            ),
            const SizedBox(height: 3),
            Text(subtitle,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                children: [
                  TextSpan(
                      text:
                          '$metaLeading ${_RiwayatLaciMejaScreenState._fmtDateTime(createdAt)}',
                      style: TextStyle(color: AppTheme.laciFg(isDark))),
                  TextSpan(
                    text: ' · $days hari lalu',
                    style: TextStyle(
                        color: _RiwayatLaciMejaScreenState._ageColor(days, isDark),
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (progress != null) progress!,
          ],
        ),
      ),
    );
    return onTap == null ? card : InkWell(onTap: onTap, child: card);
  }
}
