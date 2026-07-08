import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/produk/barcode_screen.dart';
import '../../features/kasir/kasir_screen.dart';
import '../../features/kasir/payment_screen.dart';
import '../../features/kasir/receipt_screen.dart';
import '../../features/laporan/laporan_screen.dart';
import '../../features/pelanggan/pelanggan_form_screen.dart';
import '../../features/pelanggan/pelanggan_list_screen.dart';
import '../../features/pengaturan/arsip_screen.dart';
import '../../features/pengaturan/backup_screen.dart';
import '../../features/pengaturan/csv_import_screen.dart';
import '../../features/pengaturan/asisten_permissions_screen.dart';
import '../../features/pengaturan/kasir_permissions_screen.dart';
import '../../features/pengaturan/order_share_screen.dart';
import '../../features/pengaturan/pair_device_screen.dart';
import '../../features/pengaturan/payment_methods_screen.dart';
import '../../features/pengaturan/pengaturan_screen.dart';
import '../../features/pengaturan/employee_screen.dart';
import '../../features/pengaturan/printer_screen.dart';
import '../../features/pengaturan/store_info_screen.dart';
import '../../features/pengaturan/sync_screen.dart';
import '../../features/pengaturan/tutup_buku_screen.dart';
import '../services/price_match_service.dart';
import '../../features/produk/price_preview_screen.dart';
import '../../features/produk/price_sync_screen.dart';
import '../../features/produk/product_group_screen.dart';
import '../../features/produk/catalog/catalog_list_screen.dart';
import '../../features/produk/produk_form_screen.dart';
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
          GoRoute(
              path: '/ringkasan', builder: (_, __) => const RingkasanScreen()),
          GoRoute(
            path: '/kasir',
            builder: (_, __) => const KasirScreen(),
            routes: [
              GoRoute(
                path: 'bayar',
                builder: (_, __) => const PaymentScreen(),
              ),
              GoRoute(
                path: 'struk/:txId',
                builder: (_, state) =>
                    ReceiptScreen(transactionId: state.pathParameters['txId']!),
              ),
              // Tambah belanjaan ke transaksi yang sudah ada.
              GoRoute(
                path: 'tambah/:txId',
                builder: (_, state) =>
                    KasirScreen(addToTxId: state.pathParameters['txId']!),
                routes: [
                  GoRoute(
                    path: 'bayar',
                    builder: (_, state) =>
                        PaymentScreen(addToTxId: state.pathParameters['txId']!),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/produk',
            builder: (_, __) => const ProdukListScreen(),
            routes: [
              GoRoute(
                path: 'kategori',
                builder: (_, __) => const ProductGroupScreen(),
              ),
              GoRoute(
                path: 'katalog',
                builder: (_, __) => const CatalogListScreen(),
                routes: [
                  GoRoute(
                    path: 'buat',
                    builder: (_, __) => const KasirScreen(catalogMode: true),
                  ),
                ],
              ),
              GoRoute(
                path: 'sinkron-harga',
                builder: (_, __) => const PriceSyncScreen(),
                routes: [
                  GoRoute(
                    path: 'preview',
                    builder: (_, state) => PricePreviewScreen(
                      result: state.extra! as PriceMatchResult,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    ProdukFormScreen(productId: state.pathParameters['id']),
              ),
              GoRoute(
                path: ':id/barcode',
                builder: (_, state) =>
                    BarcodeScreen(productId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/pelanggan',
            builder: (_, __) => const PelangganListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    PelangganFormScreen(customerId: state.pathParameters['id']),
              ),
            ],
          ),
          GoRoute(path: '/laporan', builder: (_, __) => const LaporanScreen()),
          GoRoute(
            path: '/pengaturan',
            builder: (_, __) => const PengaturanScreen(),
            routes: [
              GoRoute(
                  path: 'toko', builder: (_, __) => const StoreInfoScreen()),
              GoRoute(
                  path: 'metode-bayar',
                  builder: (_, __) => const PaymentMethodsScreen()),
              GoRoute(
                  path: 'pegawai', builder: (_, __) => const EmployeeScreen()),
              GoRoute(
                  path: 'izin-kasir',
                  builder: (_, __) => const KasirPermissionsScreen()),
              GoRoute(
                  path: 'izin-asisten',
                  builder: (_, __) => const AsistenPermissionsScreen()),
              GoRoute(
                  path: 'pair', builder: (_, __) => const PairDeviceScreen()),
              GoRoute(path: 'sync', builder: (_, __) => const SyncScreen()),
              GoRoute(path: 'backup', builder: (_, __) => const BackupScreen()),
              GoRoute(
                  path: 'printer', builder: (_, __) => const PrinterScreen()),
              GoRoute(
                  path: 'import-csv',
                  builder: (_, __) => const CsvImportScreen()),
              GoRoute(
                  path: 'katalog-pesanan',
                  builder: (_, __) => const OrderShareScreen()),
              GoRoute(
                  path: 'tutup-buku',
                  builder: (_, __) => const TutupBukuScreen()),
              GoRoute(path: 'arsip', builder: (_, __) => const ArsipScreen()),
            ],
          ),
        ],
      ),
    ],
  );
});
