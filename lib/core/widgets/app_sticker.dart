import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_motion.dart';
import '../diagnostics/perf_diag.dart';

/// Stiker animasi Lottie (hasil `.tgs` yang sudah divalidasi -> JSON).
/// Berulang selama terlihat di layar (widget dilepas = animasi berhenti,
/// `TickerMode` yang menonaktifkan rute di belakang menghentikannya juga);
/// bila pengguna memilih "kurangi animasi" tampil DIAM di frame tengah.
/// Gagal dimuat/dirender = tidak menampilkan apa-apa (layar tetap normal).
class AppSticker extends StatefulWidget {
  const AppSticker({super.key, required this.json, this.size = 128});

  final String json;
  final double size;

  @override
  State<AppSticker> createState() => _AppStickerState();
}

class _AppStickerState extends State<AppSticker>
    with SingleTickerProviderStateMixin {
  // Dibuat di initState: saat stiker dimatikan (saklar diagnostik) `build`
  // tak menyentuh controller, dan pembuatan Ticker pertama saat dispose()
  // melempar "deactivated widget's ancestor".
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
  }
  late final List<int> _bytes = utf8.encode(widget.json);
  bool _reduced = false;
  LottieComposition? _comp;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = AppMotion.reduced(context);
    if (reduced != _reduced) {
      _reduced = reduced;
      _apply();
    }
  }

  void _apply() {
    final comp = _comp;
    if (comp == null) return;
    _c.duration = comp.duration;
    if (_reduced) {
      _c.stop();
      _c.value = 0.5; // frame tengah, seperti katalog HTML
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Diagnostik performa: stiker dimatikan (ruang tetap).
    if (!PerfDiag.s.stickers) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Lottie.memory(
        Uint8List.fromList(_bytes),
        controller: _c,
        fit: BoxFit.contain,
        onLoaded: (comp) {
          _comp = comp;
          _apply();
        },
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}
