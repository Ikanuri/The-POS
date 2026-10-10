import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Slot yang menampilkan [child] dengan animasi MUNCUL (tinggi membuka dari
/// bawah + geser naik + memudar) dan HILANG (kebalikannya) saat [child]
/// berganti antara non-null <-> null. Selama animasi keluar, konten TERAKHIR
/// dipertahankan. Tinggi slot ikut animasi, jadi layar di atasnya (mis.
/// daftar yang memakai `extendBody`) tidak melonjak. "Kurangi animasi" ->
/// langsung tanpa animasi.
class AppSlideSlot extends StatefulWidget {
  const AppSlideSlot({super.key, required this.child});

  final Widget? child;

  @override
  State<AppSlideSlot> createState() => _AppSlideSlotState();
}

class _AppSlideSlotState extends State<AppSlideSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
    reverseDuration: AppMotion.fast + const Duration(milliseconds: 60),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
      parent: _c,
      curve: AppMotion.easeOutQuint,
      reverseCurve: AppMotion.easeIn);
  Widget? _last;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _last = widget.child;
    if (_last != null) _c.value = 1; // sudah ada saat pertama dipasang
    _c.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && widget.child == null && mounted) {
        setState(() => _last = null);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppMotion.reduced(context);
  }

  @override
  void didUpdateWidget(AppSlideSlot old) {
    super.didUpdateWidget(old);
    if (widget.child != null) {
      _last = widget.child;
      if (_reduced) {
        _c.value = 1;
      } else if (_c.status != AnimationStatus.forward &&
          _c.status != AnimationStatus.completed) {
        _c.forward();
      }
    } else if (old.child != null) {
      if (_reduced) {
        _c.value = 0;
        _last = null;
      } else {
        _c.reverse();
      }
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = _last;
    if (child == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _curve,
      child: child,
      builder: (context, c) => ClipRect(
        child: SizeTransition(
          sizeFactor: _curve,
          axisAlignment: 1.0,
          child: FadeTransition(
            opacity: _curve,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero)
                      .animate(_curve),
              child: c,
            ),
          ),
        ),
      ),
    );
  }
}
