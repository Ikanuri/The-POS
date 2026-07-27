import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/providers/laci_meja_provider.dart';
import '../../core/theme/app_theme.dart';

enum _LaciMejaCategory { titipKetinggalan, pinjaman, preorder }

final _selectedCategoryProvider =
    StateProvider<_LaciMejaCategory>((ref) => _LaciMejaCategory.titipKetinggalan);

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

  /// Subtitle kartu: keterangan + NAMA PELANGGAN ber-aksen terracotta
  /// (`AppTheme.accent`, aksen utama app) supaya langsung kebaca "punya
  /// siapa" — sengaja dibedakan dari warna umur (hijau/kuning/merah) yang
  /// menandai seberapa lama menunggu.
  static Widget _subtitle({
    required String leading,
    required String? customerName,
    required int days,
    required bool isDark,
  }) {
    final ageStyle = TextStyle(
        fontSize: 12, color: _ageColor(days, isDark), fontWeight: FontWeight.w600);
    return Text.rich(
      TextSpan(
        style: ageStyle,
        children: [
          TextSpan(text: leading),
          if (customerName != null && customerName.isNotEmpty)
            TextSpan(
              text: ' — $customerName',
              style: const TextStyle(
                  color: AppTheme.accent, fontWeight: FontWeight.w700),
            ),
          TextSpan(text: ' · $days hari lalu'),
        ],
      ),
    );
  }

  static int _daysSince(DateTime d) => DateTime.now().difference(d).inDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(_selectedCategoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    final leftBehind = ref.watch(leftBehindItemsProvider);
    final borrowed = ref.watch(borrowedItemsProvider);
    final preorder = ref.watch(preorderEntriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Laci Meja')),
      body: Column(
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

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: txIds.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final group = groups[txIds[i]]!;
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var j = 0; j < group.length; j++) ...[
                if (j > 0) const Divider(height: 1),
                _leftBehindTile(context, ref, group[j], qtyUnit, isDark),
              ],
            ],
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
    final qtyLabel = qu == null
        ? ''
        : ' · ${qu.qty % 1 == 0 ? qu.qty.toInt() : qu.qty} ${qu.unitName}'
            .trimRight();
    return ListTile(
      // Item 52 susulan — tap kartu redirect ke nota terkait, mekanisme
      // SAMA PERSIS dgn Buku Hutang (HutangTab -> push
      // '/kasir/struk/:txId'): sama-sama push ANTAR-RUTE DI DALAM satu
      // ShellRoute yang sama, bukan lintas batas shell (lihat dok rute
      // 'laci-meja' di app_router.dart soal kenapa layar ini pindah ke
      // dalam shell).
      onTap: () => context.push('/kasir/struk/${e.transactionId}'),
      title: Text('${e.itemName}$qtyLabel',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: _subtitle(
        leading: e.jenis == 'titip' ? 'Dititip' : 'Ketinggalan',
        customerName: e.customerNameText,
        days: days,
        isDark: isDark,
      ),
      trailing: _CollectButton(
        onTap: () async {
          final db = ref.read(databaseProvider);
          final locallyModified = ref.read(laciMejaLocallyModifiedProvider);
          await db.markLeftBehindCollected(e.id, locallyModified: locallyModified);
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

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: keys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final group = groups[keys[i]]!;
        final customerName = group.first.customerNameText ?? 'Umum';
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customerName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      // Tiap baris tetap tertaut ke transactionId MASING-MASING (satu grup
      // pelanggan bisa berisi baris dari nota yang BERBEDA-BEDA).
      onTap: () => context.push('/kasir/struk/${e.transactionId}'),
      title: Text(e.itemName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: _subtitle(
        leading: 'Sisa $sisa dari ${e.qty}',
        customerName: null,
        days: days,
        isDark: isDark,
      ),
      trailing: TextButton(
        onPressed: () => _showReturnDialog(context, ref, e),
        child: const Text('Kembali'),
      ),
    );
  }

  Future<void> _showReturnDialog(
      BuildContext context, WidgetRef ref, BorrowedItem e) async {
    final sisa = e.qty - e.qtyReturned;
    final controller = TextEditingController(text: sisa.toStringAsFixed(0));
    final qty = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Kembali — ${e.itemName}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Jumlah kembali (sisa $sisa)'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (qty == null || qty <= 0) return;
    final db = ref.read(databaseProvider);
    final locallyModified = ref.read(laciMejaLocallyModifiedProvider);
    await db.returnBorrowedItemQty(e.id, qty, locallyModified: locallyModified);
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

    // transactionId NULLABLE (satu-satunya kasus: titip wadah tanpa beli
    // apa pun) — baris begini masing-masing jadi grup sendiri (kunci per id).
    final groups = <String, List<PreorderEntry>>{};
    for (final e in items) {
      groups.putIfAbsent(e.transactionId ?? 'no-tx-${e.id}', () => []).add(e);
    }
    final keys = groups.keys.toList();

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: keys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final group = groups[keys[i]]!;
        final first = group.first;
        final days = _daysSince(first.createdAt);
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: first.transactionId == null
                      ? null
                      : () =>
                          context.push('/kasir/struk/${first.transactionId}'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(first.customerName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Text('$days hari lalu',
                          style: TextStyle(
                              fontSize: 12,
                              color: _ageColor(days, isDark),
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text('$qtyStr $productName$depositStr'
                '${e.paid ? ' · sudah bayar' : ''}',
                style: TextStyle(fontSize: 13, color: AppTheme.laciFg(isDark))),
          ),
          IconButton(
            tooltip: 'Batal',
            icon: const Icon(Icons.close),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final db = ref.read(databaseProvider);
              final locallyModified = ref.read(laciMejaLocallyModifiedProvider);
              await db.cancelPreorderEntry(e.id, locallyModified: locallyModified);
            },
          ),
          TextButton(
            onPressed: () async {
              final db = ref.read(databaseProvider);
              final locallyModified = ref.read(laciMejaLocallyModifiedProvider);
              await db.fulfillPreorderEntry(e.id, locallyModified: locallyModified);
            },
            child: const Text('Penuhi'),
          ),
        ],
      ),
    );
  }
}

/// Redesain (permintaan user): tombol "Sudah Diambil" disederhanakan jadi
/// pill kecil ikon+label singkat — minimalis tapi TIDAK kotak-persegi rigid
/// (`StadiumBorder`), pola sama semangatnya dgn `_CollectButton` di chip
/// lain app ini (rounded, aksen warna domain Laci Meja).
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
