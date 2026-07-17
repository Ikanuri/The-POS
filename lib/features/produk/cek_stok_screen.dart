import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
import 'stock_opname_screen.dart';

/// Item 30(b) — layar kontrol stok terpisah dari daftar Produk (fokus
/// triase, bukan manajemen). Filter kategori → list produk stok riil
/// diurut tertipis → checkbox yang SEKALIGUS: (1) update `markedOutOfStock`
/// sungguhan di DB (state nyata, langsung dibaca katalog HTML Item 29 &
/// item_entry_sheet.dart kasir), DAN (2) menyusun teks order restock ke
/// supplier di panel bawah. Reuse untuk Item 30(a): dibuka dgn parameter
/// [initialGroupId] dari kartu ringkas Ringkasan Harian.
class CekStokScreen extends ConsumerStatefulWidget {
  const CekStokScreen({super.key, this.initialGroupId});
  final int? initialGroupId;

  @override
  ConsumerState<CekStokScreen> createState() => _CekStokScreenState();
}

final _cekStokGroupProvider = StateProvider<int?>((ref) => null);

final _cekStokGroupsProvider = FutureProvider<List<ProductGroup>>((ref) {
  return ref.watch(databaseProvider).getAllProductGroups();
});

final _cekStokOverviewProvider =
    StreamProvider.family<List<StockOverviewRow>, int?>((ref, groupId) {
  return ref.watch(databaseProvider).watchStockOverview(groupId: groupId);
});

class _CekStokScreenState extends ConsumerState<CekStokScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.initialGroupId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(_cekStokGroupProvider.notifier).state =
            widget.initialGroupId;
      });
    }
  }

  Future<void> _toggle(String productId, bool value) async {
    final db = ref.read(databaseProvider);
    await db.setMarkedOutOfStock(productId, value);
  }

  void _copyOrderText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teks order disalin')));
  }

  void _shareOrderText(String text) {
    Share.share(text, subject: 'Order Restock');
  }

  @override
  Widget build(BuildContext context) {
    final groupId = ref.watch(_cekStokGroupProvider);
    final groupsAsync = ref.watch(_cekStokGroupsProvider);
    final rowsAsync = ref.watch(_cekStokOverviewProvider(groupId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cek Stok'),
        actions: [
          IconButton(
            icon: const Icon(Icons.checklist_rounded),
            tooltip: 'Stock Opname',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const StockOpnameScreen(),
            )),
          ),
        ],
      ),
      body: Column(
        children: [
          groupsAsync.when(
            data: (groups) {
              final named = groups.where((g) => g.name != null).toList();
              return SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    _GroupChip(
                      label: 'Semua',
                      selected: groupId == null,
                      onTap: () =>
                          ref.read(_cekStokGroupProvider.notifier).state =
                              null,
                    ),
                    ...named.map((g) => _GroupChip(
                          label: g.name!,
                          selected: groupId == g.id,
                          onTap: () =>
                              ref.read(_cekStokGroupProvider.notifier).state =
                                  g.id,
                        )),
                  ],
                ),
              );
            },
            loading: () => const SizedBox(height: 44),
            error: (_, __) => const SizedBox(height: 44),
          ),
          const Divider(height: 1),
          Expanded(
            child: rowsAsync.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return const Center(
                      child: Text('Tidak ada produk berstok di kategori ini'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _StockRow(
                    row: rows[i],
                    onToggle: (v) => _toggle(rows[i].productId, v),
                  ),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
          rowsAsync.maybeWhen(
            data: (rows) {
              final checked = rows.where((r) => r.markedOutOfStock).toList();
              if (checked.isEmpty) return const SizedBox.shrink();
              final text = _buildOrderText(checked);
              return _OrderTextPanel(
                text: text,
                onCopy: () => _copyOrderText(text),
                onShare: () => _shareOrderText(text),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _buildOrderText(List<StockOverviewRow> checked) {
    final buf = StringBuffer('Order Restock:\n');
    for (final r in checked) {
      buf.writeln('- ${r.name}');
    }
    return buf.toString().trim();
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
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({required this.row, required this.onToggle});
  final StockOverviewRow row;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final checked = row.markedOutOfStock;

    final Color badgeFg;
    final Color badgeBg;
    if (row.stock <= 0) {
      badgeFg = AppTheme.debtFg(isDark);
      badgeBg = AppTheme.debtBg(isDark);
    } else if (row.minStock != null && row.stock < row.minStock!) {
      badgeFg = AppTheme.stockWarnFg(isDark);
      badgeBg = AppTheme.stockWarnBg(isDark);
    } else {
      badgeFg = AppTheme.changeFg(isDark);
      badgeBg = AppTheme.changeBg(isDark);
    }

    final stockLabel =
        row.stock % 1 == 0 ? row.stock.toInt().toString() : row.stock.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: checked ? badgeBg.withOpacity(0.3) : null,
      shape: checked
          ? RoundedRectangleBorder(
              side: BorderSide(color: badgeFg, width: 1),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: CheckboxListTile(
        value: checked,
        onChanged: (v) => onToggle(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          row.name,
          style: TextStyle(
            fontSize: 13,
            decoration: checked ? TextDecoration.lineThrough : null,
          ),
        ),
        secondary: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: badgeBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            stockLabel,
            style: TextStyle(
                color: badgeFg, fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      ),
    );
  }
}

class _OrderTextPanel extends StatelessWidget {
  const _OrderTextPanel(
      {required this.text, required this.onCopy, required this.onShare});
  final String text;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Teks Order Restock',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 100),
              child: SingleChildScrollView(
                child: Text(text, style: const TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Salin'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.send_outlined, size: 16),
                    label: const Text('Kirim ke Supplier'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
