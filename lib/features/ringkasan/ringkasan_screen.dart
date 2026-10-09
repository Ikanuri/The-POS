import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/data_refresh_provider.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_style.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_filter_chip.dart';
import '../../core/widgets/chart_kit.dart';
import '../../core/utils/chart_utils.dart';
import '../shell/sync_status_banner.dart';

final _ringkasanProvider = FutureProvider<_RingkasanData>((ref) async {
  // WAJIB baris pertama — lihat dok `dataSyncedTickProvider` (bug nyata:
  // total pendapatan hari ini tidak bertambah setelah sync dari host).
  ref.watch(dataSyncedTickProvider);
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = todayStart.add(const Duration(days: 1));
  final weekStart = now.subtract(Duration(days: now.weekday - 1));
  final weekStartDay = DateTime(weekStart.year, weekStart.month, weekStart.day);
  final monthStart = DateTime(now.year, now.month, 1);

  final todayTx = await (db.select(db.transactions)
        ..where((t) =>
            t.status.isNotValue('void') &
            t.createdAt.isBiggerOrEqualValue(todayStart) &
            t.createdAt.isSmallerOrEqualValue(todayEnd)))
      .get();

  final weekTx = await (db.select(db.transactions)
        ..where((t) =>
            t.status.isNotValue('void') &
            t.createdAt.isBiggerOrEqualValue(weekStartDay)))
      .get();

  final yesterdayStart = todayStart.subtract(const Duration(days: 1));
  final yesterdayTx = await (db.select(db.transactions)
        ..where((t) =>
            t.status.isNotValue('void') &
            t.createdAt.isBiggerOrEqualValue(yesterdayStart) &
            t.createdAt.isSmallerThanValue(todayStart)))
      .get();

  final monthTx = await (db.select(db.transactions)
        ..where((t) =>
            t.status.isNotValue('void') &
            t.createdAt.isBiggerOrEqualValue(monthStart)))
      .get();

  // Hourly breakdown untuk hari ini
  final hourly = List<int>.filled(24, 0);
  for (final tx in todayTx) {
    hourly[tx.createdAt.hour] += tx.total;
  }

  // Top products hari ini
  final todayItems = <String, _ProductStat>{};
  for (final tx in todayTx) {
    final items = await (db.select(db.transactionItems)
          ..where((t) => t.transactionId.equals(tx.id)))
        .get();
    for (final item in items) {
      final stat = todayItems.putIfAbsent(
          item.productId, () => _ProductStat(item.productId));
      stat.sold += item.qty;
      stat.revenue += item.subtotal;
    }
  }
  final topProds = todayItems.values.toList()
    ..sort((a, b) => b.revenue.compareTo(a.revenue));

  // Load product names for top products
  for (final s in topProds.take(5)) {
    final p = await (db.select(db.products)
          ..where((t) => t.id.equals(s.productId)))
        .getSingleOrNull();
    if (p != null) s.name = p.name;
  }

  return _RingkasanData(
    todayRevenue: todayTx.fold(0, (s, t) => s + t.total),
    todayTransactions: todayTx.length,
    yesterdayRevenue: yesterdayTx.fold(0, (s, t) => s + t.total),
    weekRevenue: weekTx.fold(0, (s, t) => s + t.total),
    monthRevenue: monthTx.fold(0, (s, t) => s + t.total),
    hourly: hourly,
    topProducts: topProds.take(5).toList(),
  );
});

// Item 30(a) — kartu cek cepat stok. State filter kategori TERPISAH dari
// filter layar "Cek Stok" (30b) — kartu ini murni ringkasan, tombol "Lihat
// semua" membawa kategori terpilih sbg parameter awal ke layar 30b (bukan
// berbagi provider yang sama).
final _stockGroupFilterProvider = StateProvider<int?>((ref) => null);

final _stockGroupsProvider = FutureProvider<List<ProductGroup>>((ref) {
  return ref.watch(databaseProvider).getAllProductGroups();
});

final _stockOverviewForRingkasanProvider =
    StreamProvider.family<List<StockOverviewRow>, int?>((ref, groupId) {
  return ref.watch(databaseProvider).watchStockOverview(groupId: groupId);
});

/// Jam yang sedang "dipin" di chart Penjualan Per Jam (permintaan user:
/// rincian dibuka via TAP — bukan tekan-tahan `Tooltip` bawaan Flutter yang
/// otomatis hilang begitu jari dilepas — dan tetap tampil sampai user tap
/// area lain atau scroll layar). null = tidak ada yang dipin.
final _pinnedHourProvider = StateProvider<int?>((ref) => null);

class RingkasanScreen extends ConsumerWidget {
  const RingkasanScreen({super.key});

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Selamat pagi';
    if (h < 15) return 'Selamat siang';
    if (h < 18) return 'Selamat sore';
    return 'Selamat malam';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider);
    final dataAsync = ref.watch(_ringkasanProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 18,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_greeting(),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant)),
            Text(
              device.storeName.isNotEmpty ? device.storeName : 'Ringkasan',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.numStyle(context,
                  size: 21, weight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Material(
              color: scheme.primary.withOpacity(0.12),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Muat ulang',
                icon: Icon(Icons.refresh_rounded, color: scheme.primary),
                onPressed: () => ref.invalidate(_ringkasanProvider),
              ),
            ),
          ),
        ],
      ),
      // Tap di mana pun di layar ini menutup rincian jam yang sedang dipin
      // (lihat dok `_pinnedHourProvider`) — GestureDetector di sini kalah
      // arena thd tap yang sudah ditangani widget anak, jadi cuma menutup
      // kalau tap benar2 jatuh di area kosong.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => ref.read(_pinnedHourProvider.notifier).state = null,
        child: Column(
          children: [
            const SyncStatusBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(_ringkasanProvider),
                child: dataAsync.when(
                  data: (data) => _RingkasanBody(data: data),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Muncul berurutan: memudar + naik 10dp (easeOutQuint), tertunda [index]*60ms.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + index * 60),
      curve: AppMotion.easeOutQuint,
      builder: (_, t, c) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: c),
      ),
      child: child,
    );
  }
}

class _RingkasanBody extends ConsumerWidget {
  const _RingkasanBody({required this.data});
  final _RingkasanData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final avgDay = data.monthRevenue ~/ now.day.clamp(1, 31);

    // Scroll juga menutup rincian jam yang dipin (NotificationListener di sini
    // adalah ancestor Scrollable-nya).
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification) {
          ref.read(_pinnedHourProvider.notifier).state = null;
        }
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
        children: [
          _Reveal(
            index: 0,
            child: _HeroCard(
              revenue: data.todayRevenue,
              transactions: data.todayTransactions,
              yesterday: data.yesterdayRevenue,
            ),
          ),
          const SizedBox(height: 12),
          _Reveal(
            index: 1,
            child: _PeriodCard(
              items: [
                _PeriodItem('Minggu Ini', data.weekRevenue,
                    Icons.date_range_rounded, AppTheme.riwayatFg(isDark),
                    AppTheme.riwayatBg(isDark)),
                _PeriodItem('Bulan Ini', data.monthRevenue,
                    Icons.calendar_month_rounded, AppTheme.scanFg(isDark),
                    AppTheme.scanBg(isDark)),
                _PeriodItem('Rata-rata/Hari', avgDay,
                    Icons.trending_up_rounded, AppTheme.changeFg(isDark),
                    AppTheme.changeBg(isDark)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle('Penjualan Per Jam (Hari Ini)'),
          _Reveal(
            index: 2,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: _HourlyChart(hourly: data.hourly),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle('Kontrol Stok'),
          const _Reveal(index: 3, child: _StockQuickCheckCard()),
          if (data.topProducts.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _SectionTitle('Produk Terlaris Hari Ini'),
            _Reveal(
              index: 4,
              child: _TopProductsCard(
                products: data.topProducts,
                accent: scheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

/// Kartu utama: omzet hari ini (gradien terracotta) + selisih vs kemarin.
class _HeroCard extends StatelessWidget {
  const _HeroCard(
      {required this.revenue,
      required this.transactions,
      required this.yesterday});
  final int revenue;
  final int transactions;
  final int yesterday;

  @override
  Widget build(BuildContext context) {
    // Selisih vs kemarin: hanya bila kemarin ada penjualan.
    String? delta;
    var up = true;
    if (yesterday > 0) {
      final pct = ((revenue - yesterday) * 100 / yesterday).round();
      up = pct >= 0;
      delta = '${up ? '+' : ''}$pct% dari kemarin';
    }
    final avgTx = transactions > 0 ? revenue ~/ transactions : 0;
    return Container(
      key: const Key('ringkasan-hero'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppStyle.rPanel),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD97757), Color(0xFFC96442)],
        ),
        boxShadow: AppStyle.accentShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.today_rounded, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              const Text('Hari Ini',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70)),
              const Spacer(),
              if (delta != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(AppStyle.rPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          up
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 12,
                          color: Colors.white),
                      const SizedBox(width: 3),
                      Text(delta,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatRupiah(revenue),
              style: AppTheme.numStyle(context,
                  size: 30, weight: FontWeight.w600, color: Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            transactions == 0
                ? 'Belum ada transaksi'
                : '$transactions transaksi · rata-rata ${formatRupiah(avgTx)}',
            style: const TextStyle(fontSize: 12.5, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _PeriodItem {
  const _PeriodItem(this.label, this.value, this.icon, this.fg, this.bg);
  final String label;
  final int value;
  final IconData icon;
  final Color fg;
  final Color bg;
}

/// Tiga periode dalam satu kartu: ikon bulat berwarna + nominal serif.
class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.items});
  final List<_PeriodItem> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      key: const Key('ringkasan-periode'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        child: IntrinsicHeight(
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: items[i].bg),
                          child: Icon(items[i].icon,
                              size: 15, color: items[i].fg),
                        ),
                        const SizedBox(height: 8),
                        Text(items[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatRupiah(items[i].value),
                            style: AppTheme.numStyle(context,
                                size: 14.5, weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Rincian per-jam dibuka via TAP & permanen (lihat `_pinnedHourProvider`);
/// state-nya provider-level karena pemicu "tutup" (tap area kosong, scroll)
/// berasal dari widget leluhur yang terpisah.
class _HourlyChart extends ConsumerWidget {
  const _HourlyChart({required this.hourly});
  final List<int> hourly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final max = hourly.reduce((a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;
    if (max == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.bar_chart_rounded,
                size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Text('Belum ada penjualan hari ini',
                style:
                    TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    final pinned = ref.watch(_pinnedHourProvider);
    final peak = hourly.indexOf(max);

    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: pinned != null
                ? Text(
                    '${pinned.toString().padLeft(2, '0')}:00 — '
                    '${formatRupiah(hourly[pinned])}',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary),
                  )
                : Text(
                    'Tersibuk sekitar jam $peak · ketuk batang untuk rincian',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
          ),
        ),
        // Geser di atas batang = rincian ikut pindah (scrub) dgn haptik tiap
        // pindah jam; batang terpilih menonjol, yang lain meredup (Telegram).
        LayoutBuilder(builder: (context, c) {
          void scrub(double dx) {
            final h = (dx / c.maxWidth * hourly.length)
                .floor()
                .clamp(0, hourly.length - 1);
            if (ref.read(_pinnedHourProvider) != h) {
              chartTick();
              ref.read(_pinnedHourProvider.notifier).state = h;
            }
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => scrub(d.localPosition.dx),
            child: SizedBox(
              height: 92,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: hourly.asMap().entries.map((e) {
                  final h = e.key;
                  final v = e.value;
                  final height = clampedBarHeight(v, max, emptyHeight: 0);
                  final isPinned = pinned == h;
                  final base = v > 0
                      ? scheme.primary.withOpacity(h == peak ? 0.9 : 0.5)
                      : scheme.surfaceContainerHighest;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.2),
                      child: GestureDetector(
                        key: ValueKey('hour_bar_$h'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (!isPinned) chartTick();
                          ref.read(_pinnedHourProvider.notifier).state =
                              isPinned ? null : h;
                        },
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: AnimatedContainer(
                            duration: AppMotion.dur(context, AppMotion.base),
                            curve: AppMotion.easeOutQuint,
                            height: height + 3,
                            decoration: BoxDecoration(
                              color: isPinned
                                  ? scheme.primary
                                  : pinned != null
                                      ? base.withOpacity(base.opacity * 0.4)
                                      : base,
                              borderRadius:
                                  BorderRadius.circular(AppStyle.rPill),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        }),
        const SizedBox(height: 6),
        Row(
          children: hourly.asMap().entries.map((e) {
            final h = e.key;
            final label = h % 6 == 0 ? h.toString().padLeft(2, '0') : '';
            return Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.fg, this.bg);
  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(AppStyle.rPill)),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      );
}

class _StockQuickCheckCard extends ConsumerWidget {
  const _StockQuickCheckCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groupId = ref.watch(_stockGroupFilterProvider);
    final groupsAsync = ref.watch(_stockGroupsProvider);
    final rowsAsync = ref.watch(_stockOverviewForRingkasanProvider(groupId));

    return Card(
      key: const Key('ringkasan-stok'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            groupsAsync.maybeWhen(
              data: (groups) {
                final named = groups.where((g) => g.name != null).toList();
                if (named.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _MiniChip(
                          label: 'Semua',
                          selected: groupId == null,
                          onTap: () => ref
                              .read(_stockGroupFilterProvider.notifier)
                              .state = null,
                        ),
                        ...named.map((g) => _MiniChip(
                              label: g.name!,
                              selected: groupId == g.id,
                              onTap: () => ref
                                  .read(_stockGroupFilterProvider.notifier)
                                  .state = g.id,
                            )),
                      ],
                    ),
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
            rowsAsync.when(
              data: (rows) {
                final habis = rows.where((r) => r.stock <= 0).length;
                final menipis = rows
                    .where((r) =>
                        r.stock > 0 &&
                        r.minStock != null &&
                        r.stock < r.minStock!)
                    .length;
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Belum ada produk berstok di kategori ini',
                        style: TextStyle(fontSize: 12.5)),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Pill('$menipis menipis', AppTheme.stockWarnFg(isDark),
                            AppTheme.stockWarnBg(isDark)),
                        const SizedBox(width: 6),
                        _Pill('$habis habis', AppTheme.debtFg(isDark),
                            AppTheme.debtBg(isDark)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('$menipis produk stok menipis, $habis habis',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: habis > 0
                                ? AppTheme.debtFg(isDark)
                                : scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    ...rows.take(3).map((r) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(r.name,
                                    style: const TextStyle(fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 8),
                              _Pill(
                                r.stock % 1 == 0
                                    ? r.stock.toInt().toString()
                                    : r.stock.toString(),
                                r.stock <= 0
                                    ? AppTheme.debtFg(isDark)
                                    : AppTheme.stockWarnFg(isDark),
                                r.stock <= 0
                                    ? AppTheme.debtBg(isDark)
                                    : AppTheme.stockWarnBg(isDark),
                              ),
                            ],
                          ),
                        )),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () =>
                            context.push('/produk/cek-stok', extra: groupId),
                        child: const Text('Lihat semua'),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard({required this.products, required this.accent});
  final List<_ProductStat> products;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topRev = products.first.revenue <= 0 ? 1 : products.first.revenue;
    return Card(
      key: const Key('ringkasan-terlaris'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          children: [
            for (var i = 0; i < products.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == 0
                            ? accent
                            : scheme.surfaceContainerHighest,
                      ),
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: i == 0
                                  ? Colors.white
                                  : scheme.onSurfaceVariant)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              products[i].name.isNotEmpty
                                  ? products[i].name
                                  : products[i].productId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                              '${products[i].sold % 1 == 0 ? products[i].sold.toInt() : products[i].sold} terjual',
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 11.5)),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppStyle.rPill),
                            child: LinearProgressIndicator(
                              value: products[i].revenue / topRev,
                              minHeight: 4,
                              backgroundColor:
                                  scheme.surfaceContainerHighest,
                              color: accent.withOpacity(i == 0 ? 1 : 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(formatRupiah(products[i].revenue),
                        style: AppTheme.numStyle(context,
                            size: 14.5, weight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: AppFilterChip(label: label, selected: selected, onTap: onTap),
      );
}

class _RingkasanData {
  _RingkasanData({
    required this.todayRevenue,
    required this.todayTransactions,
    required this.yesterdayRevenue,
    required this.weekRevenue,
    required this.monthRevenue,
    required this.hourly,
    required this.topProducts,
  });

  final int todayRevenue;
  final int todayTransactions;
  final int yesterdayRevenue;
  final int weekRevenue;
  final int monthRevenue;
  final List<int> hourly;
  final List<_ProductStat> topProducts;
}

class _ProductStat {
  _ProductStat(this.productId);
  final String productId;
  String name = '';
  double sold = 0;
  int revenue = 0;
}
