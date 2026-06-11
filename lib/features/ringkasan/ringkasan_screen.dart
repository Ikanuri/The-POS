import 'package:flutter/material.dart';

import '../shell/placeholder_screen.dart';

class RingkasanScreen extends StatelessWidget {
  const RingkasanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Ringkasan',
      icon: Icons.grid_view_outlined,
      phase: 'Phase 3',
      description:
          'KPI hari ini, grafik penjualan per jam, metode pembayaran, produk terlaris.',
    );
  }
}
