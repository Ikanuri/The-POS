import 'package:flutter/material.dart';

import '../shell/placeholder_screen.dart';

class LaporanScreen extends StatelessWidget {
  const LaporanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Laporan',
      icon: Icons.bar_chart_outlined,
      phase: 'Phase 3',
      description:
          'Ringkasan, produk terlaris, pelanggan utama, riwayat transaksi '
          '(tambah bayar & void), export PDF/XLSX.',
    );
  }
}
