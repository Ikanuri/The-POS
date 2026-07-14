import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Badge lingkaran berisi jumlah item — gaya yang sama dipakai di cart bar
/// kasir (dulu private `_CartBar`), keranjang, dan struk in-app, supaya
/// representasi "jumlah barang" konsisten di seluruh alur kasir.
class ItemCountBadge extends StatelessWidget {
  const ItemCountBadge({
    super.key,
    required this.count,
    this.size = 34,
    this.elevated = false,
  });

  final int count;
  final double size;

  /// true untuk badge yang "mengambang" di atas widget lain (mis. menempel
  /// di sudut kartu) — tambah bayangan agar terkesan berada di depan.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.accent,
        shape: BoxShape.circle,
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          '$count',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.38,
          ),
        ),
      ),
    );
  }
}
