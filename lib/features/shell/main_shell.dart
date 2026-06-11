import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/device_provider.dart';

class _TabItem {
  const _TabItem(this.path, this.label, this.icon, this.selectedIcon);
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _allTabs = [
  _TabItem('/ringkasan', 'Ringkasan', Icons.grid_view_outlined, Icons.grid_view),
  _TabItem('/kasir', 'Kasir', Icons.point_of_sale_outlined, Icons.point_of_sale),
  _TabItem('/produk', 'Produk', Icons.inventory_2_outlined, Icons.inventory_2),
  _TabItem('/pelanggan', 'Pelanggan', Icons.people_outline, Icons.people),
  _TabItem('/laporan', 'Laporan', Icons.bar_chart_outlined, Icons.bar_chart),
  _TabItem('/pengaturan', 'Pengaturan', Icons.settings_outlined, Icons.settings),
];

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider);
    // Tab Laporan disembunyikan dari kasir.
    final tabs = device.canSeeReports
        ? _allTabs
        : _allTabs.where((t) => t.path != '/laporan').toList();

    final location = GoRouterState.of(context).matchedLocation;
    var selected = tabs.indexWhere((t) => location.startsWith(t.path));
    if (selected < 0) selected = 0;

    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: cs.outlineVariant, width: 0.5),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (i) => context.go(tabs[i].path),
          destinations: [
            for (final t in tabs)
              NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.selectedIcon),
                label: t.label,
              ),
          ],
        ),
      ),
    );
  }
}
