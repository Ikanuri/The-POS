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
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = items[i];
        final days = _daysSince(e.createdAt);
        return ListTile(
          // Item 52 susulan — tap kartu redirect ke nota terkait, mekanisme
          // SAMA PERSIS dgn Buku Hutang (HutangTab -> push
          // '/kasir/struk/:txId'): sama-sama push ANTAR-RUTE DI DALAM satu
          // ShellRoute yang sama, bukan lintas batas shell (lihat dok rute
          // 'laci-meja' di app_router.dart soal kenapa layar ini pindah ke
          // dalam shell).
          onTap: () => context.push('/kasir/struk/${e.transactionId}'),
          title: Text(e.itemName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: _subtitle(
            leading: e.jenis == 'titip' ? 'Dititip' : 'Ketinggalan',
            customerName: e.customerNameText,
            days: days,
            isDark: isDark,
          ),
          trailing: TextButton(
            onPressed: () async {
              final db = ref.read(databaseProvider);
              final locallyModified = ref.read(laciMejaLocallyModifiedProvider);
              await db.markLeftBehindCollected(e.id, locallyModified: locallyModified);
            },
            child: const Text('Sudah Diambil'),
          ),
        );
      },
    );
  }

  Widget _buildBorrowedList(BuildContext context, WidgetRef ref,
      List<BorrowedItem> items, bool isDark, ColorScheme scheme) {
    if (items.isEmpty) {
      return Center(
          child: Text('Tidak ada pinjaman barang aktif.',
              style: TextStyle(color: scheme.onSurfaceVariant)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = items[i];
        final days = _daysSince(e.createdAt);
        final sisa = e.qty - e.qtyReturned;
        return ListTile(
          onTap: () => context.push('/kasir/struk/${e.transactionId}'),
          title: Text(e.itemName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: _subtitle(
            leading: 'Sisa $sisa dari ${e.qty}',
            customerName: e.customerNameText,
            days: days,
            isDark: isDark,
          ),
          trailing: TextButton(
            onPressed: () => _showReturnDialog(context, ref, e),
            child: const Text('Kembali'),
          ),
        );
      },
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

  Widget _buildPreorderList(BuildContext context, WidgetRef ref,
      List<PreorderEntry> items, bool isDark, ColorScheme scheme) {
    if (items.isEmpty) {
      return Center(
          child: Text('Tidak ada pre-order aktif.',
              style: TextStyle(color: scheme.onSurfaceVariant)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = items[i];
        final days = _daysSince(e.createdAt);
        return ListTile(
          // transactionId NULLABLE (satu-satunya kasus: titip wadah tanpa
          // beli apa pun) — redirect hanya kalau memang ada nota terkait.
          onTap: e.transactionId == null
              ? null
              : () => context.push('/kasir/struk/${e.transactionId}'),
          title: Text(e.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: _subtitle(
            leading: 'Qty ${e.qtyOrdered}'
                '${e.depositQty > 0 ? ' · titip wadah ${e.depositQty}' : ''}'
                '${e.paid ? ' · sudah bayar' : ''}',
            customerName: null,
            days: days,
            isDark: isDark,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Batal',
                icon: const Icon(Icons.close),
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
      },
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
