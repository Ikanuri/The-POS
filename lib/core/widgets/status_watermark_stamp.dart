import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Watermark "stempel" Lunas/Tempo — dirender SAMAR (opacity rendah) di
/// BELAKANG baris item struk (bukan elemen mengambang di sudut kartu),
/// supaya berapa pun panjang daftar itemnya, nama & harga produk selalu di
/// lapisan depan dan tidak pernah tertutup. Desain final disepakati user
/// lewat beberapa putaran mockup — lihat PLAN.md Item 29.
class StatusWatermarkStamp extends StatelessWidget {
  const StatusWatermarkStamp({
    super.key,
    required this.label,
    required this.serial,
    required this.color,
  });

  /// "LUNAS" atau "TEMPO".
  final String label;

  /// Nomor nota (`tx.localId`), ditampilkan sbg baris kedua di dalam stempel.
  final String serial;

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.22,
        child: Transform.rotate(
          angle: -11 * math.pi / 180,
          child: CustomPaint(
            painter: _StampBorderPainter(color: color),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      letterSpacing: 2,
                    ),
                  ),
                  Container(
                    width: 70,
                    height: 1.4,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: color,
                  ),
                  Text(
                    serial,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Double border bersudut tumpul + tepi "kasar/bertinta" (dash acak dgn
/// seed tetap — deterministic, bukan flicker tiap rebuild) meniru tekstur
/// stempel karet yg sudah aus, persis referensi visual yg diberikan user.
class _StampBorderPainter extends CustomPainter {
  _StampBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final outer =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    final innerRect = Rect.fromLTWH(6, 6, size.width - 12, size.height - 12);
    final inner = RRect.fromRectAndRadius(innerRect, const Radius.circular(7));

    final outerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2;
    final innerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    _drawDistressedRRect(canvas, outer, outerPaint, seed: 7);
    _drawDistressedRRect(canvas, inner, innerPaint, seed: 19);
  }

  void _drawDistressedRRect(Canvas canvas, RRect rrect, Paint paint,
      {required int seed}) {
    final path = Path()..addRRect(rrect);
    final rnd = math.Random(seed);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final dashLen = 3.0 + rnd.nextDouble() * 6;
        final gapLen = rnd.nextDouble() < 0.15 ? rnd.nextDouble() * 3 : 0.4;
        final end = math.min(distance + dashLen, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StampBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
