import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/providers/laci_meja_provider.dart';
import '../../core/theme/app_theme.dart';

enum _LaciMejaCategory { titipKetinggalan, pinjaman, preorder }

/// Log riwayat gabungan (PLAN.md Item 54 poin 5) — dibuka lewat ikon di
/// AppBar, BUKAN kartu filter keempat: tiga kartu atas itu "berapa yang masih
/// menggantung sekarang", sedangkan ini catatan yang sudah SELESAI. Menaruhnya
/// sebagai kartu keempat akan membaurkan dua makna yang berbeda.
final _showLogProvider = StateProvider<bool>((ref) => false);

final _selectedCategoryProvider =
    StateProvider<_LaciMejaCategory>((ref) => _LaciMejaCategory.titipKetinggalan);

/// Kata kunci pencarian tab Pre-order (permintaan user) — dicocokkan ke NAMA
/// PELANGGAN maupun NAMA PRODUK sekaligus, karena staf bisa datang dari dua
/// arah: "siapa yang antri Gas?" vs "Bu Artia antri apa saja?".
final _preorderSearchProvider = StateProvider<String>((ref) => '');

/// Item 52 ("Laci Meja") — dashboard 3 kartu tappable (sekaligus filter):
/// Titip/Ketinggalan, Pinjaman Barang, Pre-order. Rancangan lengkap:
/// PLAN.md Item 52.
class LaciMejaDashboardScreen extends ConsumerWidget {
  const LaciMejaDashboardScreen({super.key});

  /// Hijau (<7 hari) → kuning (7–29) → merah (≥30), pola sama persis
  /// `HutangTab._overdueColor` — ambang pasti belum ditentukan user utk
  /// kategori ini (lihat catatan di PLAN.md Item 52), dipakai sbg default
  /// sampai ada masukan lebih spesifik.
  static Color _ageColor(int days, bool isDark) {
    if (days >= 30) return AppTheme.debtFg(isDark);
    if (days >= 7) return isDark ? const Color(0xFFF0B54A) : const Color(0xFFB8791A);
    return AppTheme.changeFg(isDark);
  }

  /// Format timestamp — SENGAJA disamakan persis dgn kartu "Riwayat
  /// Pembayaran" (`receipt_screen.dart::_formatDateTime`, permintaan user
  /// eksplisit "timestamp sama formatnya seperti riwayat pembayaran").
  /// Dirakit manual, BUKAN `DateFormat` ber-locale — lihat gotcha
  /// `LocaleDataException` di CLAUDE.md.
  static String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Baris ke-3 kartu (redesain permintaan user): keterangan + timestamp
  /// absolut, diikuti umur relatif yang TETAP diberi warna hijau/kuning/merah
  /// — umur berwarna itu penanda "sudah mengendap berapa lama" yang sudah
  /// dipakai sejak awal, jadi tidak dibuang, cuma didampingi jam pastinya.
  static Widget _metaLine({
    required String leading,
    required DateTime at,
    required int days,
    required bool isDark,
    String? trailing,
  }) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
        children: [
          TextSpan(
              text: '$leading ${_formatDateTime(at)}',
              style: TextStyle(color: AppTheme.laciFg(isDark))),
          TextSpan(
            text: ' · $days hari lalu',
            style: TextStyle(
                color: _ageColor(days, isDark), fontWeight: FontWeight.w600),
          ),
          if (trailing != null && trailing.isNotEmpty)
            TextSpan(
                text: ' · $trailing',
                style: TextStyle(color: AppTheme.laciFg(isDark))),
        ],
      ),
    );
  }

  /// Nama pelanggan yang ditampilkan: UTAMAKAN nama hidup dari nota rujukan
  /// (lihat `laciMejaCustomerNamesProvider`), baru jatuh ke salinan beku yang
  /// tersimpan di baris Laci Meja, terakhir "Umum". Urutan ini yang bikin
  /// entri lama yang terlanjur menyimpan nama basi ikut terkoreksi.
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

  /// Baris ke-1 kartu (redesain permintaan user): NAMA PELANGGAN paling atas,
  /// bold & paling besar — menggantikan nama barang yang dulu di posisi ini.
  static Widget _cardHeader(String customerName, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            customerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  static int _daysSince(DateTime d) => DateTime.now().difference(d).inDays;

  /// Angka bulat tanpa ".0" — qty di sini hampir selalu bilangan bulat
  /// (tabung, krat, sak), tapi kolomnya `real` jadi tetap bisa pecahan.
  static String _n(double v) => v % 1 == 0 ? v.toInt().toString() : '$v';

  /// Baris progres "sudah x dari y" + bar tipis, hanya muncul kalau memang
  /// sudah ada yang diambil sebagian (PLAN.md Item 54 poin 1). Entri yang
  /// belum tersentuh tidak diberi bar supaya daftar tidak jadi ramai.
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
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: AppTheme.laciBg(isDark),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 3),
          Text('$verb ${_n(taken)} dari ${_n(total)}',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(_selectedCategoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    final leftBehind = ref.watch(leftBehindItemsProvider);
    final borrowed = ref.watch(borrowedItemsProvider);
    final preorder = ref.watch(preorderEntriesProvider);

    final showLog = ref.watch(_showLogProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(showLog ? 'Riwayat Laci Meja' : 'Laci Meja'),
        actions: [
          IconButton(
            tooltip: showLog ? 'Kembali ke daftar' : 'Riwayat',
            icon: Icon(showLog ? Icons.list_alt : Icons.history),
            onPressed: () =>
                ref.read(_showLogProvider.notifier).state = !showLog,
          ),
        ],
      ),
      body: showLog
          ? _buildEventLog(context, ref, isDark, scheme)
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    label: 'Titip/Ketinggalan',
                    icon: Icons.inventory_outlined,
                    count: leftBehind.valueOrNull?.length ?? 0,
                    selected: selected == _LaciMejaCategory.titipKetinggalan,
                    onTap: () => ref.read(_selectedCategoryProvider.notifier).state =
                        _LaciMejaCategory.titipKetinggalan,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryCard(
                    label: 'Pinjaman',
                    icon: Icons.swap_horiz,
                    count: borrowed.valueOrNull?.length ?? 0,
                    selected: selected == _LaciMejaCategory.pinjaman,
                    onTap: () => ref.read(_selectedCategoryProvider.notifier).state =
                        _LaciMejaCategory.pinjaman,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryCard(
                    label: 'Pre-order',
                    icon: Icons.hourglass_empty,
                    count: preorder.valueOrNull?.length ?? 0,
                    selected: selected == _LaciMejaCategory.preorder,
                    onTap: () => ref.read(_selectedCategoryProvider.notifier).state =
                        _LaciMejaCategory.preorder,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (selected) {
              _LaciMejaCategory.titipKetinggalan => leftBehind.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (items) => _buildLeftBehindList(context, ref, items, isDark, scheme),
                ),
              _LaciMejaCategory.pinjaman => borrowed.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (items) => _buildBorrowedList(context, ref, items, isDark, scheme),
                ),
              _LaciMejaCategory.preorder => preorder.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (items) => _buildPreorderList(context, ref, items, isDark, scheme),
                ),
            },
          ),
        ],
      ),
    );
  }

  /// PLAN.md Item 54 poin 5 — log gabungan ketiga kategori, urut TERBARU
  /// dulu (kebalikan daftar "masih menggantung" yang FIFO: di sana yang
  /// paling lama menunggu paling mendesak, di sini yang baru saja terjadi
  /// yang paling relevan). Dikelompokkan per hari supaya mudah dibaca.
  Widget _buildEventLog(
      BuildContext context, WidgetRef ref, bool isDark, ColorScheme scheme) {
    final logAsync = ref.watch(laciMejaEventLogProvider);
    return logAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (events) {
        if (events.isEmpty) {
          return Center(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Belum ada riwayat.\nCatatan muncul di sini setiap ada barang '
              'diambil, dikembalikan, atau pre-order dipenuhi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ));
        }
        // Pemisah hari: bandingkan tanggal baris ini dgn baris SEBELUMNYA.
        String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: events.length,
          itemBuilder: (_, i) {
            final e = events[i];
            final showDay =
                i == 0 || dayKey(events[i - 1].createdAt) != dayKey(e.createdAt);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showDay)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 14, bottom: 6),
                    child: Text(_dayLabel(e.createdAt),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurfaceVariant)),
                  ),
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: e.transactionId == null
                        ? null
                        : () => context.push('/kasir/struk/${e.transactionId}'),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 5, right: 10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _entityColor(e.entityType, isDark),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${e.customerName ?? 'Umum'} — '
                                  '${_aksiLabel(e.aksi)}'
                                  '${e.qty > 0 ? ' ${_n(e.qty)}' : ''}',
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_entityLabel(e.entityType)} · ${e.itemName}',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${e.createdAt.hour.toString().padLeft(2, '0')}:'
                            '${e.createdAt.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                                fontSize: 11.5, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Nama hari & bulan Indonesia DIRAKIT MANUAL — `DateFormat` ber-locale
  /// meledak `LocaleDataException` saat build di app ini (tidak pernah
  /// memanggil `initializeDateFormatting`), lihat gotcha CLAUDE.md.
  static const _idMonths = [
    '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    final tanggal = '${d.day} ${_idMonths[d.month]} ${d.year}';
    if (diff == 0) return 'Hari ini · $tanggal';
    if (diff == 1) return 'Kemarin · $tanggal';
    return tanggal;
  }

  static String _aksiLabel(String aksi) => switch (aksi) {
        'ambil' => 'diambil',
        'kembali' => 'kembali',
        'penuhi' => 'dipenuhi',
        'batal' => 'dibatalkan',
        _ => aksi,
      };

  static String _entityLabel(String type) => switch (type) {
        'titip' => 'Titip/Ketinggalan',
        'pinjaman' => 'Pinjaman',
        'preorder' => 'Pre-order',
        _ => type,
      };

  static Color _entityColor(String type, bool isDark) => switch (type) {
        'pinjaman' => AppTheme.scanFg(isDark),
        'preorder' => AppTheme.stockWarnFg(isDark),
        _ => AppTheme.laciFg(isDark),
      };

  Widget _buildLeftBehindList(BuildContext context, WidgetRef ref,
      List<LeftBehindItem> items, bool isDark, ColorScheme scheme) {
    if (items.isEmpty) {
      return Center(
          child: Text('Tidak ada barang titip/ketinggalan.',
              style: TextStyle(color: scheme.onSurfaceVariant)));
    }
    final qtyUnit = ref.watch(leftBehindQtyUnitProvider).valueOrNull ?? {};

    // Item 52 susulan (permintaan user) — barang dari NOTA YANG SAMA
    // dikumpulkan jadi satu "frame" (Card), bukan baris terpisah rata spt
    // sebelumnya (screenshot user: 5 barang beda dari nota berbeda-beda
    // tampil sbg 5 baris identik, susah dibedakan mana yg satu nota).
    // `LinkedHashMap` bawaan Dart Map menjaga urutan insert -> tetap FIFO
    // sesuai `watchLeftBehindItems` (ORDER BY created_at).
    final groups = <String, List<LeftBehindItem>>{};
    for (final e in items) {
      groups.putIfAbsent(e.transactionId, () => []).add(e);
    }
    final txIds = groups.keys.toList();
    final liveNames = ref.watch(laciMejaCustomerNamesProvider).valueOrNull ?? {};

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: txIds.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final group = groups[txIds[i]]!;
        // Satu grup = satu nota, jadi nama pelanggannya pasti sama utk
        // seluruh baris — cukup diambil dari baris pertama.
        final customerName = _customerLabel(
          txId: txIds[i],
          liveNames: liveNames,
          fallback: group.first.customerNameText,
        );
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => context.push('/kasir/struk/${txIds[i]}'),
                  child: _cardHeader(customerName),
                ),
                for (final e in group)
                  _leftBehindTile(context, ref, e, qtyUnit, isDark),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _leftBehindTile(
      BuildContext context,
      WidgetRef ref,
      LeftBehindItem e,
      Map<String, ({double qty, String unitName})> qtyUnit,
      bool isDark) {
    final days = _daysSince(e.createdAt);
    // Permintaan user: tampilkan jumlah qty + jenis satuan produknya
    // (butuh join ke transaction_items via transactionItemId — entri lama
    // tanpa tautan itu cukup tidak menampilkan qty, bukan error).
    final qu = e.transactionItemId != null ? qtyUnit[e.transactionItemId] : null;
    // Susulan (permintaan user): yang ketinggalan/dititip bisa SEBAGIAN dari
    // qty baris nota — `e.qty` (kalau terisi) adalah angka SEBENARNYA yang
    // tertinggal/dititip, BUKAN qty penuh baris nota (`qu.qty`). Null berarti
    // entri lama (dibuat sebelum kolom ini ada) = seluruh qty baris nota.
    final displayQty = e.qty ?? qu?.qty;
    final qtyLabel = displayQty == null
        ? ''
        : ' · ${displayQty % 1 == 0 ? displayQty.toInt() : displayQty}'
                ' ${qu?.unitName ?? ''}'
            .trimRight();
    // Item 52 susulan — tap baris redirect ke nota terkait, mekanisme SAMA
    // PERSIS dgn Buku Hutang (HutangTab -> push '/kasir/struk/:txId'):
    // sama-sama push ANTAR-RUTE DI DALAM satu ShellRoute yang sama, bukan
    // lintas batas shell (lihat dok rute 'laci-meja' di app_router.dart soal
    // kenapa layar ini pindah ke dalam shell).
    final taken = ref.watch(laciMejaTakenQtyProvider).valueOrNull?[e.id] ?? 0;
    final sisa = displayQty == null ? null : displayQty - taken;
    return _EntryRow(
      onTap: () => context.push('/kasir/struk/${e.transactionId}'),
      line2: Text('${e.itemName}$qtyLabel',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      meta: _metaLine(
        leading: e.jenis == 'titip' ? 'Dititip' : 'Ketinggalan',
        at: e.createdAt,
        days: days,
        isDark: isDark,
      ),
      progress: _progressLine(
          taken: taken, total: displayQty, verb: 'Diambil', isDark: isDark),
      trailing: _CollectButton(
        onTap: () async {
          final db = ref.read(databaseProvider);
          final locallyModified = ref.read(laciMejaLocallyModifiedProvider);
          final deviceCode = ref.read(deviceProvider).deviceCode;
          // Entri dgn qty > 1 boleh diambil sebagian; qty 1 atau entri lama
          // tanpa angka acuan langsung ditutup spt sebelumnya (tidak ada yang
          // bisa dipecah, dialog cuma jadi langkah ekstra sia-sia).
          if (sisa != null && sisa > 1) {
            final qty = await _showQtyDialog(
              context,
              title: 'Ambil — ${e.itemName}',
              sisaLabel: 'Sisa belum diambil: ${_n(sisa)} dari ${_n(displayQty!)}',
              sisa: sisa,
              actionLabel: 'Ambil',
            );
            if (qty == null || qty <= 0) return;
            await db.collectLeftBehindQty(e.id, qty,
                total: displayQty,
                locallyModified: locallyModified,
                deviceCode: deviceCode);
            return;
          }
          await db.markLeftBehindCollected(e.id,
              locallyModified: locallyModified,
              sisaQty: sisa,
              deviceCode: deviceCode);
        },
      ),
    );
  }

  /// Item 52 redesain (permintaan user) — grup pinjaman BUKAN per-nota
  /// (beda dari Titip/Ketinggalan) melainkan per-PELANGGAN: satu pelanggan
  /// bisa punya pinjaman dari BEBERAPA nota berbeda, semuanya harus
  /// kelihatan jadi satu grup supaya trackingnya utuh — tiap baris tetap
  /// tertaut ke `transactionId`-nya SENDIRI (bisa beda-beda per baris dalam
  /// satu grup) utk redirect nota masing-masing.
  static String _borrowedGroupKey(BorrowedItem e) =>
      e.customerId ??
      (e.customerNameText != null && e.customerNameText!.trim().isNotEmpty
          ? 'name:${e.customerNameText!.trim()}'
          : 'anon');

  Widget _buildBorrowedList(BuildContext context, WidgetRef ref,
      List<BorrowedItem> items, bool isDark, ColorScheme scheme) {
    if (items.isEmpty) {
      return Center(
          child: Text('Tidak ada pinjaman barang aktif.',
              style: TextStyle(color: scheme.onSurfaceVariant)));
    }
    final groups = <String, List<BorrowedItem>>{};
    for (final e in items) {
      groups.putIfAbsent(_borrowedGroupKey(e), () => []).add(e);
    }
    final keys = groups.keys.toList();
    final liveNames = ref.watch(laciMejaCustomerNamesProvider).valueOrNull ?? {};

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: keys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final group = groups[keys[i]]!;
        // Grup pinjaman per-PELANGGAN (bukan per-nota), jadi barisnya bisa
        // berasal dari nota berbeda-beda. Nama header diambil dari nota baris
        // PERTAMA — kalau grupnya dikunci `customerId`, seluruh baris pasti
        // menunjuk pelanggan yang sama sehingga hasilnya identik; kunci
        // grup sendiri sengaja TIDAK diubah ke nama hidup supaya pembagian
        // grup tidak ikut bergeser saat nota diedit.
        final customerName = _customerLabel(
          txId: group.first.transactionId,
          liveNames: liveNames,
          fallback: group.first.customerNameText,
        );
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardHeader(customerName),
                for (final e in group)
                  _borrowedTile(context, ref, e, isDark),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _borrowedTile(
      BuildContext context, WidgetRef ref, BorrowedItem e, bool isDark) {
    final days = _daysSince(e.createdAt);
    final sisa = e.qty - e.qtyReturned;
    // Tiap baris tetap tertaut ke transactionId MASING-MASING (satu grup
    // pelanggan bisa berisi baris dari nota yang BERBEDA-BEDA).
    return _EntryRow(
      onTap: () => context.push('/kasir/struk/${e.transactionId}'),
      // Baris ke-2 = barang + "yang sevariabel dgn qty" utk pinjaman
      // (permintaan user): sisa vs total pinjaman.
      line2: Text('${e.itemName} · Sisa ${_n(sisa)} dari ${_n(e.qty)}',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      meta: _metaLine(
        leading: 'Dipinjam',
        at: e.createdAt,
        days: days,
        isDark: isDark,
      ),
      progress: _progressLine(
          taken: e.qtyReturned,
          total: e.qty,
          verb: 'Kembali',
          isDark: isDark),
      trailing: TextButton(
        onPressed: () => _showReturnDialog(context, ref, e),
        child: const Text('Kembali'),
      ),
    );
  }

  /// Dialog "ambil/kembali/penuhi sebagian" — dipakai ketiga kategori
  /// (PLAN.md Item 54 poin 1). Prefill SELURUH sisa (kasus paling umum: ambil
  /// semuanya sekaligus), tinggal dikurangi kalau cuma sebagian.
  ///
  /// Hanya DUA tombol dalam satu baris — `AlertDialog.content` selalu
  /// dibungkus `IntrinsicWidth` & lebarnya jauh lebih sempit dari layar, 3
  /// tombol custom bisa sama sekali tidak muat di HP (gotcha CLAUDE.md).
  static Future<double?> _showQtyDialog(
    BuildContext context, {
    required String title,
    required String sisaLabel,
    required double sisa,
    required String actionLabel,
  }) async {
    final controller = TextEditingController(
        text: sisa % 1 == 0 ? sisa.toInt().toString() : '$sisa');
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sisaLabel,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Jumlah'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim().replaceAll(',', '.'));
              if (v == null || v <= 0) return Navigator.pop(ctx);
              // Tidak boleh melebihi sisa — kelebihan input diam-diam
              // dipotong, bukan bikin sisa jadi negatif.
              Navigator.pop(ctx, v > sisa ? sisa : v);
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _showReturnDialog(
      BuildContext context, WidgetRef ref, BorrowedItem e) async {
    final sisa = e.qty - e.qtyReturned;
    final qty = await _showQtyDialog(
      context,
      title: 'Kembali — ${e.itemName}',
      sisaLabel: 'Sisa belum kembali: ${_n(sisa)} dari ${_n(e.qty)}',
      sisa: sisa,
      actionLabel: 'Kembali',
    );
    if (qty == null || qty <= 0) return;
    final db = ref.read(databaseProvider);
    final locallyModified = ref.read(laciMejaLocallyModifiedProvider);
    await db.returnBorrowedItemQty(e.id, qty,
        locallyModified: locallyModified,
        deviceCode: ref.read(deviceProvider).deviceCode);
  }

  /// Item 52 redesain (permintaan user, screenshot device asli) — barang
  /// pre-order dari NOTA YANG SAMA dikumpulkan jadi satu "frame" (Card),
  /// pola SAMA dgn Titip/Ketinggalan — "supaya kalau ada beberapa produk
  /// pre-order dalam satu nota, tidak perlu kocar-kacir". Beda dari
  /// Titip/Ketinggalan: header kartu = nama pelanggan (bold, sekali per
  /// grup, bukan diulang per baris), tiap baris produk format ringkas
  /// "[qty] [produk] - [qty jaminan]".
  Widget _buildPreorderList(BuildContext context, WidgetRef ref,
      List<PreorderEntry> items, bool isDark, ColorScheme scheme) {
    if (items.isEmpty) {
      return Center(
          child: Text('Tidak ada pre-order aktif.',
              style: TextStyle(color: scheme.onSurfaceVariant)));
    }
    final labels = ref.watch(preorderProductUnitLabelsProvider).valueOrNull ?? {};
    final query = ref.watch(_preorderSearchProvider).trim().toLowerCase();

    // Pencarian (permintaan user): cocokkan ke NAMA PELANGGAN atau NAMA
    // PRODUK. Statistik di bawah dihitung dari hasil TERSARING — supaya
    // saat mencari "Gas", angkanya menjawab "berapa Gas yang diantri",
    // bukan total seluruh pre-order (yang sudah terlihat di kartu atas).
    final filtered = query.isEmpty
        ? items
        : items.where((e) {
            final produk =
                (labels[e.productUnitId]?.productName ?? e.productId)
                    .toLowerCase();
            return e.customerName.toLowerCase().contains(query) ||
                produk.contains(query);
          }).toList();

    // Statistik akumulatif — produk & jaminan SENGAJA dipisah (permintaan
    // user): keduanya satuan berbeda maknanya (barang dipesan vs wadah
    // dititip sbg jaminan), menjumlahkannya jadi satu angka menyesatkan.
    final totalQty = filtered.fold<double>(0, (s, e) => s + e.qtyOrdered);
    final totalDeposit = filtered.fold<double>(0, (s, e) => s + e.depositQty);

    // Rincian jaminan per produk (permintaan user, mis. "LPG: 20 jaminan") —
    // hanya entri yang benar-benar punya jaminan (>0) yang dihitung.
    final depositByProduct = <String, double>{};
    for (final e in filtered) {
      if (e.depositQty <= 0) continue;
      final name = labels[e.productUnitId]?.productName ?? e.productId;
      depositByProduct[name] = (depositByProduct[name] ?? 0) + e.depositQty;
    }

    // transactionId NULLABLE (satu-satunya kasus: titip wadah tanpa beli
    // apa pun) — baris begini masing-masing jadi grup sendiri (kunci per id).
    final groups = <String, List<PreorderEntry>>{};
    for (final e in filtered) {
      groups.putIfAbsent(e.transactionId ?? 'no-tx-${e.id}', () => []).add(e);
    }
    final keys = groups.keys.toList();

    return Column(
      children: [
        _PreorderSearchField(
          onChanged: (v) =>
              ref.read(_preorderSearchProvider.notifier).state = v,
        ),
        _PreorderStats(
          totalQty: totalQty,
          totalDeposit: totalDeposit,
          entryCount: filtered.length,
          depositByProduct: depositByProduct,
          isDark: isDark,
        ),
        Expanded(
          child: keys.isEmpty
              ? Center(
                  child: Text('Tidak ada yang cocok dgn "$query".',
                      style: TextStyle(color: scheme.onSurfaceVariant)))
              : _buildPreorderGroups(context, ref, groups, keys, labels, isDark,
                  ref.watch(laciMejaCustomerNamesProvider).valueOrNull ?? {}),
        ),
      ],
    );
  }

  Widget _buildPreorderGroups(
      BuildContext context,
      WidgetRef ref,
      Map<String, List<PreorderEntry>> groups,
      List<String> keys,
      Map<String, ({String productName, String unitName})> labels,
      bool isDark,
      Map<String, String> liveNames) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: keys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final group = groups[keys[i]]!;
        final first = group.first;
        // Pre-order satu-satunya kategori yang menyimpan nama pelanggan TANPA
        // `customerId` sama sekali (lihat `PreorderEntries.customerName`) —
        // justru kategori inilah yang dilaporkan user salah nama. Nama hidup
        // dari nota menutup itu; entri tanpa nota (titip wadah tanpa beli)
        // memang cuma punya salinan bekunya.
        final customerName = _customerLabel(
          txId: first.transactionId,
          liveNames: liveNames,
          fallback: first.customerName,
        );
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: first.transactionId == null
                      ? null
                      : () =>
                          context.push('/kasir/struk/${first.transactionId}'),
                  child: _cardHeader(customerName),
                ),
                for (final e in group)
                  _preorderTile(context, ref, e, labels, isDark),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _preorderTile(
      BuildContext context,
      WidgetRef ref,
      PreorderEntry e,
      Map<String, ({String productName, String unitName})> labels,
      bool isDark) {
    final label = labels[e.productUnitId];
    final productName = label?.productName ?? e.productId;
    final qtyStr =
        e.qtyOrdered % 1 == 0 ? e.qtyOrdered.toInt().toString() : '${e.qtyOrdered}';
    final depositStr = e.depositQty > 0
        ? ' - ${e.depositQty % 1 == 0 ? e.depositQty.toInt() : e.depositQty} jaminan'
        : '';
    final taken = ref.watch(laciMejaTakenQtyProvider).valueOrNull?[e.id] ?? 0;
    final sisa = e.qtyOrdered - taken;
    return _EntryRow(
      // Permintaan user: qty & nama produk dibedakan bold dari sisa baris
      // (jaminan, status bayar).
      line2: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 13.5),
          children: [
            // Bold ditulis EKSPLISIT di span-nya (bukan diwarisi dari style
            // induk) supaya widget test bisa membaca ketebalannya langsung
            // dari span ini — lihat `findBoldableSpan` di test grouping.
            TextSpan(
                text: '$qtyStr $productName',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(
              text: '$depositStr${e.paid ? ' · sudah bayar' : ''}',
              style: TextStyle(
                  fontWeight: FontWeight.w500, color: AppTheme.laciFg(isDark)),
            ),
          ],
        ),
      ),
      meta: _metaLine(
        leading: 'Dipesan',
        at: e.createdAt,
        days: _daysSince(e.createdAt),
        isDark: isDark,
      ),
      progress: _progressLine(
          taken: taken,
          total: e.qtyOrdered,
          verb: 'Dipenuhi',
          isDark: isDark),
      // Tombol "Batal" (hapus pre-order) DIHAPUS atas permintaan user —
      // hanya "Penuhi" yang tersisa. `cancelPreorderEntry`/aksi log 'batal'
      // tetap ada di DB (dipakai jalur lain: sync/riwayat lama), cuma
      // pemicunya dari kartu ini yang dicabut.
      trailing: TextButton(
        onPressed: () async {
          final db = ref.read(databaseProvider);
          final locallyModified = ref.read(laciMejaLocallyModifiedProvider);
          final deviceCode = ref.read(deviceProvider).deviceCode;
          // Pre-order boleh dipenuhi bertahap (kasus user: antri 5 LPG,
          // datang 3 dulu).
          if (sisa > 1) {
            final qty = await _showQtyDialog(
              context,
              title: 'Penuhi — $productName',
              sisaLabel:
                  'Sisa belum dipenuhi: ${_n(sisa)} dari ${_n(e.qtyOrdered)}',
              sisa: sisa,
              actionLabel: 'Penuhi',
            );
            if (qty == null || qty <= 0) return;
            await db.fulfillPreorderQty(e.id, qty,
                locallyModified: locallyModified, deviceCode: deviceCode);
            return;
          }
          await db.fulfillPreorderEntry(e.id,
              locallyModified: locallyModified, deviceCode: deviceCode);
        },
        child: const Text('Penuhi'),
      ),
    );
  }
}

/// Satu baris entri di dalam kartu Laci Meja (redesain permintaan user):
/// baris ke-2 ([line2] — nama barang + qty, bold) di atas baris ke-3
/// ([meta] — timestamp). Nama pelanggan TIDAK di sini, dia jadi header kartu
/// (baris ke-1) supaya tidak berulang tiap baris.
///
/// Kelas terpisah (bukan `Column` inline) DISENGAJA: dipakai ketiga kategori
/// supaya tata letaknya tidak menyimpang satu sama lain, sekaligus memberi
/// widget test satu tipe yang bisa dihitung per kartu — pola yang sama dgn
/// `_MetaTabDivider` di `kasir_screen.dart`. Sebelumnya peran ini dipegang
/// `ListTile`, yang sudah tidak dipakai lagi sejak baris punya 3 tingkat.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.line2,
    required this.meta,
    this.onTap,
    this.trailing,
    this.progress,
  });

  final Widget line2;
  final Widget meta;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Baris progres "sudah x dari y" — hanya terisi kalau entri sudah diambil
  /// SEBAGIAN (PLAN.md Item 54 poin 1). Ditaruh di bawah [meta] supaya urutan
  /// 3 tingkat hasil redesain (nama/barang/timestamp) tidak terganggu.
  final Widget? progress;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                line2,
                const SizedBox(height: 3),
                meta,
                if (progress != null) progress!,
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
    return onTap == null ? body : InkWell(onTap: onTap, child: body);
  }
}

/// Redesain (permintaan user): tombol "Sudah Diambil" disederhanakan jadi
/// pill kecil ikon+label singkat — minimalis tapi TIDAK kotak-persegi rigid
/// (`StadiumBorder`), pola sama semangatnya dgn `_CollectButton` di chip
/// lain app ini (rounded, aksen warna domain Laci Meja).
/// Kotak pencarian tab Pre-order (permintaan user) — `StatefulWidget` sendiri
/// supaya `TextEditingController`-nya tidak dibuat ulang tiap rebuild daftar
/// (kalau dibuat di dalam `build`, kursor melompat ke awal tiap ketikan).
class _PreorderSearchField extends StatefulWidget {
  const _PreorderSearchField({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  State<_PreorderSearchField> createState() => _PreorderSearchFieldState();
}

class _PreorderSearchFieldState extends State<_PreorderSearchField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: TextField(
        controller: _ctrl,
        onChanged: (v) {
          widget.onChanged(v);
          // Rebuild lokal semata utk memunculkan/menyembunyikan tombol clear
          // (state pencariannya sendiri hidup di provider, bukan di sini).
          setState(() {});
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Cari nama pelanggan atau produk…',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _ctrl.clear();
                    widget.onChanged('');
                    setState(() {});
                  },
                ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        ),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
      ),
    );
  }
}

/// Statistik akumulasi tab Pre-order (permintaan user) — total produk dipesan
/// & total jaminan dititip, SENGAJA dipisah jadi dua angka (satuannya beda
/// maknanya: barang yang ditunggu vs wadah yang dipegang toko).
class _PreorderStats extends StatelessWidget {
  const _PreorderStats({
    required this.totalQty,
    required this.totalDeposit,
    required this.entryCount,
    required this.depositByProduct,
    required this.isDark,
  });

  final double totalQty;
  final double totalDeposit;
  final int entryCount;
  final Map<String, double> depositByProduct;
  final bool isDark;

  static String _fmt(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toString();

  @override
  Widget build(BuildContext context) {
    final fg = AppTheme.laciFg(isDark);
    final breakdown = depositByProduct.entries
        .map((e) => (name: e.key, qty: _fmt(e.value)))
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
                label: 'Total produk',
                value: _fmt(totalQty),
                sub: '$entryCount entri',
                fg: fg,
                isDark: isDark),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatTile(
                label: 'Total jaminan',
                value: _fmt(totalDeposit),
                sub: 'jaminan dititip',
                breakdown: breakdown,
                fg: fg,
                isDark: isDark),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.sub,
    this.breakdown = const [],
    required this.fg,
    required this.isDark,
  });

  final String label;
  final String value;
  final String sub;
  final List<({String name, String qty})> breakdown;
  final Color fg;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.laciBg(isDark),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: fg)),
          const SizedBox(height: 2),
          Text(value,
              style: AppTheme.numStyle(context,
                  size: 18, weight: FontWeight.w700, color: fg)),
          Text(sub,
              style: TextStyle(fontSize: 10, color: fg.withOpacity(0.75))),
          for (final line in breakdown)
            Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 10, color: fg.withOpacity(0.75)),
                children: [
                  TextSpan(
                      text: line.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ': '),
                  TextSpan(
                      text: line.qty,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' jaminan'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CollectButton extends StatelessWidget {
  const _CollectButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = AppTheme.laciFg(isDark);
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: fg.withOpacity(0.5))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 16, color: fg),
              const SizedBox(width: 4),
              Text('Ambil',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = AppTheme.laciFg(isDark);
    final bg = AppTheme.laciBg(isDark);
    return Material(
      color: selected ? bg : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? fg : Theme.of(context).colorScheme.outlineVariant,
                width: selected ? 1.5 : 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg, size: 20),
              const SizedBox(height: 4),
              Text('$count',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16, color: fg)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
