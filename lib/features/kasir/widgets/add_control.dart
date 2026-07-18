import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Tombol "+" yang berubah jadi lingkaran berisi jumlah saat produk ada di
/// keranjang. Tap menambah 1 (produk satuan tunggal) atau membuka modal
/// (produk multi-satuan). Dipakai di kartu/baris produk kasir DAN di baris
/// item keranjang (`cart_sheet.dart`) supaya gaya stepper konsisten di
/// seluruh alur kasir.
class AddControl extends StatefulWidget {
  const AddControl({
    super.key,
    required this.qty,
    required this.onTap,
    this.onMinus,
    this.size = 34,
  });

  final double qty;
  final VoidCallback onTap;
  final VoidCallback? onMinus;
  final double size;

  @override
  State<AddControl> createState() => _AddControlState();
}

// Item 13 — jeda anti-missclick: tap +/- yang datang terlalu rapat (jari
// sedikit geser lalu kena tombol sebelah) diabaikan, bukan diproses dobel.
const _kMisclickDebounce = Duration(milliseconds: 150);

// Feedback taktil: tombol membesar sesaat saat ditekan, mengecil lagi saat
// dilepas ATAU jari geser keluar area tombol (TapGestureRecognizer bawaan
// Flutter otomatis membatalkan tap-nya sendiri kalau pointer bergerak keluar
// batas toleransi geser saat masih ditekan, jadi onTapCancel juga menangani
// kasus "pindah ke area lain" tanpa perlu deteksi posisi manual).
const _kPressScale = 1.15;
const _kPressScaleDuration = Duration(milliseconds: 100);

class _AddControlState extends State<AddControl> {
  bool _blocked = false;
  Timer? _unblockTimer;
  bool _mainPressed = false;
  bool _minusPressed = false;

  @override
  void dispose() {
    _unblockTimer?.cancel();
    super.dispose();
  }

  bool _debounced() {
    if (_blocked) return true;
    _blocked = true;
    _unblockTimer?.cancel();
    _unblockTimer = Timer(_kMisclickDebounce, () => _blocked = false);
    return false;
  }

  void _handleTap() {
    if (_debounced()) return;
    widget.onTap();
  }

  void _handleMinus() {
    if (_debounced()) return;
    widget.onMinus?.call();
  }

  @override
  Widget build(BuildContext context) {
    final qty = widget.qty;
    final size = widget.size;
    final inCart = qty > 0;
    final label = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = inCart ? AppTheme.changeFg(isDark) : AppTheme.accent;
    final shadowColor = inCart
        ? AppTheme.changeFg(isDark).withOpacity(0.30)
        : const Color(0x33C96442);

    // Lingkaran utama (jumlah / "+") berukuran sama baik saat kosong maupun
    // saat sudah ada di keranjang, agar tidak "melompat" ukuran.
    final circleSize = size + 4;
    final mainCircle = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      onTapDown: (_) => setState(() => _mainPressed = true),
      onTapUp: (_) => setState(() => _mainPressed = false),
      onTapCancel: () => setState(() => _mainPressed = false),
      child: AnimatedScale(
        scale: _mainPressed ? _kPressScale : 1.0,
        duration: _kPressScaleDuration,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: shadowColor,
                  blurRadius: 6,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Center(
            child: inCart
                ? Padding(
                    // Label tetap bulat (bukan pill) — utk qty desimal (mis.
                    // "0.25", produk timbang) yang lebih panjang dari 1-2
                    // digit biasa, `FittedBox` menyusutkan font-nya secara
                    // proporsional supaya tetap muat dalam lingkaran, bukan
                    // terpotong/meluber.
                    padding: EdgeInsets.all(circleSize * 0.12),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: circleSize * 0.40,
                        ),
                      ),
                    ),
                  )
                : Icon(Icons.add_rounded,
                    color: Colors.white, size: circleSize * 0.6),
          ),
        ),
      ),
    );

    if (!inCart) return mainCircle;

    // Tombol minus: merah, sedikit lebih kecil dari lingkaran jumlah. Pakai
    // HitTestBehavior.opaque agar tap tidak "tembus" ke InkWell kartu produk.
    final minusSize = size - 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleMinus,
          onTapDown: (_) => setState(() => _minusPressed = true),
          onTapUp: (_) => setState(() => _minusPressed = false),
          onTapCancel: () => setState(() => _minusPressed = false),
          child: AnimatedScale(
            scale: _minusPressed ? _kPressScale : 1.0,
            duration: _kPressScaleDuration,
            curve: Curves.easeOut,
            child: Container(
              width: minusSize,
              height: minusSize,
              decoration: const BoxDecoration(
                color: Color(0xFFD64545),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(Icons.remove_rounded,
                    color: Colors.white, size: minusSize * 0.6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        mainCircle,
      ],
    );
  }
}
