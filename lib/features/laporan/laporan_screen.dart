import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tabs/ringkasan_tab.dart';
import 'tabs/produk_tab.dart';
import 'tabs/pelanggan_tab.dart';
import 'tabs/transaksi_tab.dart';

final dateRangeProvider =
    StateProvider<DateTimeRange>((ref) {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month, now.day),
    end: DateTime(now.year, now.month, now.day, 23, 59, 59),
  );
});

class LaporanScreen extends ConsumerWidget {
  const LaporanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(dateRangeProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Laporan'),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(
                '${_fmt(range.start)} – ${_fmt(range.end)}',
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: () => _pickRange(context, ref, range),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Ringkasan'),
              Tab(text: 'Produk'),
              Tab(text: 'Pelanggan'),
              Tab(text: 'Transaksi'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            RingkasanTab(range: range),
            ProdukTab(range: range),
            PelangganTab(range: range),
            TransaksiTab(range: range),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';

  Future<void> _pickRange(
      BuildContext context, WidgetRef ref, DateTimeRange current) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: current,
    );
    if (picked != null) {
      ref.read(dateRangeProvider.notifier).state = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
      );
    }
  }
}
