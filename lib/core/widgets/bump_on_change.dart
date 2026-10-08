import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Membungkus [child] dan memberi "denyut" skala singkat (1 -> [peak] -> 1,
/// easeOutBack) setiap kali [value] berubah — umpan balik halus untuk angka
/// (jumlah, badge) tanpa menduplikasi widget seperti `AnimatedSwitcher`
/// (hanya satu [child] di pohon, aman utk `find.text` di test). Nilai awal
/// tidak berdenyut. Animasi dimatikan bila pengguna memilih "kurangi animasi".
class BumpOnChange extends StatefulWidget {
  const BumpOnChange({
    super.key,
    required this.value,
    required this.child,
    this.peak = 1.16,
  });

  /// Nilai yang dipantau (dibandingkan dgn `==`).
  final Object? value;
  final Widget child;
  final double peak;

  @override
  State<BumpOnChange> createState() => _BumpOnChangeState();
}

class _BumpOnChangeState extends State<BumpOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: AppMotion.base);

  @override
  void didUpdateWidget(BumpOnChange old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !AppMotion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // 0..1 -> naik ke peak di separuh pertama, turun ke 1 di separuh akhir.
        final t = _c.value;
        final k = t < 0.5
            ? AppMotion.easeOut.transform(t * 2)
            : 1 - AppMotion.easeOut.transform((t - 0.5) * 2);
        final scale = 1 + (widget.peak - 1) * (_c.isAnimating ? k : 0);
        return Transform.scale(scale: scale, child: child);
      },
    );
  }
}
