import 'package:flutter/material.dart';

import '../shell/placeholder_screen.dart';

class PelangganListScreen extends StatelessWidget {
  const PelangganListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Pelanggan',
      icon: Icons.people_outline,
      phase: 'Phase 3',
      description:
          'CRUD pelanggan, group harga, poin loyalitas, piutang.',
    );
  }
}
