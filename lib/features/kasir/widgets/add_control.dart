import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Tombol "+" yang berubah jadi lingkaran berisi jumlah saat produk ada di
/// keranjang. Tap menambah 1 (produk satuan tunggal) atau membuka modal
/// (produk multi-satuan). Dipakai di kartu/baris produk kasir DAN di baris
/// item keranjang (`cart_sheet.dart`) supaya gaya stepper konsisten di
/// seluruh alur kasir.
class AddControl extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: circleSize,
        height: circleSize,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: shadowColor, blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Center(
          child: inCart
              ? Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: circleSize * 0.40,
                  ),
                )
              : Icon(Icons.add_rounded,
                  color: Colors.white, size: circleSize * 0.6),
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
          onTap: onMinus,
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
        const SizedBox(width: 6),
        mainCircle,
      ],
    );
  }
}
