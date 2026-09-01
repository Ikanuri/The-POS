import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/providers/laci_meja_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/marquee_text.dart';
import 'preorder_quota_store.dart';

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

/// Filter produk tab Pre-order (permintaan user) — PELENGKAP pencarian, bukan
/// penggantinya: garis pembatas kuota hanya masuk akal untuk SATU produk
/// (tiap produk kuotanya sendiri-sendiri), jadi butuh pilihan yang tegas
/// "produk ini", bukan kata kunci yang bisa mengenai beberapa produk. null =
/// semua produk.
final _preorderProductFilterProvider = StateProvider<String?>((ref) => null);

/// Produk yang jaminannya DITAMPILKAN LANGSUNG di chip statistik (permintaan
/// user) — sebelumnya rincian per produk cuma bisa dilihat lewat tooltip yang
/// harus di-tap tiap kali. null = belum dipilih, jatuh ke produk PERTAMA yang
/// punya jaminan (lihat `_buildPreorderList`). Produk lain tetap bisa dilihat
/// lewat dropdown di chip yang sama.
final _preorderJaminanDisplayProvider = StateProvider<String?>((ref) => null);

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
  static Widget _cardHeader(String customerName,
      {Widget? trailing, Widget? leading, bool accent = false}) {
    return Row(
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 6)],
        Expanded(
          child: Text(
            customerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
                // Nama pelanggan TERDAFTAR ikut aksen terracotta juga
                // (permintaan user), bukan cuma ikon di depannya — dulu
                // ikonnya kecil di pinggir, gampang terlewat.
                color: accent ? AppTheme.accent : null),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  static bool _isRegisteredCustomer(String? customerId) =>
      customerId != null && customerId.isNotEmpty;

  /// Penanda pelanggan TERDAFTAR vs nama ad-hoc (permintaan user). Sinyalnya
  /// `customerId`: terisi = pelanggan yang punya record (riwayat, hutang,
  /// pinjaman lamanya bisa ditelusuri), null = nama yang cuma diketik saat
  /// itu (lihat `CartMeta`/`Transactions.customerName`). Perbedaan ini
  /// penting saat menagih wadah/pre-order — yang ad-hoc tidak punya jejak
  /// lain untuk dihubungi.
  ///
  /// Ikon dipakai sbg pembeda utama (bukan warna saja) supaya tetap terbaca
  /// di layar HP murah/kontras rendah maupun bagi yang sulit membedakan warna.
  static Widget _customerTypeIcon(String? customerId, bool isDark) {
    final terdaftar = _isRegisteredCustomer(customerId);
    return Icon(
      terdaftar ? Icons.person : Icons.person_outline,
      size: 16,
      color: terdaftar ? AppTheme.accent : AppTheme.laciFg(isDark),
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
                  child: _cardHeader(
                    customerName,
                    leading:
                        _customerTypeIcon(group.first.customerId, isDark),
                    accent: _isRegisteredCustomer(group.first.customerId),
                  ),
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
        // Sematan disimpan per baris, tapi dinyalakan/dimatikan sekaligus
        // untuk seluruh grup — lihat dok `setBorrowedPinned`.
        final pinned = group.any((e) => e.pinned);
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardHeader(
                  customerName,
                  leading: _customerTypeIcon(group.first.customerId, isDark),
                  accent: _isRegisteredCustomer(group.first.customerId),
                  trailing: IconButton(
                    tooltip: pinned ? 'Lepas sematan' : 'Sematkan ke atas',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 18,
                      color: pinned ? AppTheme.accent : null,
                    ),
                    onPressed: () => ref
                        .read(databaseProvider)
                        .setBorrowedPinned(
                          [for (final e in group) e.id],
                          !pinned,
                          locallyModified:
                              ref.read(laciMejaLocallyModifiedProvider),
                        ),
                  ),
                ),
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
    final productFilter = ref.watch(_preorderProductFilterProvider);
    final quotas = ref.watch(preorderQuotaProvider);
    final taken = ref.watch(laciMejaTakenQtyProvider).valueOrNull ?? {};

    // Sisa yang BELUM dipenuhi — dipakai di mana pun angka "berapa yang
    // masih harus diserahkan" ditampilkan (kuota, statistik, baris entri),
    // supaya pemenuhan sebagian langsung tercermin di semuanya, bukan cuma
    // progress bar. Jaminan diasumsikan konsumsi 1:1 dgn item (tabung kosong
    // ditukar tabung isi) — asumsi yang sudah dipakai default toggle
    // jaminan di `item_entry_sheet.dart`/dialog "Jadikan Pre-order".
    double sisaQty(PreorderEntry e) =>
        (e.qtyOrdered - (taken[e.id] ?? 0)).clamp(0.0, e.qtyOrdered);
    double sisaDeposit(PreorderEntry e) =>
        e.depositQty <= 0 ? 0.0 : (e.depositQty - (taken[e.id] ?? 0)).clamp(0.0, e.depositQty);

    String productNameOf(PreorderEntry e) =>
        labels[e.productUnitId]?.productName ?? e.productId;

    // Daftar produk yang PUNYA antrian terbuka — sumber chip filter sekaligus
    // daftar produk yang kuotanya bisa diatur.
    final productNames = <String, String>{};
    for (final e in items) {
      productNames[e.productId] = productNameOf(e);
    }

    // Pencarian (permintaan user): cocokkan ke NAMA PELANGGAN atau NAMA
    // PRODUK. Statistik di bawah dihitung dari hasil TERSARING — supaya
    // saat mencari "Gas", angkanya menjawab "berapa Gas yang diantri",
    // bukan total seluruh pre-order (yang sudah terlihat di kartu atas).
    final filtered = items.where((e) {
      if (productFilter != null && e.productId != productFilter) return false;
      if (query.isEmpty) return true;
      return e.customerName.toLowerCase().contains(query) ||
          productNameOf(e).toLowerCase().contains(query);
    }).toList();

    // Garis pembatas kuota. Dihitung dari SELURUH antrian terbuka produk itu
    // (`items`, bukan `filtered`) — kata kunci pencarian tidak boleh menggeser
    // posisi antrian, dan entri yang sudah dipenuhi/dibatalkan memang sudah
    // tidak ada di `items` sehingga garisnya ikut maju dengan sendirinya.
    //
    // Kalau HANYA satu produk yang punya antrian, produk itu dianggap terpilih
    // dengan sendirinya — chip filternya memang sengaja disembunyikan di
    // kondisi ini (tidak ada yang perlu disaring), dan justru inilah kondisi
    // paling lazim di toko (cuma LPG yang diantri). Tanpa ini, garis
    // pembatasnya TIDAK PERNAH muncul walau kuotanya sudah disetel.
    final effectiveProduct = productFilter ??
        (productNames.length == 1 ? productNames.keys.first : null);
    final quota = effectiveProduct == null ? null : quotas[effectiveProduct];
    final beyondQuota = quota == null
        ? const <String>{}
        : preorderIdsBeyondQuota(items, effectiveProduct!, quota,
            takenQty: taken);
    // Nomor antrian per entri, juga dihitung dari antrian penuh produk itu.
    final queueNumbers = <String, int>{};
    if (effectiveProduct != null) {
      var n = 0;
      for (final e in items) {
        if (e.productId != effectiveProduct) continue;
        queueNumbers[e.id] = ++n;
      }
    }

    // Statistik akumulatif — produk & jaminan SENGAJA dipisah (permintaan
    // user): keduanya satuan berbeda maknanya (barang dipesan vs wadah
    // dititip sbg jaminan), menjumlahkannya jadi satu angka menyesatkan.
    // Dihitung dari SISA (bukan qty penuh) supaya sinkron dgn angka yang
    // ditampilkan per kartu — pemenuhan sebagian langsung mengurangi total.
    // Jaminan TIDAK dijumlah lintas produk (permintaan user) — angkanya
    // mengikuti produk yang sedang dipilih, dihitung di `_PreorderStatsLine`.
    final totalQty = filtered.fold<double>(0, (s, e) => s + sisaQty(e));

    // Rincian jaminan per produk (permintaan user, mis. "LPG: 20 jaminan") —
    // hanya entri yang benar-benar punya jaminan (>0) yang dihitung. Kunci
    // per productId (bukan nama) supaya provider di bawah bisa MENYIMPAN
    // pilihan produk yang ditampilkan dgn stabil (nama bisa berubah/sama
    // antar produk berbeda, id tidak).
    final depositByProduct = <String, ({String name, double qty})>{};
    for (final e in filtered) {
      final sisa = sisaDeposit(e);
      if (sisa <= 0) continue;
      final name = labels[e.productUnitId]?.productName ?? e.productId;
      final prev = depositByProduct[e.productId];
      depositByProduct[e.productId] = (name: name, qty: (prev?.qty ?? 0) + sisa);
    }
    // Produk yang ditampilkan langsung di chip jaminan (permintaan user):
    // pilihan tersimpan kalau masih ada di daftar terkini, kalau tidak
    // (produk itu sudah tidak lagi punya jaminan terbuka) jatuh ke produk
    // PERTAMA yang tersedia.
    final jaminanSelected = ref.watch(_preorderJaminanDisplayProvider);
    final effectiveJaminanId = depositByProduct.containsKey(jaminanSelected)
        ? jaminanSelected
        : (depositByProduct.isEmpty ? null : depositByProduct.keys.first);

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
        // Filter + statistik DIBUNGKUS jadi satu panel (permintaan user:
        // sebelumnya masing-masing elemen punya padding sendiri-sendiri yang
        // tidak selaras, jadi kelihatan "asal tempel" begitu daftar di
        // bawahnya discroll). Satu kartu dgn batas jelas = satu unit visual.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.laciBg(isDark).withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.laciFg(isDark).withOpacity(0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Chip filter HANYA saat >1 produk (tidak ada yang perlu
                // disaring kalau cuma 1) — baris sendiri krn bisa perlu
                // scroll horizontal, beda kebutuhan dari baris statistik.
                if (productNames.length > 1) ...[
                  _PreorderProductFilter(
                    productNames: productNames,
                    selected: productFilter,
                    quotas: quotas,
                    onSelected: (id) => ref
                        .read(_preorderProductFilterProvider.notifier)
                        .state = id,
                  ),
                  const SizedBox(height: 8),
                ],
                // Statistik + tombol Kuota SATU BARIS (permintaan user:
                // kartu total sebelumnya terlalu besar/makan tempat). Chip
                // "Jaminan: N" menampilkan angka produk yang SEDANG dipilih
                // (dinamis, bukan dijumlah semua produk) — dipilih lewat
                // chip nama produk di sebelahnya, tanpa perlu tap tooltip.
                _PreorderStatsLine(
                  totalQty: totalQty,
                  entryCount: filtered.length,
                  depositByProduct: depositByProduct,
                  selectedJaminanId: effectiveJaminanId,
                  onSelectJaminan: (id) => ref
                      .read(_preorderJaminanDisplayProvider.notifier)
                      .state = id,
                  isDark: isDark,
                  onManageQuota: () =>
                      _showQuotaSheet(context, ref, productNames, quotas),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: keys.isEmpty
              ? Center(
                  child: Text(
                      query.isEmpty
                          ? 'Tidak ada pre-order untuk produk ini.'
                          : 'Tidak ada yang cocok dgn "$query".',
                      style: TextStyle(color: scheme.onSurfaceVariant)))
              : _buildPreorderGroups(
                  context,
                  ref,
                  groups,
                  keys,
                  labels,
                  isDark,
                  ref.watch(laciMejaCustomerNamesProvider).valueOrNull ?? {},
                  beyondQuota: beyondQuota,
                  queueNumbers: queueNumbers,
                  quota: quota,
                ),
        ),
      ],
    );
  }

  /// Sheet pengaturan kuota per produk. Hanya produk yang punya antrian
  /// terbuka yang ditawarkan — kuota untuk produk tanpa antrian tidak ada
  /// gunanya dan cuma bikin daftarnya panjang.
  static Future<void> _showQuotaSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, String> productNames,
    Map<String, double> quotas,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Kuota Pre-order',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Batas jumlah yang bisa dilayani sekali kirim. Antrian yang '
                'melewati batas diberi garis pemisah — posisinya ikut '
                'menyesuaikan tiap ada yang dipenuhi.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in productNames.entries)
                      _QuotaRow(
                        productName: entry.value,
                        threshold: quotas[entry.key],
                        onChanged: (v) {
                          final store =
                              ref.read(preorderQuotaProvider.notifier);
                          if (v == null) {
                            store.clearThreshold(entry.key);
                          } else {
                            store.setThreshold(entry.key, v);
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreorderGroups(
      BuildContext context,
      WidgetRef ref,
      Map<String, List<PreorderEntry>> groups,
      List<String> keys,
      Map<String, ({String productName, String unitName})> labels,
      bool isDark,
      Map<String, String> liveNames,
      {Set<String> beyondQuota = const {},
      Map<String, int> queueNumbers = const {},
      double? quota}) {
    // Kartu PERTAMA yang isinya sudah melewati kuota — garis pembatas
    // disisipkan tepat di atasnya. Dihitung dari urutan kartu yang benar-benar
    // dirender, jadi ikut bergeser saat antrian berubah.
    final firstBeyondIndex = quota == null
        ? -1
        : keys.indexWhere(
            (k) => groups[k]!.any((e) => beyondQuota.contains(e.id)));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: keys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final group = groups[keys[i]]!;
        final first = group.first;
        final quotaDivider = quota != null && i == firstBeyondIndex
            ? _QuotaDivider(quota: quota, isDark: isDark)
            : null;
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
        final card = Card(
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
                  child: _cardHeader(
                    customerName,
                    leading: _customerTypeIcon(first.customerId, isDark),
                    accent: _isRegisteredCustomer(first.customerId),
                  ),
                ),
                for (final e in group)
                  _preorderTile(context, ref, e, labels, isDark,
                      queueNumber: queueNumbers[e.id],
                      beyondQuota: beyondQuota.contains(e.id)),
              ],
            ),
          ),
        );
        if (quotaDivider == null) return card;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [quotaDivider, const SizedBox(height: 8), card],
        );
      },
    );
  }

  Widget _preorderTile(
      BuildContext context,
      WidgetRef ref,
      PreorderEntry e,
      Map<String, ({String productName, String unitName})> labels,
      bool isDark,
      {int? queueNumber,
      bool beyondQuota = false}) {
    final label = labels[e.productUnitId];
    final productName = label?.productName ?? e.productId;
    final taken = ref.watch(laciMejaTakenQtyProvider).valueOrNull?[e.id] ?? 0;
    final sisa = (e.qtyOrdered - taken).clamp(0.0, e.qtyOrdered);
    // Angka yang tampil di baris SELALU sisa yang belum diserahkan, bukan
    // jumlah pesanan awal — begitu ada pengambilan sebagian, kartu langsung
    // menunjukkan "berapa lagi", bukan angka basi yang butuh dihitung manual
    // dari progress bar. Jaminan diasumsikan konsumsi 1:1 dgn item (lihat
    // dok `sisaDeposit` di `_buildPreorderList`).
    final qtyStr = sisa % 1 == 0 ? sisa.toInt().toString() : '$sisa';
    final sisaDeposit =
        e.depositQty <= 0 ? 0.0 : (e.depositQty - taken).clamp(0.0, e.depositQty);
    final depositStr = sisaDeposit > 0
        ? ' - ${sisaDeposit % 1 == 0 ? sisaDeposit.toInt() : sisaDeposit} jaminan'
        : '';
    // Status "Tempo"/"Lunas" berdasar `e.paid` (DP RUPIAH — permintaan user
    // eksplisit "Rp 0" = tempo), BUKAN `depositQty` (jaminan WADAH FISIK,
    // mis. tabung kosong LPG — beda konsep total).
    //
    // BUG YANG SUDAH DIPERBAIKI: versi sebelumnya salah pakai `depositQty >
    // 0` sbg penanda "sudah bayar" — ternyata SEMUA pre-order tampil
    // "Lunas" krn `item_entry_sheet.dart` OTOMATIS mengisi penuh `depositQty
    // = qty` begitu toggle pre-order dinyalakan utk unit yang
    // `requiresDeposit` (baris ~480-482), TERLEPAS dari apakah DP-nya
    // benar-benar dibayar. `paid`/`preorderPaid` (dari toggle "DP sudah
    // dibayar" di form, mengendalikan `_effectivePrice`) adalah sinyal yang
    // BENAR: nota bisa "lunas" krn barang LAIN di keranjang yang sama, tapi
    // baris pre-order itu SENDIRI tetap tempo kalau DP-nya belum masuk.
    final statusLabel = e.paid ? 'Lunas' : 'Tempo';
    final statusColor =
        e.paid ? AppTheme.changeFg(isDark) : AppTheme.debtFg(isDark);
    return _EntryRow(
      // Permintaan user: qty & nama produk dibedakan bold dari sisa baris
      // (jaminan, status Tempo/Lunas).
      line2: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 13.5),
          children: [
            // Nomor antrian hanya muncul saat difilter ke satu produk —
            // di daftar campur, "#3" tidak punya makna (antrian tiap produk
            // jalan sendiri-sendiri).
            if (queueNumber != null)
              TextSpan(
                text: '#$queueNumber ',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: beyondQuota
                        ? AppTheme.stockWarnFg(isDark)
                        : AppTheme.laciFg(isDark)),
              ),
            // Bold ditulis EKSPLISIT di span-nya (bukan diwarisi dari style
            // induk) supaya widget test bisa membaca ketebalannya langsung
            // dari span ini — lihat `findBoldableSpan` di test grouping.
            TextSpan(
                text: '$qtyStr $productName',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (depositStr.isNotEmpty)
              TextSpan(
                text: depositStr,
                style: TextStyle(
                    fontWeight: FontWeight.w500, color: AppTheme.laciFg(isDark)),
              ),
            TextSpan(
              text: ' $statusLabel',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: statusColor),
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

/// Baris chip filter produk + pintu masuk pengaturan kuota (permintaan user).
/// Chip produk yang kuotanya aktif diberi angka batasnya langsung di label,
/// supaya staf tahu ada garis pembatas tanpa harus membuka sheet pengaturan.
/// Chip filter produk — dipanggil HANYA saat >1 produk (parent sudah
/// mengecek), jadi tidak perlu tangani kasus "sembunyi" di sini lagi.
/// Tombol Kuota TIDAK di sini lagi (permintaan user: gabung satu baris dgn
/// statistik, lihat `_PreorderStatsLine`) — dulu ganda dgn baris statistik
/// jadi 2 baris toolbar yang makan tempat.
class _PreorderProductFilter extends StatelessWidget {
  const _PreorderProductFilter({
    required this.productNames,
    required this.selected,
    required this.quotas,
    required this.onSelected,
  });

  final Map<String, String> productNames;
  final String? selected;
  final Map<String, double> quotas;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    // TANPA Padding sendiri — widget ini dipanggil dari dalam panel yang
    // sudah punya padding seragam (lihat pembungkusnya di `_buildPreorderList`).
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Semua'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
            visualDensity: VisualDensity.compact,
          ),
          for (final e in productNames.entries) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text(quotas[e.key] == null
                  ? e.value
                  : '${e.value} · maks ${_fmt(quotas[e.key]!)}'),
              selected: selected == e.key,
              onSelected: (_) => onSelected(e.key),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  static String _fmt(double v) => v % 1 == 0 ? v.toInt().toString() : '$v';
}

/// Satu baris pengaturan kuota di sheet "Kuota Pre-order": toggle aktif +
/// angka batas. Mematikan toggle MENGHAPUS kuotanya (bukan menyimpan 0) —
/// lihat dok `PreorderQuotaStore`.
class _QuotaRow extends StatefulWidget {
  const _QuotaRow({
    required this.productName,
    required this.threshold,
    required this.onChanged,
  });

  final String productName;
  final double? threshold;
  final ValueChanged<double?> onChanged;

  @override
  State<_QuotaRow> createState() => _QuotaRowState();
}

class _QuotaRowState extends State<_QuotaRow> {
  late final TextEditingController _ctrl = TextEditingController(
      text: widget.threshold == null ? '' : _fmt(widget.threshold!));
  late bool _enabled = widget.threshold != null;

  static String _fmt(double v) => v % 1 == 0 ? v.toInt().toString() : '$v';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    if (!_enabled) {
      widget.onChanged(null);
      return;
    }
    final parsed = double.tryParse(_ctrl.text.trim());
    widget.onChanged(parsed != null && parsed > 0 ? parsed : null);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Switch(
            value: _enabled,
            onChanged: (v) {
              setState(() => _enabled = v);
              _commit();
            },
          ),
          Expanded(
            child: Text(widget.productName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _ctrl,
              enabled: _enabled,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'mis. 70',
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (_) => _commit(),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Garis pembatas kuota di tengah daftar antrian. Posisinya dihitung ulang
/// tiap render dari antrian yang masih terbuka — lihat
/// `preorderIdsBeyondQuota`.
class _QuotaDivider extends StatelessWidget {
  const _QuotaDivider({required this.quota, required this.isDark});

  final double quota;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // Abu-abu netral (permintaan user) — sebelumnya warna peringatan
    // (kuning/oranye), yang terlalu "alarm" untuk sekadar penanda posisi
    // antrian.
    final color = isDark ? const Color(0xFF6B6B6B) : const Color(0xFF9E9E9E);
    final label = quota % 1 == 0 ? quota.toInt().toString() : '$quota';
    return Row(
      children: [
        Expanded(child: _DashedLine(color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Batas kiriman ($label)',
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ),
        Expanded(child: _DashedLine(color: color)),
      ],
    );
  }
}

/// Garis putus-putus horizontal (permintaan user, pembeda visual dari garis
/// solid `Divider` biasa yang dipakai di tempat lain). Flutter tidak punya
/// varian putus-putus bawaan — digambar manual lewat `CustomPaint` daripada
/// menambah dependency baru (app ini offline-first, tiap dependency = beban
/// rilis).
class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1.2,
      child: CustomPaint(
        painter: _DashedLinePainter(color: color),
        size: const Size(double.infinity, 1.2),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;
  static const _dashWidth = 5.0;
  static const _gapWidth = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
          Offset(x, size.height / 2), Offset(x + _dashWidth, size.height / 2), paint);
      x += _dashWidth + _gapWidth;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Statistik akumulasi tab Pre-order (permintaan user) — total produk dipesan
/// & total jaminan dititip, SENGAJA dipisah jadi dua angka (satuannya beda
/// maknanya: barang yang ditunggu vs wadah yang dipegang toko).
/// Statistik + tombol Kuota SATU BARIS (permintaan user — 2 kartu besar
/// sebelumnya kebanyakan makan tempat vertikal). Gradasi label-normal +
/// angka-bold dari kartu LAMA dipertahankan (disukai user), cuma dipadatkan
/// jadi "chip" mini satu baris — bukan diganti teks polos rata (versi
/// sebelumnya "terlalu ringkas", kehilangan penekanan visual pada angka).
/// Rincian jaminan per produk (kalau ada >1 produk berjaminan) dipindah ke
/// tooltip lewat ikon info supaya detailnya tidak hilang tapi tidak
/// menambah tinggi baris.
class _PreorderStatsLine extends StatelessWidget {
  const _PreorderStatsLine({
    required this.totalQty,
    required this.entryCount,
    required this.depositByProduct,
    required this.selectedJaminanId,
    required this.onSelectJaminan,
    required this.isDark,
    required this.onManageQuota,
  });

  final double totalQty;
  final int entryCount;
  final Map<String, ({String name, double qty})> depositByProduct;
  final String? selectedJaminanId;
  final ValueChanged<String> onSelectJaminan;
  final bool isDark;
  final VoidCallback onManageQuota;

  static String _fmt(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toString();

  @override
  Widget build(BuildContext context) {
    final fg = AppTheme.laciFg(isDark);
    final hasDeposit = depositByProduct.isNotEmpty;
    final selectedId = hasDeposit
        ? (depositByProduct.containsKey(selectedJaminanId)
            ? selectedJaminanId!
            : depositByProduct.keys.first)
        : null;
    // Angka DINAMIS ikut produk yang sedang dipilih di dropdown (permintaan
    // user) — BUKAN dijumlahkan dari seluruh produk. Beda produk = beda
    // angka, persis spt "Produk: X" tapi utk jaminan.
    final selectedQty = selectedId == null ? 0.0 : depositByProduct[selectedId]!.qty;

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text('$entryCount entri',
                    style: TextStyle(fontSize: 11, color: fg.withOpacity(0.7))),
                const SizedBox(width: 6),
                _StatChip(label: 'Produk', value: _fmt(totalQty), fg: fg),
                if (hasDeposit) ...[
                  const SizedBox(width: 6),
                  // Pemilih produk (nama saja, custom dropdown) TERPISAH
                  // dari angkanya — angkanya sendiri jadi chip "Jaminan: N"
                  // yang ikut berubah begitu pilihan produk diganti.
                  _ProductPickerChip(
                    entries: depositByProduct,
                    selectedId: selectedId,
                    onSelected: onSelectJaminan,
                    fg: fg,
                  ),
                  const SizedBox(width: 6),
                  _StatChip(
                      label: 'Jaminan', value: _fmt(selectedQty), fg: fg),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Susulan (permintaan user): tombol kuota diringkas jadi SIMBOL saja
        // (sebelumnya `OutlinedButton.icon` berlabel "Kuota") — baris
        // statistik ini padat & scroll horizontal, label teks tetap
        // memakan lebar tetap yang mengurangi ruang utk chip lain (mis.
        // "234 12"/"Jaminan: N" ikut terpotong, dilaporkan user via
        // screenshot). Tooltip tetap menjelaskan fungsinya utk aksesibilitas.
        IconButton(
          onPressed: onManageQuota,
          tooltip: 'Kuota',
          icon: const Icon(Icons.rule, size: 18),
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            foregroundColor: AppTheme.accent,
            side: BorderSide(color: AppTheme.accent.withOpacity(0.5)),
            minimumSize: const Size(34, 34),
          ),
        ),
      ],
    );
  }
}

/// Chip statistik mini — label BIASA + angka BOLD (gradasi yang disukai
/// user dari kartu lama), dikemas jadi satu `Text.rich` (satu widget, satu
/// baris) supaya ukurannya sekecil mungkin. Border+background tipis
/// mempertahankan identitas visual "kartu" tanpa tinggi kartu sungguhan.
class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.label, required this.value, required this.fg});

  final String label;
  final String value;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withOpacity(0.18)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
                text: '$label: ',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: fg.withOpacity(0.8))),
            TextSpan(
                text: value,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Chip jaminan yang bisa GANTI PRODUK yang ditampilkan (permintaan user) —
/// sebelumnya rincian per produk cuma bisa dilihat lewat tooltip yang harus
/// di-tap ulang tiap kali. Sekarang satu produk ditampilkan LANGSUNG (tanpa
/// perlu tap apa pun), produk lain tetap bisa dilihat/dipilih lewat dropdown
/// (`PopupMenuButton`) yang muncul begitu chip di-tap — hanya kalau memang
/// ada >1 produk berjaminan, kalau cuma 1 tidak ada gunanya menawarkan
/// pilihan yang isinya itu-itu saja.
/// Pemilih PRODUK (bukan angka — angkanya ada di chip "Jaminan: N" sebelah
/// ini, lihat `_PreorderStatsLine`) utk menentukan produk mana yang jaminan-
/// nya sedang ditampilkan. Dropdown-nya didesain sendiri (permintaan user
/// eksplisit "bukan default flutter") — bukan `PopupMenuItem` polos putih
/// dgn `ListTile` bawaan, tapi kartu aksen dgn indikator radio & badge qty.
/// Tetap pakai mekanisme `PopupMenuButton` (posisi/dismiss/keyboard sudah
/// teruji Flutter sendiri), yang di-custom total cuma tampilannya.
class _ProductPickerChip extends StatelessWidget {
  const _ProductPickerChip({
    required this.entries,
    required this.selectedId,
    required this.onSelected,
    required this.fg,
  });

  final Map<String, ({String name, double qty})> entries;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final Color fg;

  static String _fmt(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toString();

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final id = entries.containsKey(selectedId) ? selectedId! : entries.keys.first;
    final selectedName = entries[id]!.name;
    final hasOthers = entries.length > 1;

    final chip = Container(
      padding: EdgeInsets.fromLTRB(8, 4, hasOthers ? 4 : 8, 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accent.withOpacity(0.14),
            AppTheme.accent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 12, color: AppTheme.accent),
          const SizedBox(width: 4),
          // Susulan (permintaan user): nama produk dibatasi lebarnya &
          // dibuat berjalan (marquee, pola sama dgn nama pelanggan di cart
          // bar) kalau kepanjangan — dulu chip ini bisa melebar tak
          // terbatas (Row `mainAxisSize.min`) & mendorong chip lain
          // ("Jaminan: N", tombol Kuota) keluar layar tanpa tanda ada
          // konten terpotong.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: MarqueeText(
              text: selectedName,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
          if (hasOthers) ...[
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 16, color: AppTheme.accent),
          ],
        ],
      ),
    );

    // Tanpa produk lain, chip cuma tampilan — tidak ada yang perlu dipilih.
    if (!hasOthers) return chip;

    return PopupMenuButton<String>(
      tooltip: 'Pilih produk jaminan',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 6),
      elevation: 6,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppTheme.accent.withOpacity(0.25)),
      ),
      constraints: const BoxConstraints(minWidth: 180),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final e in entries.entries)
          PopupMenuItem<String>(
            value: e.key,
            padding: EdgeInsets.zero,
            height: 0,
            child: _ProductPickerMenuRow(
              name: e.value.name,
              qty: _fmt(e.value.qty),
              selected: e.key == id,
              fg: fg,
            ),
          ),
      ],
      child: chip,
    );
  }
}

/// Satu baris pilihan di dropdown `_ProductPickerChip` — desain sendiri:
/// indikator radio (bukan cuma teks polos), nama produk, badge qty bulat
/// beraksen. Baris yang sedang dipilih diberi tint latar supaya langsung
/// kelihatan tanpa perlu baca radio-nya.
class _ProductPickerMenuRow extends StatelessWidget {
  const _ProductPickerMenuRow({
    required this.name,
    required this.qty,
    required this.selected,
    required this.fg,
  });

  final String name;
  final String qty;
  final bool selected;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      color: selected ? AppTheme.accent.withOpacity(0.1) : null,
      child: Row(
        children: [
          Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 16,
              color: selected ? AppTheme.accent : fg.withOpacity(0.35)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: fg)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$qty jaminan',
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accent)),
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
