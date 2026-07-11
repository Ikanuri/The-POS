import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import 'report_export.dart';
import 'tabs/ringkasan_tab.dart';
import 'tabs/produk_tab.dart';
import 'tabs/pelanggan_tab.dart';
import 'tabs/transaksi_tab.dart';
import 'tabs/hutang_tab.dart';

final dateRangeProvider = StateProvider<DateTimeRange>((ref) {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month, now.day),
    end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
  );
});

class LaporanScreen extends ConsumerStatefulWidget {
  const LaporanScreen({super.key});

  @override
  ConsumerState<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends ConsumerState<LaporanScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(dateRangeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(
              '${_fmt(range.start)} – ${_fmt(range.end)}',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: () => _pickRange(context, range),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export tab ini',
            onSelected: (v) => _export(range, v),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pdf',
                child: Text(
                    'Export PDF — ${_tabName(_tabController.index)}'),
              ),
              PopupMenuItem(
                value: 'xlsx',
                child: Text(
                    'Export Excel — ${_tabName(_tabController.index)}'),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Ringkasan'),
            Tab(text: 'Produk'),
            Tab(text: 'Pelanggan'),
            Tab(text: 'Transaksi'),
            Tab(text: 'Hutang'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          RingkasanTab(range: range),
          ProdukTab(range: range),
          PelangganTab(range: range),
          TransaksiTab(range: range),
          const HutangTab(),
        ],
      ),
    );
  }

  String _tabName(int i) =>
      const ['Ringkasan', 'Produk', 'Pelanggan', 'Transaksi', 'Hutang'][i];

  /// Tab Hutang (index 4) tidak punya padanan [ReportTab] & tidak diekspor.
  bool get _canExportCurrentTab =>
      _tabController.index < ReportTab.values.length;

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';

  Future<void> _export(DateTimeRange range, String format) async {
    if (!_canExportCurrentTab) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tab Hutang tidak bisa diekspor.')));
      return;
    }
    final device = ref.read(deviceProvider);
    final tab = ReportTab.values[_tabController.index];
    // Indikasi proses untuk ekspor yang melibatkan tangkapan grafik.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 1),
        content: Text('Menyiapkan laporan ${_tabName(_tabController.index)}…'),
      ));
    await exportReport(
      context: context,
      ref: ref,
      range: range,
      tab: tab,
      format: format,
      storeName: device.storeName,
    );
  }

  Future<void> _pickRange(BuildContext context, DateTimeRange current) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: current,
    );
    if (picked != null) {
      ref.read(dateRangeProvider.notifier).state = DateTimeRange(
        start:
            DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999),
      );
    }
  }
}
