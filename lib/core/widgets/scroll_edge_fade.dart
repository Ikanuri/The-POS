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
    this.mask = false,
  });

  final Widget child;

  /// Tinggi pemudaran (dp); 0 = tanpa.
  final double top;
  final double bottom;

  /// Warna latar tujuan; default `scaffoldBackgroundColor`.
  final Color? color;

  /// true = pemudaran ALFA murni (konten sendiri memudar menjadi transparan,
  /// memperlihatkan apa pun yang ada di belakangnya: gradien/blob/warna
  /// berbeda) — untuk latar yang TIDAK datar (layar Kasir). Memakai
  /// `ShaderMask(dstIn)`; false = overlay warna datar (lebih murah).
  final bool mask;

  @override
  Widget build(BuildContext context) {
    if (mask) return _buildMask();
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

  Widget _buildMask() {
    if (top <= 0 && bottom <= 0) return child;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) {
        final h = r.height <= 0 ? 1.0 : r.height;
        final t = (top / h).clamp(0.0, 0.5);
        final b = (bottom / h).clamp(0.0, 0.5);
        // Kurva lembut: 0 -> .25 -> .7 -> 1 di sepanjang zona pemudaran.
        final stops = <double>[];
        final colors = <Color>[];
        void add(double st, double a) {
          stops.add(st);
          colors.add(Color.fromRGBO(0, 0, 0, a));
        }

        if (t > 0) {
          add(0, 0);
          add(t * 0.4, 0.25);
          add(t * 0.75, 0.7);
          add(t, 1);
        } else {
          add(0, 1);
        }
        if (b > 0) {
          add(1 - b, 1);
          add(1 - b * 0.75, 0.7);
          add(1 - b * 0.4, 0.25);
          add(1, 0);
        } else {
          add(1, 1);
        }
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: stops,
        ).createShader(r);
      },
      child: child,
    );
  }
}
