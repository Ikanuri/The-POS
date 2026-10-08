import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Umpan balik sentuh "memantul" ala Telegram: saat ditekan [child] mengecil
/// ke `1 - depth` dalam 80 ms; saat dilepas kembali dalam 350 ms dengan
/// sedikit melewati ukuran asli (overshoot) lalu mendarat.
///
/// Murni PAINT (Transform.scale) dan memakai `Listener` — tidak ikut arena
/// gestur, jadi tap/long-press/geser anak tetap bekerja persis seperti biasa.
/// [depth]: 0,02-0,05 utk baris/ikon/chip, 0,1 hanya utk tombol besar.
/// Dimatikan bila pengguna memilih "kurangi animasi".
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.depth = 0.03,
    this.enabled = true,
  });

  final Widget child;
  final double depth;
  final bool enabled;

  /// Durasi (konstanta Telegram).
  static const pressDuration = Duration(milliseconds: 80);
  static const releaseDuration = Duration(milliseconds: 350);

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: PressScale.pressDuration, // maju = ditekan (cepat)
    reverseDuration: PressScale.releaseDuration, // mundur = dilepas (memantul)
  );
  // 0 = normal, 1 = tertekan penuh. Naik cepat (80 ms), turun lambat+memantul.
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
    reverseCurve: AppMotion.easeOutBack.flipped,
  );
  int _pointers = 0;

  bool get _active => widget.enabled && !AppMotion.reduced(context);

  void _down() {
    _pointers++;
    if (!_active) return;
    _c.forward();
  }

  void _up() {
    if (_pointers > 0) _pointers--;
    // Termasuk saat tap lebih cepat dari satu frame (value masih 0 tapi
    // status sudah `forward`) — kalau tidak, tombol tersangkut menciut.
    if (_pointers == 0 && _c.status != AnimationStatus.dismissed) _c.reverse();
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: AnimatedBuilder(
        animation: _curve,
        child: widget.child,
        builder: (context, child) {
          final s = 1 - widget.depth * _curve.value;
          return s == 1 ? child! : Transform.scale(scale: s, child: child);
        },
      ),
    );
  }
}
