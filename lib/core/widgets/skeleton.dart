import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Kerangka memuat (skeleton) ala Telegram `FlickerLoadingView`: bentuk abu
/// bersudut membulat dgn kilau lembut yang bergerak dari kiri ke kanan
/// (1,2 dtk berulang) — menggantikan spinner/"…" supaya layar terasa sudah
/// "berbentuk" sebelum data tiba. Statis bila pengguna memilih "kurangi
/// animasi". Gerak kilau hanya paint (gradient shader), tidak mengubah tata letak.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 4,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  static const period = Duration(milliseconds: 1200);

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: SkeletonBox.period);
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (!AppMotion.reduced(context)) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.outlineVariant.withOpacity(0.35);
    final glint = cs.outlineVariant.withOpacity(0.7);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Kilau menyapu dari -1 ke 2 lebar kotak.
        final x = -1 + 3 * Curves.easeInOut.transform(_c.value);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius:
                widget.circle ? null : BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(x - 0.6, 0),
              end: Alignment(x + 0.6, 0),
              colors: [base, glint, base],
            ),
          ),
        );
      },
    );
  }
}

/// Satu baris kerangka bergaya baris produk kasir: kotak 42 px + dua bar teks
/// + lingkaran kecil di kanan. Dipakai [SkeletonList].
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key, this.nameFactor = 0.55});

  /// Lebar bar nama relatif thd ruang tersedia (variasi antar baris).
  final double nameFactor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          const SkeletonBox(width: 42, height: 42, radius: 11),
          const SizedBox(width: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: c.maxWidth * nameFactor, height: 12),
                  const SizedBox(height: 8),
                  SkeletonBox(width: c.maxWidth * 0.3, height: 10),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          const SkeletonBox(width: 34, height: 34, circle: true),
        ],
      ),
    );
  }
}

/// Daftar kerangka (tidak bisa digulir, tidak bisa disentuh) utk keadaan memuat.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 8});

  final int count;

  static const _factors = [0.55, 0.4, 0.65, 0.5, 0.35, 0.6, 0.45, 0.52];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Memuat',
      child: IgnorePointer(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          itemBuilder: (_, i) =>
              SkeletonRow(nameFactor: _factors[i % _factors.length]),
        ),
      ),
    );
  }
}
