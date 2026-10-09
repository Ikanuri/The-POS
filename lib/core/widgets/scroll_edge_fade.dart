import 'package:flutter/material.dart';

/// Pemudaran tepi ala Telegram: konten yang menggulir memudar halus ke warna
/// latar di tepi atas/bawah (bukan terpotong tegas). Overlay gradien murni
/// (tanpa ShaderMask) supaya murah dan tak memaksa layer offscreen; tidak
/// menangkap sentuhan.
class ScrollEdgeFade extends StatelessWidget {
  const ScrollEdgeFade({
    super.key,
    required this.child,
    this.top = 0,
    this.bottom = 0,
    this.color,
  });

  final Widget child;

  /// Tinggi pemudaran (dp); 0 = tanpa.
  final double top;
  final double bottom;

  /// Warna latar tujuan; default `scaffoldBackgroundColor`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? Theme.of(context).scaffoldBackgroundColor;
    Widget strip(double h, bool atTop) => IgnorePointer(
          child: SizedBox(
            height: h,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: atTop ? Alignment.topCenter : Alignment.bottomCenter,
                  end: atTop ? Alignment.bottomCenter : Alignment.topCenter,
                  // Kurva lembut: tebal di tepi, menipis perlahan.
                  colors: [
                    bg,
                    bg.withOpacity(0.75),
                    bg.withOpacity(0.3),
                    bg.withOpacity(0),
                  ],
                  stops: const [0, 0.35, 0.7, 1],
                ),
              ),
            ),
          ),
        );

    return Stack(
      children: [
        Positioned.fill(child: child),
        if (top > 0)
          Positioned(
              key: const Key('edge-fade-top'),
              top: 0,
              left: 0,
              right: 0,
              child: strip(top, true)),
        if (bottom > 0)
          Positioned(
              key: const Key('edge-fade-bottom'),
              bottom: 0,
              left: 0,
              right: 0,
              child: strip(bottom, false)),
      ],
    );
  }
}
