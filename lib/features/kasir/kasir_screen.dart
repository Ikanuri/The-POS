import 'package:flutter/material.dart';

import '../shell/placeholder_screen.dart';

class KasirScreen extends StatelessWidget {
  const KasirScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Kasir',
      icon: Icons.point_of_sale_outlined,
      phase: 'Phase 2',
      description:
          'Katalog produk, scan barcode, keranjang dengan varian & harga berjenjang, '
          'pembayaran multi-metode, cetak struk Bluetooth.',
    );
  }
}
