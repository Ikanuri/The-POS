import 'package:flutter/material.dart';

import '../shell/placeholder_screen.dart';

class ProdukListScreen extends StatelessWidget {
  const ProdukListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Produk',
      icon: Icons.inventory_2_outlined,
      phase: 'Phase 2',
      description:
          'CRUD produk, varian & satuan, barcode per varian, harga berjenjang, stok.',
    );
  }
}
