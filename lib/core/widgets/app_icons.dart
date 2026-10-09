import 'package:flutter/material.dart';

/// Ikon navigasi bawah buatan sendiri (bukan Material Icons bawaan Flutter):
/// garis bulat 1,8 dp pada kisi 24, varian [filled] = isi duotone lembut.
enum AppIconKind { ringkasan, kasir, produk, pelanggan, laporan, pengaturan }

class AppIcon extends StatelessWidget {
  const AppIcon(this.kind,
      {super.key, this.size = 24, required this.color, this.filled = false});

  final AppIconKind kind;
  final double size;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _IconPainter(kind, color, filled)),
      );
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.kind, this.color, this.filled);
  final AppIconKind kind;
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color.withOpacity(0.24)
      ..style = PaintingStyle.fill;

    void shape(Path p) {
      if (filled) canvas.drawPath(p, fill);
      canvas.drawPath(p, stroke);
    }

    RRect rr(double l, double t, double w, double h, double r) =>
        RRect.fromRectAndRadius(
            Rect.fromLTWH(l, t, w, h), Radius.circular(r));

    switch (kind) {
      case AppIconKind.ringkasan:
        // Bento: empat petak berbeda ukuran.
        for (final r in [
          rr(3.5, 3.5, 7.5, 10, 2.4),
          rr(13, 3.5, 7.5, 6, 2.4),
          rr(3.5, 15.5, 7.5, 5, 2.4),
          rr(13, 11.5, 7.5, 9, 2.4),
        ]) {
          shape(Path()..addRRect(r));
        }
      case AppIconKind.kasir:
        // Struk bergerigi + dua baris.
        final p = Path()
          ..moveTo(6.5, 3.5)
          ..lineTo(17.5, 3.5)
          ..arcToPoint(const Offset(19, 5),
              radius: const Radius.circular(1.5))
          ..lineTo(19, 20.5)
          ..lineTo(16.75, 19)
          ..lineTo(14.5, 20.5)
          ..lineTo(12.25, 19)
          ..lineTo(10, 20.5)
          ..lineTo(7.75, 19)
          ..lineTo(5, 20.5)
          ..lineTo(5, 5)
          ..arcToPoint(const Offset(6.5, 3.5),
              radius: const Radius.circular(1.5))
          ..close();
        shape(p);
        canvas.drawLine(const Offset(8.5, 9), const Offset(15.5, 9), stroke);
        canvas.drawLine(
            const Offset(8.5, 12.8), const Offset(13.2, 12.8), stroke);
      case AppIconKind.produk:
        // Kotak isometrik.
        final p = Path()
          ..moveTo(12, 3)
          ..lineTo(20, 7.5)
          ..lineTo(20, 16.5)
          ..lineTo(12, 21)
          ..lineTo(4, 16.5)
          ..lineTo(4, 7.5)
          ..close();
        shape(p);
        canvas.drawPath(
            Path()
              ..moveTo(4, 7.5)
              ..lineTo(12, 12)
              ..lineTo(20, 7.5)
              ..moveTo(12, 12)
              ..lineTo(12, 21),
            stroke);
      case AppIconKind.pelanggan:
        // Dua orang: depan besar, belakang kecil.
        final back = Path()
          ..addOval(Rect.fromCircle(center: const Offset(16.8, 8.6), radius: 2.6));
        shape(back);
        canvas.drawPath(
            Path()
              ..moveTo(16.5, 13.6)
              ..cubicTo(19.2, 13.4, 21, 15.3, 21, 18),
            stroke);
        final front = Path()
          ..addOval(Rect.fromCircle(center: const Offset(9.4, 8), radius: 3.4));
        shape(front);
        final body = Path()
          ..moveTo(3, 20)
          ..cubicTo(3, 15.6, 5.6, 13.8, 9.4, 13.8)
          ..cubicTo(13.2, 13.8, 15.8, 15.6, 15.8, 20)
          ..close();
        shape(body);
      case AppIconKind.laporan:
        // Diagram lingkar dengan irisan terpisah.
        final body = Path()
          ..moveTo(10.5, 13.5)
          ..lineTo(10.5, 6)
          ..arcToPoint(const Offset(18, 13.5),
              radius: const Radius.circular(7.5),
              largeArc: true,
              clockwise: false)
          ..close();
        shape(body);
        final slice = Path()
          ..moveTo(13.5, 10.5)
          ..lineTo(13.5, 3.5)
          ..arcToPoint(const Offset(20.5, 10.5),
              radius: const Radius.circular(7))
          ..close();
        shape(slice);
      case AppIconKind.pengaturan:
        // Tiga penggeser: garis berjeda di sekitar kenop.
        const rows = [(7.0, 15.0), (12.0, 8.5), (17.0, 13.0)];
        for (final e in rows) {
          canvas.drawLine(Offset(4, e.$1), Offset(e.$2 - 3.6, e.$1), stroke);
          canvas.drawLine(Offset(e.$2 + 3.6, e.$1), Offset(20, e.$1), stroke);
          final c = Offset(e.$2, e.$1);
          if (filled) {
            canvas.drawCircle(c, 2.5, fill);
          }
          canvas.drawCircle(c, 2.5, stroke);
        }
    }
  }

  @override
  bool shouldRepaint(_IconPainter o) =>
      o.kind != kind || o.color != color || o.filled != filled;
}
