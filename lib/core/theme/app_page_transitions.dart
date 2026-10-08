import 'package:flutter/material.dart';

import 'app_motion.dart';

/// Transisi halaman ala Telegram, dipasang lewat `PageTransitionsTheme`:
///
/// - **Sub-halaman (push)**: halaman baru memudar masuk sambil bergeser 48 px
///   dari kanan dan mendarat halus (easeOutQuint); halaman di bawahnya diam.
///   Saat kembali (pop) urutannya dibalik: halaman yang ditinggalkan cepat
///   menjauh lalu memudar. Tidak ada gerak layar penuh yang menutupi isi.
/// - **Pindah tab / halaman akar** (rute berawalan "/" di GoRouter —
///   `RouteSettings.name` diisi GoRouter dgn `path`-nya): memudar silang
///   dengan sedikit skala (0,985 -> 1), tanpa geser, karena tab itu setara,
///   bukan "lebih dalam".
/// - Pengguna mematikan animasi di sistem: tanpa transisi.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  /// Jarak geser masuk (setara 48 dp Telegram).
  static const slideDistance = 48.0;

  /// Rute akar/tab: nama rute GoRouter = path absolut ("/kasir", "/produk").
  static bool isRootRoute(PageRoute<dynamic> route) {
    final n = route.settings.name;
    return n != null && n.startsWith('/');
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Rute pertama saat app dibuka sudah selesai animasinya (nilai 1), jadi
    // aman tanpa pengecualian; pindah tab (`go`) mengganti seluruh tumpukan
    // sehingga halaman baru juga "rute pertama" tapi tetap beranimasi masuk.
    if (AppMotion.reduced(context)) return child;

    final eased = CurvedAnimation(
      parent: animation,
      curve: AppMotion.easeOutQuint,
      // Keluar: cepat di awal, melambat di akhir (kebalikan waktu dari masuk).
      reverseCurve: AppMotion.easeOutQuint.flipped,
    );

    if (isRootRoute(route)) {
      // Pindah tab terasa seketika: efektif ~200 ms dari 300 ms rute.
      final quick = CurvedAnimation(
        parent: animation,
        curve: const Interval(0, 0.7, curve: AppMotion.easeOutQuint),
        reverseCurve: Interval(0, 0.7, curve: AppMotion.easeOutQuint.flipped),
      );
      return FadeTransition(
        opacity: quick,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(quick),
          child: child,
        ),
      );
    }

    return FadeTransition(
      opacity: eased,
      child: AnimatedBuilder(
        animation: eased,
        child: child,
        builder: (context, child) => Transform.translate(
          offset: Offset(slideDistance * (1 - eased.value), 0),
          child: child,
        ),
      ),
    );
  }

  /// Pasangan builder untuk semua platform: iOS/macOS tetap gestur geser-balik
  /// bawaan Cupertino, sisanya memakai transisi di atas.
  static const theme = PageTransitionsTheme(builders: {
    TargetPlatform.android: AppPageTransitionsBuilder(),
    TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
    TargetPlatform.linux: AppPageTransitionsBuilder(),
    TargetPlatform.windows: AppPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
  });
}
