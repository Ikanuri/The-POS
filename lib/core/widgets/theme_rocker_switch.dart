import 'package:flutter/material.dart';

import '../diagnostics/perf_diag.dart';
import '../theme/app_motion.dart';

List<BoxShadow> _shadows(List<BoxShadow> s) =>
    PerfDiag.s.shadows ? s : const [];

class ThemeRockerSwitch extends StatelessWidget {
  const ThemeRockerSwitch(
      {super.key, required this.dark, required this.onTap, this.size = 46});
  final bool dark;
  final VoidCallback onTap;

  /// Ukuran ubin (persegi). Semua proporsi di bawah diambil dari saklar
  /// GoPay (diukur dari screenshot): lekukan 34% x 56% ubin, muka kotak 76%
  /// tinggi lekukan.
  final double size;

  /// Saklar "ilusi optik" ala GoPay: SEBENARNYA hanya satu kotak yang
  /// bergeser naik/turun di dalam lekukan. Gelap = kotak di ATAS, lubang
  /// hitam tampak di bawahnya; terang = kotak di BAWAH, lubang putih tampak
  /// di atasnya.
  @override
  Widget build(BuildContext context) {
    final dur = AppMotion.dur(context, AppMotion.medium);
    final wellW = size * 0.344;
    final wellH = size * 0.56;
    final faceH = wellH * 0.76;
    final travel = wellH - faceH - 1.6; // sisa ruang geser (dalam garis tepi)
    return Semantics(
      button: true,
      label: dark ? 'Ganti ke mode terang' : 'Ganti ke mode gelap',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: dark ? 0.0 : 1.0), // 0 = gelap (kotak atas)
          duration: dur,
          curve: AppMotion.easeOutBack,
          builder: (context, k, _) {
            // k: 0 = gelap, 1 = terang (warna ikut berpindah mulus).
            final kc = k.clamp(0.0, 1.0);
            Color c(int dk, int lt) => Color.lerp(Color(dk), Color(lt), kc)!;
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.227),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    c(0xFF2C2F34, 0xFFFBFCFE),
                    c(0xFF252A2E, 0xFFF7F8FA)
                  ],
                ),
                boxShadow: _shadows([
                  BoxShadow(
                      color: Color.lerp(const Color(0x66000000),
                          const Color(0x1F000000), kc)!,
                      blurRadius: 6,
                      offset: const Offset(0, 2)),
                ]),
              ),
              alignment: Alignment.center,
              child: Container(
                width: wellW,
                height: wellH,
                decoration: BoxDecoration(
                  // Lubang di balik kotak: hitam (gelap) / putih (terang).
                  color: c(0xFF08090B, 0xFFFBFBFB),
                  borderRadius: BorderRadius.circular(wellW * 0.26),
                  border:
                      Border.all(color: c(0xFF141519, 0xFFDFE0E4), width: 0.8),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0.4,
                      right: 0.4,
                      // k=0 -> menempel atas, k=1 -> menempel bawah.
                      top: 0.4 + travel * k,
                      height: faceH,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(wellW * 0.24),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              c(0xFF1A1E21, 0xFFE6E7E9),
                              c(0xFF252A2E, 0xFFF9FAFC),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
