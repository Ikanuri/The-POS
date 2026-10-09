import '../kasir/cart_provider.dart' show kasirLandingProvider;
import 'kasir_sticker_sheet.dart';
import '../kasir/kasir_style.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../../core/theme/app_style.dart';
import '../../core/providers/scan_frame_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/device_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/export_destination.dart';
import '../../core/utils/input_formatters.dart';
import '../shell/sync_status_banner.dart';
import '../../core/theme/app_overlays.dart';

const _thousandsFmt = ThousandsSeparatorFormatter();

/// Toggle tampilkan nama pegawai di struk share & cetak. Default ON.
final _showEmployeeProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final v = await db.getSetting('receipt_show_employee');
  return v == null || v == '1';
});

/// Aturan poin loyalitas: setiap belanja [threshold] rupiah → dapat [pointsPer]
/// poin. threshold = 0 menonaktifkan poin otomatis.
final loyaltyRuleProvider =
    FutureProvider<({int threshold, int pointsPer})>((ref) async {
  final db = ref.watch(databaseProvider);
  final t =
      int.tryParse(await db.getSetting('loyalty_point_threshold') ?? '') ?? 0;
  final p = int.tryParse(await db.getSetting('loyalty_points_per') ?? '') ?? 1;
  return (threshold: t, pointsPer: p < 1 ? 1 : p);
});

/// Boleh membuka layar Pengeluaran: owner/asisten selalu; kasir bila izin
/// `input_pengeluaran` aktif.
final _canInputExpenseProvider = FutureProvider<bool>((ref) async {
  final device = ref.watch(deviceProvider);
  if (device.canSeeReports) return true;
  final db = ref.watch(databaseProvider);
  return db.isPermissionEnabled('input_pengeluaran');
});

/// Screening "guard file sensitif" (permintaan user) — "Backup & Restore"
/// & "Import/Export CSV Produk" dulu TIDAK PERNAH bisa diakses non-owner
/// sama sekali (backup malah dulu terlihat tanpa gate apa pun — celah
/// nyata). Sekarang: owner selalu, Kasir/Asisten opsional lewat toggle
/// `akses_backup`/`asisten_akses_backup` masing² (default OFF, lihat
/// `kKasirPermissionKeys`/`kAsistenPermissionKeys`) — owner yang putuskan
/// per toko, BUKAN hardcode role. "Alihkan Owner" SENGAJA TIDAK dapat
/// provider serupa — tetap owner-only murni (lihat `AlihOwnerScreen`).
final _canAccessBackupProvider = FutureProvider<bool>((ref) async {
  final device = ref.watch(deviceProvider);
  if (device.isOwner) return true;
  final db = ref.watch(databaseProvider);
  final key =
      device.deviceRole == 'asisten' ? 'asisten_akses_backup' : 'akses_backup';
  return db.isPermissionEnabled(key);
});

/// Pasangan [_canAccessBackupProvider] utk Import/Export CSV Produk.
final _canAccessCsvProvider = FutureProvider<bool>((ref) async {
  final device = ref.watch(deviceProvider);
  if (device.isOwner) return true;
  final db = ref.watch(databaseProvider);
  final key = device.deviceRole == 'asisten'
      ? 'asisten_akses_csv_produk'
      : 'akses_csv_produk';
  return db.isPermissionEnabled(key);
});

/// Izinkan kasir jual meski stok 0 (pre-order) — setting global. Dulu ada
/// langsung di halaman Pengaturan, sempat dipindah ke dalam Izin Kasir
/// (kurang terlihat), sekarang dikembalikan jadi entri terpisah di sini
/// (owner selalu bebas tanpa toggle ini — lihat resolveAllowNegativeStock).
final _allowNegativeStockProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final v = await db.getSetting('allow_negative_stock');
  return v == '1';
});

/// Item susulan usulan user: jeda pelacakan stok semua produk sementara
/// (mis. sedang tidak sempat rapikan data stok, tapi kasir tetap perlu
/// jualan tanpa peringatan/pengurangan stok). Lihat
/// `AppDatabase.pauseStockTrackingForAllProducts`.
final _stockPauseProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  return db.isStockTrackingPaused();
});

class PengaturanScreen extends ConsumerWidget {
  const PengaturanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider);
    final themeMode = ref.watch(themeModeProvider);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Aksen warna soft per fungsi (mockup Varian B, dipilih user): tiap
    // kartu SEKSI diwarnai menurut domainnya — hue sama dgn Ringkasan/
    // Laporan (bukan warna baru per layar).
    // "Device Ini" SENGAJA netral (tanpa aksen) — permintaan user.

    // Item 24d — label "Pegawai" KOSMETIK saja. Nilai internal deviceRole
    // TETAP 'kasir' (lihat catatan di kKasirPermissionKeys/PLAN.md) — jangan
    // ganti string switch di bawah jadi 'pegawai'.
    String roleLabel(String role) => switch (role) {
          'owner' => 'Owner',
          'asisten' => 'Asisten',
          'kasir' => 'Pegawai',
          _ => role,
        };

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 18,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                device.storeName.isNotEmpty
                    ? device.storeName
                    : roleLabel(device.deviceRole),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant)),
            Text('Pengaturan',
                style: AppTheme.numStyle(context,
                    size: 21, weight: FontWeight.w600)),
          ],
        ),
      ),
      body: Column(
        children: [
          const SyncStatusBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SectionHeader('Device Ini'),
                Container(
                  key: const Key('setting-device-hero'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppStyle.rPanel),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFD97757), Color(0xFFC96442)],
                    ),
                    boxShadow: AppStyle.accentShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.22),
                        ),
                        child: Text(
                          device.deviceCode.isEmpty ? '?' : device.deviceCode,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(device.deviceName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                                '${roleLabel(device.deviceRole)} · ${device.storeName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const _SectionHeader('Toko'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: SettingsIconBubble(Icons.store_outlined, AppTheme.changeFg(isDark), AppTheme.changeBg(isDark)),
                        title: const Text('Informasi Toko'),
                        subtitle:
                            const Text('Nama, alamat, telepon, catatan struk'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/pengaturan/toko'),
                      ),
                      ListTile(
                        leading: SettingsIconBubble(Icons.payments_outlined, AppTheme.changeFg(isDark), AppTheme.changeBg(isDark)),
                        title: const Text('Metode Pembayaran'),
                        subtitle: const Text('QRIS, transfer bank, e-wallet'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/pengaturan/metode-bayar'),
                      ),
                      // "Kategori Harga" PINDAH ke layar Produk (permintaan
                      // user, revisi 3) — lebih dekat konteksnya ke daftar
                      // produk drpd Pengaturan. Route-nya sendiri TETAP
                      // `/pengaturan/kategori-harga` (URL internal, tidak
                      // terlihat user), cuma entry point-nya yang pindah —
                      // lihat `produk_list_screen.dart`.
                      Builder(builder: (context) {
                        final canExpense =
                            ref.watch(_canInputExpenseProvider).valueOrNull ??
                                false;
                        if (!canExpense) return const SizedBox.shrink();
                        return ListTile(
                          leading: SettingsIconBubble(Icons.money_off_outlined, AppTheme.changeFg(isDark), AppTheme.changeBg(isDark)),
                          title: const Text('Pengeluaran'),
                          subtitle: const Text(
                              'Catat biaya operasional & kas keluar'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/pengaturan/pengeluaran'),
                        );
                      }),
                      ListTile(
                        leading: SettingsIconBubble(Icons.badge_outlined, AppTheme.changeFg(isDark), AppTheme.changeBg(isDark)),
                        title: const Text('Pegawai Toko'),
                        subtitle:
                            const Text('Dicatat di tiap nota (yang melayani)'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/pengaturan/pegawai'),
                      ),
                      if (device.isOwner) ...[
                        Builder(builder: (context) {
                          final show =
                              ref.watch(_showEmployeeProvider).valueOrNull ??
                                  true;
                          return SwitchListTile(
                            secondary: SettingsIconBubble(Icons.receipt_long_outlined, AppTheme.changeFg(isDark), AppTheme.changeBg(isDark)),
                            title: const Text('Pegawai di Struk'),
                            subtitle: const Text(
                                'Tampilkan nama pegawai di struk share & cetak'),
                            value: show,
                            onChanged: (v) async {
                              final db = ref.read(databaseProvider);
                              await db.setSetting(
                                  'receipt_show_employee', v ? '1' : '0');
                              ref.invalidate(_showEmployeeProvider);
                            },
                          );
                        }),
                        Builder(builder: (context) {
                          final allow = ref
                                  .watch(_allowNegativeStockProvider)
                                  .valueOrNull ??
                              false;
                          return SwitchListTile(
                            secondary: SettingsIconBubble(Icons.inventory_2_outlined, AppTheme.changeFg(isDark), AppTheme.changeBg(isDark)),
                            title: const Text('Izinkan Stok Minus'),
                            subtitle: const Text(
                                'Pegawai bisa jual meski stok 0 (pre-order) — owner selalu bisa terlepas dari ini'),
                            value: allow,
                            onChanged: (v) async {
                              final db = ref.read(databaseProvider);
                              await db.setSetting(
                                  'allow_negative_stock', v ? '1' : '0');
                              ref.invalidate(_allowNegativeStockProvider);
                            },
                          );
                        }),
                      ],
                      if (device.isOwner) ...[
                        ListTile(
                          leading: SettingsIconBubble(Icons.tune_outlined, AppTheme.changeFg(isDark), AppTheme.changeBg(isDark)),
                          title: const Text('Izin Pegawai'),
                          subtitle:
                              const Text('Override harga, input stok, dll'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/pengaturan/izin-kasir'),
                        ),
                        ListTile(
                          leading: SettingsIconBubble(Icons.badge_outlined, AppTheme.changeFg(isDark), AppTheme.changeBg(isDark)),
                          title: const Text('Izin Asisten'),
                          subtitle: const Text('Izinkan stok minus, dll'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/pengaturan/izin-asisten'),
                        ),
                        Builder(builder: (context) {
                          final rule =
                              ref.watch(loyaltyRuleProvider).valueOrNull;
                          final subtitle = rule == null || rule.threshold <= 0
                              ? 'Nonaktif — ketuk untuk mengatur'
                              : 'Setiap belanja ${formatRupiah(rule.threshold)} '
                                  '→ ${rule.pointsPer} poin';
                          return ListTile(
                            leading: SettingsIconBubble(Icons.stars_outlined, AppTheme.changeFg(isDark), AppTheme.changeBg(isDark)),
                            title: const Text('Poin Loyalitas'),
                            subtitle: Text(subtitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _showLoyaltyDialog(context, ref),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const _SectionHeader('Sinkronisasi'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: SettingsIconBubble(Icons.wifi_outlined, AppTheme.riwayatFg(isDark), AppTheme.riwayatBg(isDark)),
                        title: const Text('Sync WiFi'),
                        subtitle: const Text(
                            'Sinkronisasi antar HP via jaringan lokal'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/pengaturan/sync'),
                      ),
                      Builder(builder: (context) {
                        final canBackup =
                            ref.watch(_canAccessBackupProvider).valueOrNull ??
                                false;
                        if (!canBackup) return const SizedBox.shrink();
                        return ListTile(
                          leading: SettingsIconBubble(Icons.save_alt_outlined, AppTheme.riwayatFg(isDark), AppTheme.riwayatBg(isDark)),
                          title: const Text('Backup & Restore'),
                          subtitle: const Text('File terenkripsi .berkahpos'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/pengaturan/backup'),
                        );
                      }),
                      // Alihkan Owner SENGAJA TIDAK dapat toggle izin spt
                      // Backup/CSV di atas — menimpa TOTAL identitas+data
                      // toko/device (bukan cuma data biasa), tetap
                      // owner-only murni (lihat dok `_canAccessBackupProvider`).
                      if (device.isOwner)
                        ListTile(
                          leading: SettingsIconBubble(Icons.swap_horiz_outlined, AppTheme.riwayatFg(isDark), AppTheme.riwayatBg(isDark)),
                          title: const Text('Alihkan Owner'),
                          subtitle: const Text(
                              'Pindahkan seluruh data & identitas toko ke device lain'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/pengaturan/alih-owner'),
                        ),
                      Builder(builder: (context) {
                        final canCsv =
                            ref.watch(_canAccessCsvProvider).valueOrNull ??
                                false;
                        if (!canCsv) return const SizedBox.shrink();
                        return Column(children: [
                          ListTile(
                            leading: SettingsIconBubble(Icons.upload_file_outlined, AppTheme.riwayatFg(isDark), AppTheme.riwayatBg(isDark)),
                            title: const Text('Import Produk CSV'),
                            subtitle:
                                const Text('Impor daftar produk dari file CSV'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/pengaturan/import-csv'),
                          ),
                          ListTile(
                            leading: SettingsIconBubble(Icons.download_outlined, AppTheme.riwayatFg(isDark), AppTheme.riwayatBg(isDark)),
                            title: const Text('Export Produk CSV'),
                            subtitle: const Text(
                                'Ekspor seluruh produk aktif ke CSV'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _exportProductsCsv(context, ref),
                          ),
                        ]);
                      }),
                      if (device.isOwner) ...[
                        ListTile(
                          leading: SettingsIconBubble(Icons.storefront_outlined, AppTheme.riwayatFg(isDark), AppTheme.riwayatBg(isDark)),
                          title: const Text('Katalog Pesanan'),
                          subtitle: const Text(
                              'Bagikan katalog HTML agar pelanggan bisa pesan sendiri'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              context.push('/pengaturan/katalog-pesanan'),
                        ),
                        ListTile(
                          leading: SettingsIconBubble(Icons.qr_code_2_outlined, AppTheme.riwayatFg(isDark), AppTheme.riwayatBg(isDark)),
                          title: const Text('Pair Device Baru'),
                          subtitle:
                              const Text('Tambah HP kasir / asisten via QR'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/pengaturan/pair'),
                        ),
                      ],
                    ],
                  ),
                ),
                if (device.isOwner) ...[
                  const SizedBox(height: 8),
                  const _SectionHeader('Manajemen Data'),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: SettingsIconBubble(Icons.point_of_sale_outlined, AppTheme.debtFg(isDark), AppTheme.debtBg(isDark)),
                          title: const Text('Tutup Kasir'),
                          subtitle: const Text(
                              'Rekap kas harian: sistem vs uang fisik'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/pengaturan/tutup-kasir'),
                        ),
                        ListTile(
                          leading: SettingsIconBubble(Icons.archive_outlined, AppTheme.debtFg(isDark), AppTheme.debtBg(isDark)),
                          title: const Text('Tutup Buku'),
                          subtitle: const Text('Arsipkan transaksi tahun lalu'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/pengaturan/tutup-buku'),
                        ),
                        ListTile(
                          leading: SettingsIconBubble(Icons.folder_zip_outlined, AppTheme.debtFg(isDark), AppTheme.debtBg(isDark)),
                          title: const Text('Buka Arsip'),
                          subtitle: const Text(
                              'Lihat laporan tahun yang sudah diarsipkan'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/pengaturan/arsip'),
                        ),
                        Consumer(builder: (context, ref, _) {
                          final paused =
                              ref.watch(_stockPauseProvider).valueOrNull ??
                                  false;
                          return SwitchListTile(
                            secondary: SettingsIconBubble(Icons.inventory_2_outlined, AppTheme.debtFg(isDark), AppTheme.debtBg(isDark)),
                            title: const Text('Jeda Pelacakan Stok'),
                            subtitle: Text(paused
                                ? 'Aktif — semua produk yang tadinya dilacak sementara jadi non-stok'
                                : 'Set semua produk yang masih dilacak jadi non-stok sementara'),
                            value: paused,
                            onChanged: (v) =>
                                _toggleStockPause(context, ref, v),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const _SectionHeader('Perangkat'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: SettingsIconBubble(Icons.print_outlined, AppTheme.tealFg(isDark), AppTheme.tealBg(isDark)),
                        title: const Text('Printer Bluetooth'),
                        subtitle: const Text('Pilih printer & test cetak'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/pengaturan/printer'),
                      ),
                      // Khusus build beta/debug (bukan produksi): saklar
                      // diagnostik performa layar Kasir.
                      if (appFlavor != 'production')
                        ListTile(
                          key: const Key('setting-perf-diag'),
                          leading: SettingsIconBubble(Icons.speed_outlined, AppTheme.tealFg(isDark), AppTheme.tealBg(isDark)),
                          title: const Text('Diagnostik Performa'),
                          subtitle: const Text(
                              'Matikan fitur satu per satu untuk mencari biang lag'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/pengaturan/diagnostik'),
                        ),
                      // Gaya Kasir Baru memindahkan sakelar terang/gelap ke
                      // layar Kasir (tombol pojok) - di sini disembunyikan.
                      if (ref.watch(kasirStyleProvider) != KasirStyle.modern)
                        SwitchListTile(
                          key: const Key('setting-dark-mode'),
                          secondary: SettingsIconBubble(Icons.dark_mode_outlined, AppTheme.tealFg(isDark), AppTheme.tealBg(isDark)),
                          title: const Text('Mode Gelap'),
                          value: themeMode == ThemeMode.dark,
                          onChanged: (_) =>
                              ref.read(themeModeProvider.notifier).toggle(),
                        ),
                      Builder(builder: (context) {
                        final scale = ref.watch(fontScaleProvider);
                        return ListTile(
                          leading: SettingsIconBubble(Icons.text_fields_outlined, AppTheme.tealFg(isDark), AppTheme.tealBg(isDark)),
                          title: const Text('Ukuran Teks'),
                          subtitle: Text(scale.label),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showFontScaleDialog(context, ref),
                        );
                      }),
                      Padding(
                        key: const Key('setting-kasir-style'),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Gaya Kasir',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              ref.watch(kasirStyleProvider) == KasirStyle.modern
                                  ? 'Baru — landing, kolom cari berpindah, tombol aksi melayang'
                                  : 'Klasik — header dan daftar produk langsung',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<KasirStyle>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(
                                      value: KasirStyle.classic,
                                      label: Text('Klasik')),
                                  ButtonSegment(
                                      value: KasirStyle.modern,
                                      label: Text('Baru')),
                                ],
                                selected: {ref.watch(kasirStyleProvider)},
                                onSelectionChanged: (v) => ref
                                    .read(kasirStyleProvider.notifier)
                                    .set(v.first),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        key: const Key('setting-scan-frame'),
                        secondary: SettingsIconBubble(Icons.center_focus_strong_outlined, AppTheme.tealFg(isDark), AppTheme.tealBg(isDark)),
                        title: const Text('Bingkai Scanner ala Telegram'),
                        subtitle: const Text(
                            'Eksperimental — bingkai mengikuti posisi barcode/QR '
                            '(Kasir, form produk, Sync LAN). Mati = scanner lama'),
                        value: ref.watch(scanFrameTelegramProvider),
                        onChanged: (v) =>
                            ref.read(scanFrameTelegramProvider.notifier).set(v),
                      ),
                      SwitchListTile(
                        key: const Key('setting-kasir-landing'),
                        secondary: SettingsIconBubble(Icons.home_outlined, AppTheme.tealFg(isDark), AppTheme.tealBg(isDark)),
                        title: const Text('Tampilan Awal Kasir'),
                        subtitle: Text(ref.watch(kasirLandingProvider)
                            ? 'Landing — Terlaris, Terakhir dijual & kategori'
                            : 'Langsung daftar semua produk'),
                        value: ref.watch(kasirLandingProvider),
                        onChanged: (v) =>
                            ref.read(kasirLandingProvider.notifier).set(v),
                      ),
                      // Stiker & teks landing ikut tersinkron ke perangkat
                      // lain -> hanya owner yang boleh mengubahnya.
                      if (ref.watch(deviceProvider).isOwner)
                        ListTile(
                          key: const Key('setting-kasir-sticker'),
                          leading: SettingsIconBubble(Icons.emoji_emotions_outlined, AppTheme.tealFg(isDark), AppTheme.tealBg(isDark)),
                          title: const Text('Stiker & Teks Landing Kasir'),
                          subtitle: const Text(
                              'Stiker .tgs + teks di bawahnya (tersinkron)'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => KasirStickerSheet.show(context),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const _SectionHeader('Diagnostik'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: SettingsIconBubble(Icons.bug_report_outlined, AppTheme.antrianFg(isDark), AppTheme.antrianBg(isDark)),
                        title: const Text('Log Error Terakhir'),
                        subtitle: const Text(
                            'Catatan error yang tertangkap otomatis, bisa dibagikan ke developer'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/pengaturan/log-error'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const _SectionHeader('Lainnya'),
                // Baris ber-aksen (mockup): satu-satunya entri di Pengaturan
                // yang diberi tint aksen — pintu masuk ke identitas app
                // (versi, panduan, lisensi), bukan setelan yang diubah-ubah.
                Card(
                  color: scheme.primary.withOpacity(0.06),
                  child: ListTile(
                    leading: Icon(Icons.info_outline, color: scheme.primary),
                    title: Text(
                      'Tentang Aplikasi',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text('Versi, panduan & tips, lisensi'),
                    trailing: Icon(Icons.chevron_right, color: scheme.primary),
                    onTap: () => context.push('/pengaturan/tentang'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFontScaleDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(fontScaleProvider);
    showAppDialog<FontScale>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Ukuran Teks'),
        children: FontScale.values.map((s) {
          return RadioListTile<FontScale>(
            title: Text(s.label),
            subtitle: Text(
              'Aa Bb Cc 123',
              style: TextStyle(fontSize: 14 * s.factor),
            ),
            value: s,
            groupValue: current,
            onChanged: (v) {
              if (v != null) {
                ref.read(fontScaleProvider.notifier).set(v);
                Navigator.pop(ctx, v);
              }
            },
          );
        }).toList(),
      ),
    );
  }

  Future<void> _showLoyaltyDialog(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final curThreshold =
        int.tryParse(await db.getSetting('loyalty_point_threshold') ?? '') ?? 0;
    final curPer =
        int.tryParse(await db.getSetting('loyalty_points_per') ?? '') ?? 1;
    if (!context.mounted) return;

    final thresholdCtrl = TextEditingController(
        text: curThreshold > 0
            ? ThousandsSeparatorFormatter.format(curThreshold)
            : '');
    final perCtrl =
        TextEditingController(text: (curPer < 1 ? 1 : curPer).toString());

    final saved = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Poin Loyalitas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pelanggan terdaftar otomatis dapat poin tiap transaksi lunas. '
              'Kosongkan nominal untuk menonaktifkan.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: thresholdCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: const [_thousandsFmt],
              decoration: const InputDecoration(
                labelText: 'Setiap belanja (Rp)',
                prefixText: 'Rp ',
                hintText: 'mis. 10.000',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: perCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Dapat berapa poin',
                suffixText: 'poin',
                hintText: 'mis. 1',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final threshold =
          ThousandsSeparatorFormatter.parseValue(thresholdCtrl.text);
      final per = int.tryParse(perCtrl.text.trim()) ?? 1;
      await db.setSetting('loyalty_point_threshold', threshold.toString());
      await db.setSetting('loyalty_points_per', (per < 1 ? 1 : per).toString());
      ref.invalidate(loyaltyRuleProvider);
    }
    thresholdCtrl.dispose();
    perCtrl.dispose();
  }

  Future<void> _toggleStockPause(
      BuildContext context, WidgetRef ref, bool turnOn) async {
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);

    if (turnOn) {
      final confirmed = await showAppDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Jeda Pelacakan Stok?'),
          content: const Text(
              'SEMUA produk yang saat ini masih dilacak stoknya akan '
              'ditandai non-stok sementara — kasir bisa jual tanpa '
              'peringatan/pengurangan stok. Produk yang sudah non-stok '
              'sebelumnya (mis. varian jasa) tidak ikut tersentuh. Bisa '
              'dikembalikan kapan saja lewat toggle yang sama.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Jeda')),
          ],
        ),
      );
      if (confirmed != true) return;
      final count = await db.pauseStockTrackingForAllProducts();
      ref.invalidate(_stockPauseProvider);
      messenger.showAppSnackBar(
          SnackBar(content: Text('$count produk ditandai non-stok sementara')));
    } else {
      final count = await db.resumeStockTrackingForAllProducts();
      ref.invalidate(_stockPauseProvider);
      messenger.showAppSnackBar(
          SnackBar(content: Text('Pelacakan stok $count produk dipulihkan')));
    }
  }
}

String _escapeCsv(String? value) {
  if (value == null || value.isEmpty) return '';
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

Future<void> _exportProductsCsv(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final messenger = ScaffoldMessenger.of(context);

  try {
    final products = await db.searchProducts('');
    final unitTypes = await db.getAllUnitTypes();
    final typeNameById = {for (final u in unitTypes) u.id: u.name};

    final buf = StringBuffer();
    buf.writeln('nama,kode_produk,satuan,harga_jual,harga_beli,stok,barcode');

    for (final p in products) {
      final units = await db.getProductUnits(p.id);
      for (final u in units) {
        final tiers = await db.getPriceTiers(u.id);
        final baseTier =
            tiers.where((t) => t.minQty == 1).firstOrNull ?? tiers.firstOrNull;
        final barcodes = await db.getProductBarcodes(u.id);
        final barcode = barcodes.firstOrNull?.barcode ?? '';
        final stock = await db.currentStock(u.id);
        final unitName =
            u.unitTypeId != null ? (typeNameById[u.unitTypeId!] ?? '') : '';

        buf.writeln([
          _escapeCsv(p.name),
          _escapeCsv(p.kodeProduk),
          _escapeCsv(unitName),
          baseTier?.price ?? 0,
          baseTier?.costPrice ?? 0,
          stock % 1 == 0 ? stock.toInt() : stock,
          _escapeCsv(barcode),
        ].join(','));
      }
    }

    final bytes = utf8.encode(buf.toString());
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    if (!context.mounted) return;
    final done = await saveOrShareExport(
      context: context,
      bytes: Uint8List.fromList(bytes),
      fileName: 'produk_$date.csv',
      shareText: 'Data produk toko',
      title: 'Simpan CSV',
    );
    if (!done) return;
    messenger.showAppSnackBar(
      const SnackBar(content: Text('Selesai')),
    );
  } catch (e) {
    messenger.showAppSnackBar(
      SnackBar(content: Text('Gagal ekspor: $e')),
    );
  }
}

/// Ikon bulat berwarna fungsi di depan tiap baris pengaturan (gaya landing).
class SettingsIconBubble extends StatelessWidget {
  const SettingsIconBubble(this.icon, this.fg, this.bg, {super.key});
  final IconData icon;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
        child: Icon(icon, size: 20, color: fg),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
