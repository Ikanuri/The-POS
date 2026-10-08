import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Memutar animasi MASUK satu kali saat widget pertama dipasang: tinggi
/// membuka + memudar (easeOutQuint). Dipakai utk baris yang baru muncul di
/// daftar (mis. barang baru masuk keranjang). Bila [enabled] false atau
/// pengguna mematikan animasi, [child] langsung tampil penuh.
class EnterAnimation extends StatefulWidget {
  const EnterAnimation({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<EnterAnimation> createState() => _EnterAnimationState();
}

class _EnterAnimationState extends State<EnterAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: AppMotion.medium);
  late final CurvedAnimation _curved =
      CurvedAnimation(parent: _c, curve: AppMotion.easeOutQuint);
  bool _decided = false;

  /// Diputuskan SEKALI saat pertama dipasang. Bentuk pohon widget dijaga
  /// tetap sama sesudahnya (juga setelah animasi selesai) supaya state
  /// [child] — mis. baris keranjang — tidak hilang karena berpindah induk.
  bool _animated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    _animated = widget.enabled && !AppMotion.reduced(context);
    if (_animated) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_animated) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => SizeTransition(
        sizeFactor: _curved,
        axisAlignment: -1,
        child: FadeTransition(opacity: _curved, child: child),
      ),
    );
  }
}
