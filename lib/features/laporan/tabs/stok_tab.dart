import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';

/// Item 30(c) — laporan analitik/audit stok di tab Laporan. TIDAK terikat
/// rentang tanggal (beda dari tab lain) — ini snapshot "nilai stok SEKARANG",
/// bukan aktivitas dalam periode. MELENGKAPI stock opname fisik, TIDAK
/// MENGGANTIKANNYA — rajin input stok kulakan tidak pernah menangkap
/// susut/rusak/hilang/kesalahan hitung, cuma hitung fisik yang bisa
/// memverifikasi angka sistem = kenyataan (lihat catatan kecil di UI).
class _CategoryValue {
  _CategoryValue(this.label);
  final String label;
  int value = 0;
}

class _StokReport {
  _StokReport({
    required this.perCategory,
    required this.grandTotal,
    required this.missingCostCount,
    required this.negativeStock,
  });
  final List<_CategoryValue> perCategory;
  final int grandTotal;
  final int missingCostCount;
  final List<InventoryRow> negativeStock;
}

final _stokTabProvider = FutureProvider<_StokReport>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.getInventoryRows();
  final groups = await db.getAllProductGroups();
  final groupNameById = {
    for (final g in groups)
      if (g.name != null) g.id: g.name!,
  };

  final perCategory = <int?, _CategoryValue>{};
  var grandTotal = 0;
  var missingCostCount = 0;
  final negativeStock = <InventoryRow>[];

  for (final r in rows) {
    final value = (r.stock * r.costPrice).round();
    grandTotal += value;
    if (r.costPrice <= 0) missingCostCount++;
    if (r.stock < 0) negativeStock.add(r);

    final label = groupNameById[r.groupId] ?? 'Tanpa Kategori';
    perCategory.putIfAbsent(r.groupId, () => _CategoryValue(label)).value +=
        value;
  }

  final categoryList = perCategory.values.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  negativeStock.sort((a, b) => a.stock.compareTo(b.stock));

  return _StokReport(
    perCategory: categoryList,
    grandTotal: grandTotal,
    missingCostCount: missingCostCount,
    negativeStock: negativeStock,
  );
});

class StokTab extends ConsumerWidget {
  const StokTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(_stokTabProvider);
    final scheme = Theme.of(context).colorScheme;

    return dataAsync.when(
      data: (report) {
        if (report.perCategory.isEmpty) {
          return Center(
            child: Text('Belum ada produk berstok',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nilai Inventori Sekarang',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(formatRupiah(report.grandTotal),
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary)),
                    if (report.missingCostCount > 0) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 14, color: AppTheme.stockWarnFg(false)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${report.missingCostCount} produk belum ada '
                            'harga pokok — nilainya BELUM terhitung di atas '
                            '(understated)',
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (report.perCategory.length >= 2) ...[
              Text('Nilai per Kategori',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _CategoryDonut(categories: report.perCategory),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text('Detail per Kategori',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < report.perCategory.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16),
                    ListTile(
                      dense: true,
                      title: Text(report.perCategory[i].label,
                          style: const TextStyle(fontSize: 13)),
                      trailing: Text(formatRupiah(report.perCategory[i].value),
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: scheme.primary)),
                    ),
                  ],
                ],
              ),
            ),
            if (report.negativeStock.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Stok Negatif Saat Ini (${report.negativeStock.length})',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < report.negativeStock.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 16),
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.error_outline,
                            size: 18, color: AppTheme.debtFg(false)),
                        title: Text(report.negativeStock[i].name,
                            style: const TextStyle(fontSize: 13)),
                        trailing: Text(
                          report.negativeStock[i].stock.toString(),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.debtFg(false)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14, color: scheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Laporan ini MELENGKAPI stock opname fisik, bukan '
                      'menggantikannya. Rajin mencatat stok masuk tidak '
                      'menangkap susut/rusak/hilang/kesalahan hitung — hanya '
                      'hitung fisik berkala yang bisa memastikan angka '
                      'sistem sesuai kenyataan.',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _CategoryDonut extends StatelessWidget {
  const _CategoryDonut({required this.categories});
  final List<_CategoryValue> categories;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topColors = <Color>[
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.error,
      const Color(0xFF4C7DBF),
    ];
    final onTopColors = <Color>[
      scheme.onPrimary,
      scheme.onTertiary,
      scheme.onSecondary,
      scheme.onError,
      Colors.white,
    ];

    const maxSlices = 5;
    final top = categories.take(maxSlices).toList();
    final otherValue =
        categories.skip(maxSlices).fold(0, (a, c) => a + c.value);
    final hasOther = otherValue > 0;
    final total = top.fold(0, (a, c) => a + c.value) + otherValue;

    bool isOther(int i) => hasOther && i == top.length;
    Color colorFor(int i) => isOther(i)
        ? scheme.surfaceContainerHighest
        : topColors[i % topColors.length];
    Color onColorFor(int i) => isOther(i)
        ? scheme.onSurfaceVariant
        : onTopColors[i % onTopColors.length];

    final count = top.length + (hasOther ? 1 : 0);
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < count; i++) {
      final value = i < top.length ? top[i].value : otherValue;
      final pct = total > 0 ? value / total * 100 : 0.0;
      final small = pct < 8;
      sections.add(PieChartSectionData(
        value: value.toDouble(),
        color: colorFor(i),
        title: total > 0 ? '${pct.round()}%' : '',
        radius: 27,
        titlePositionPercentageOffset: small ? 1.4 : 0.5,
        titleStyle: TextStyle(
          fontSize: small ? 9 : 10.5,
          fontWeight: FontWeight.w700,
          color: small ? scheme.onSurface : onColorFor(i),
        ),
      ));
    }

    return Row(
      children: [
        SizedBox(
          width: 130,
          height: 130,
          child: PieChart(PieChartData(
            centerSpaceRadius: 26,
            sectionsSpace: 2,
            sections: sections,
          )),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < count; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colorFor(i),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          i < top.length ? top[i].label : 'Lainnya',
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
