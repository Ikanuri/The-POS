import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/kasir/kasir_screen.dart';
import '../../features/laporan/laporan_screen.dart';
import '../../features/pelanggan/pelanggan_list_screen.dart';
import '../../features/pengaturan/pengaturan_screen.dart';
import '../../features/produk/produk_list_screen.dart';
import '../../features/ringkasan/ringkasan_screen.dart';
import '../../features/setup/pairing_screen.dart';
import '../../features/setup/setup_toko_screen.dart';
import '../../features/setup/welcome_screen.dart';
import '../../features/shell/main_shell.dart';
import '../providers/device_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/kasir',
    redirect: (context, state) {
      final device = ref.read(deviceProvider);
      final inSetup = state.matchedLocation.startsWith('/setup');
      if (!device.isConfigured && !inSetup) return '/setup';
      if (device.isConfigured && inSetup) return '/kasir';
      // Laporan hanya owner/asisten.
      if (state.matchedLocation == '/laporan' && !device.canSeeReports) {
        return '/kasir';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/setup',
        builder: (_, __) => const WelcomeScreen(),
        routes: [
          GoRoute(path: 'baru', builder: (_, __) => const SetupTokoScreen()),
          GoRoute(path: 'gabung', builder: (_, __) => const PairingScreen()),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/ringkasan', builder: (_, __) => const RingkasanScreen()),
          GoRoute(path: '/kasir', builder: (_, __) => const KasirScreen()),
          GoRoute(path: '/produk', builder: (_, __) => const ProdukListScreen()),
          GoRoute(path: '/pelanggan', builder: (_, __) => const PelangganListScreen()),
          GoRoute(path: '/laporan', builder: (_, __) => const LaporanScreen()),
          GoRoute(path: '/pengaturan', builder: (_, __) => const PengaturanScreen()),
        ],
      ),
    ],
  );
});
