import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

import 'core/providers/device_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Beberapa versi Android gagal dlopen libsqlcipher tanpa workaround ini.
  if (Platform.isAndroid) {
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
  }

  final container = ProviderContainer();
  // Identitas device harus dimuat sebelum router memutuskan redirect /setup.
  await container.read(deviceProvider.notifier).load();

  // Catch-up ringkasan harian yang belum ter-materialisasi (mis. data dari
  // versi lama atau hari yang terlewat). Hanya bila DB sudah bisa dibuka.
  if (container.read(deviceProvider).isConfigured) {
    try {
      final db = container.read(databaseProvider);
      await db.backfillMissingSummaries();
      // Lengkapi buku pembayaran untuk nota lama (data pra-fitur / import) agar
      // timeline pembayaran di struk tetap muncul.
      await db.backfillMissingPayments();
    } catch (_) {
      // Non-fatal — laporan & struk tetap berfungsi tanpa pre-aggregate.
    }
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ThePosApp(),
    ),
  );
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
