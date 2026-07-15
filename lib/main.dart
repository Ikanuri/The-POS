import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

import 'core/providers/device_provider.dart';
import 'core/providers/license_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/crash_log_service.dart';
import 'core/services/temp_share_cleanup.dart';
import 'core/theme/app_theme.dart';
import 'features/kasir/cart_meta_provider.dart';
import 'features/kasir/cart_provider.dart';

void main() {
  // Jaring pengaman diagnosis crash (lihat docs/HANDOFF.md): tangkap SEMUA
  // error yang lolos dari penanganan normal (termasuk yang terjadi SEBELUM
  // runApp() sempat dipanggil) dan simpan ke file lokal di HP — supaya
  // tetap bisa dibaca via File Manager walau app force-close tanpa layar
  // error sama sekali. TIDAK menggantikan penanganan error yang sudah ada,
  // murni tambahan best-effort di lapisan paling luar.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Item 9 (batch 15 Juli) — font offline-first: SEMUA font (Hanken
    // Grotesk, Newsreader, Roboto Mono) sudah di-bundle lokal
    // (assets/fonts/), jangan pernah fetch dari CDN Google Fonts saat
    // runtime — device toko sering tidak online sama sekali.
    GoogleFonts.config.allowRuntimeFetching = false;

    FlutterError.onError = (details) {
      unawaited(CrashLogService.record(details.exception, details.stack,
          context: 'FlutterError.onError'));
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
          CrashLogService.record(error, stack, context: 'PlatformDispatcher.onError'));
      return true;
    };

    // Beberapa versi Android gagal dlopen libsqlcipher tanpa workaround ini.
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
    }

    final container = ProviderContainer();
    // Identitas device harus dimuat sebelum router memutuskan redirect /setup.
    await container.read(deviceProvider.notifier).load();
    // Item 25c — gerbang lisensi juga harus dimuat sebelum router memutuskan
    // redirect /aktivasi (dicek lebih awal dari /setup, lihat app_router.dart).
    await container.read(licenseProvider.notifier).load();

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const ThePosApp(),
      ),
    );

    // Pekerjaan catch-up dijalankan SETELAH runApp agar tidak menahan frame
    // pertama — durasi backfill tumbuh seiring data (O(total tx)), dan pada
    // toko lama sempat membuat splash tertahan ratusan ms tiap startup.
    unawaited(_runStartupMaintenance(container));
  }, (error, stack) {
    unawaited(CrashLogService.record(error, stack, context: 'runZonedGuarded'));
  });
}

/// Catch-up non-fatal saat startup: materialisasi ringkasan harian, backfill
/// buku pembayaran untuk data lama, dan pembersihan keranjang yatim. Semua
/// idempotent — aman berjalan paralel dengan pemakaian app.
Future<void> _runStartupMaintenance(ProviderContainer container) async {
  // Ringkasan & buku pembayaran hanya bila DB sudah bisa dibuka.
  if (container.read(deviceProvider).isConfigured) {
    try {
      final db = container.read(databaseProvider);
      await db.backfillMissingSummaries();
      // Lengkapi buku pembayaran untuk nota lama (data pra-fitur / import)
      // agar timeline pembayaran di struk tetap muncul.
      await db.backfillMissingPayments();
    } catch (_) {
      // Non-fatal — laporan & struk tetap berfungsi tanpa pre-aggregate.
    }
  }

  // Bersihkan keranjang "tambah belanjaan" yatim (>24 jam) yang tidak selesai.
  await CartNotifier.cleanupOrphanCarts();
  // Metadata keranjang yatim mengikuti pembersihan keranjang di atas.
  await CartMetaNotifier.cleanupOrphanMeta();
  // Item 8 — file gambar/HTML sementara hasil "Bagikan" yang tidak pernah
  // dihapus sebelumnya (menumpuk di temp dir).
  await TempShareCleanup.run();
}

class ThePosApp extends ConsumerWidget {
  const ThePosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'The POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      // Terapkan warna system navigation bar sesuai tema yang sedang aktif.
      // Builder dipanggil setelah MaterialApp me-resolve tema, sehingga
      // Theme.of(context).brightness sudah benar untuk ThemeMode.system.
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            systemNavigationBarColor: AppTheme.canvasColor(isDark),
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarDividerColor: Colors.transparent,
          ),
        );

        final userScale = ref.watch(fontScaleProvider).factor;
        final mq = MediaQuery.of(context);
        final shortestSide = mq.size.shortestSide;
        final deviceFactor = (shortestSide / 390).clamp(0.92, 1.08);
        final combined = userScale * deviceFactor;

        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(combined)),
          child: child!,
        );
      },
    );
  }
}
