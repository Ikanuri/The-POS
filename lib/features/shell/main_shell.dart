import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/device_provider.dart';
import '../../core/providers/license_provider.dart';
import '../../core/services/backup_reminder.dart';

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

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  void initState() {
    super.initState();
    // Item 13: pengingat backup berbasis "cek saat app dibuka" (sekali).
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBackupReminder());
    // Item 25c: peringatan H-7 sebelum masa berlaku lisensi habis.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLicenseExpiry());
  }

  void _checkLicenseExpiry() {
    final days = ref.read(licenseProvider).daysUntilExpiry;
    if (days == null || days < 0 || days > 7) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(days == 0
          ? 'Aktivasi berakhir hari ini — hubungi developer untuk perpanjang.'
          : 'Aktivasi akan berakhir dalam $days hari — hubungi developer '
              'untuk perpanjang.'),
    ));
  }

  Future<void> _checkBackupReminder() async {
    final status = await BackupReminder.load(ref.read(databaseProvider));
    if (!mounted || !status.overdue) return;
    final days = status.daysSince;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(days == null
          ? 'Data belum pernah dicadangkan. Backup sekarang?'
          : 'Sudah $days hari belum backup. Cadangkan sekarang?'),
      action: SnackBarAction(
        label: 'Backup',
        onPressed: () => context.push('/pengaturan/backup'),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
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
      // Item 21 (Fase 1) — status sync dulu tampil sbg banner tunggal di
      // sini, di ATAS setiap layar tab (termasuk di atas toolbar/AppBar
      // masing-masing). Follow-up user: posisinya harus "inline" spt
      // notifikasi lain (di BAWAH header tiap tab, sejajar dgn `InlineBanner`
      // yg sudah ada) — jadi `SyncStatusBanner` sekarang dipasang LANGSUNG di
      // tiap layar tab (`RingkasanScreen`/`KasirScreen`/`ProdukListScreen`/
      // `PelangganListScreen`/`LaporanScreen`/`PengaturanScreen`), bukan di
      // sini lagi. `SyncScreen` sendiri (sub-halaman Pengaturan) TIDAK
      // dipasangi (sudah tampil penuh di badan layarnya sendiri).
      body: widget.child,
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
