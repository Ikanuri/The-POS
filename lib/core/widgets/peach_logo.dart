import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Logo "persik The POS" — GAMBAR YANG SAMA dengan logo header katalog HTML
/// (`#storeLogo` di `order_page_service.dart`): 4 garis (badan, daun,
/// lekukan, kilau) pada viewBox 512x512, garis tebal 22 (dari 512), ujung &
/// sambungan membulat, tanpa isi. Data jalur disalin PERSIS dari HTML (ada
/// test yang memastikan keduanya sama); hanya perintah `M`, `C`, `Z`
/// (absolut) yang dipakai sehingga cukup penguraian kecil di bawah — tanpa
/// paket SVG tambahan.
const List<String> kPeachPathData = [
  'M120.0 79.0 C107.2 84.2 93.0 92.5 82.0 100.0 C71.0 107.5 61.8 115.7 54.0 124.0 C46.2 132.3 40.3 140.3 35.0 150.0 C29.7 159.7 25.2 171.3 22.0 182.0 C18.8 192.7 17.0 201.5 16.0 214.0 C15.0 226.5 14.8 243.3 16.0 257.0 C17.2 270.7 19.5 283.3 23.0 296.0 C26.5 308.7 30.3 320.3 37.0 333.0 C43.7 345.7 53.2 359.8 63.0 372.0 C72.8 384.2 84.8 395.8 96.0 406.0 C107.2 416.2 117.7 424.3 130.0 433.0 C142.3 441.7 156.2 450.5 170.0 458.0 C183.8 465.5 199.0 472.5 213.0 478.0 C227.0 483.5 244.2 489.2 254.0 491.0 C263.8 492.8 264.0 491.2 272.0 489.0 C280.0 486.8 289.3 484.0 302.0 478.0 C314.7 472.0 332.2 463.0 348.0 453.0 C363.8 443.0 382.3 429.8 397.0 418.0 C411.7 406.2 424.7 394.5 436.0 382.0 C447.3 369.5 456.8 357.2 465.0 343.0 C473.2 328.8 480.2 312.0 485.0 297.0 C489.8 282.0 492.5 267.7 494.0 253.0 C495.5 238.3 496.2 224.3 494.0 209.0 C491.8 193.7 486.3 174.3 481.0 161.0 C475.7 147.7 470.0 139.2 462.0 129.0 C454.0 118.8 442.2 107.5 433.0 100.0 C423.8 92.5 416.7 88.5 407.0 84.0 C397.3 79.5 384.5 75.2 375.0 73.0 C365.5 70.8 358.5 70.8 350.0 71.0 C341.5 71.2 331.5 72.5 324.0 74.0 C316.5 75.5 313.3 76.0 305.0 80.0 C296.7 84.0 284.8 98.0 274.0 98.0 C263.2 98.0 252.7 84.8 240.0 80.0 C227.3 75.2 211.5 70.8 198.0 69.0 C184.5 67.2 172.0 67.3 159.0 69.0 C146.0 70.7 132.8 73.8 120.0 79.0Z',
  'M466.0 28.0 C466.0 25.2 464.8 25.0 463.0 24.0 C461.2 23.0 464.3 22.5 455.0 22.0 C445.7 21.5 421.7 20.7 407.0 21.0 C392.3 21.3 378.7 22.5 367.0 24.0 C355.3 25.5 345.8 27.5 337.0 30.0 C328.2 32.5 320.2 36.0 314.0 39.0 C307.8 42.0 305.2 43.7 300.0 48.0 C294.8 52.3 288.3 58.3 283.0 65.0 C277.7 71.7 273.7 87.8 268.0 88.0 C262.3 88.2 254.8 71.8 249.0 66.0 C243.2 60.2 240.7 57.8 233.0 53.0 C225.3 48.2 212.3 41.0 203.0 37.0 C193.7 33.0 189.0 31.3 177.0 29.0 C165.0 26.7 146.2 24.0 131.0 23.0 C115.8 22.0 97.3 22.2 86.0 23.0 C74.7 23.8 66.8 25.7 63.0 28.0 C59.2 30.3 60.2 31.2 63.0 37.0 C65.8 42.8 72.8 55.2 80.0 63.0 C87.2 70.8 95.7 82.7 106.0 84.0 C116.3 85.3 128.3 73.8 142.0 71.0 C155.7 68.2 176.0 67.0 188.0 67.0 C200.0 67.0 205.3 69.0 214.0 71.0 C222.7 73.0 230.7 74.7 240.0 79.0 C249.3 83.3 264.3 94.0 270.0 97.0 C275.7 100.0 267.3 100.3 274.0 97.0 C280.7 93.7 297.3 81.5 310.0 77.0 C322.7 72.5 337.2 70.3 350.0 70.0 C362.8 69.7 375.7 72.0 387.0 75.0 C398.3 78.0 406.7 91.5 418.0 88.0 C429.3 84.5 447.5 61.8 455.0 54.0 C462.5 46.2 461.2 45.3 463.0 41.0 C464.8 36.7 466.0 30.8 466.0 28.0Z',
  'M281 101 C352 128 392 214 376 306 C363 386 322 446 266 486',
  'M92 146 C104 120 128 104 154 98',
];

const double _kViewBox = 512;
const double _kStroke = 22;

/// Mengubah data jalur SVG yang hanya berisi `M`/`C`/`Z` absolut menjadi [Path]
/// (koordinat di ruang 512x512).
Path parsePeachPath(String d) {
  final path = Path();
  final tokens =
      RegExp(r'[MCZ]|-?\d+(?:\.\d+)?').allMatches(d).map((m) => m[0]!);
  final it = tokens.iterator;
  final nums = <double>[];
  String? cmd;
  void flush() {
    if (cmd == 'M' && nums.length >= 2) {
      path.moveTo(nums[0], nums[1]);
    } else if (cmd == 'C') {
      for (var i = 0; i + 5 < nums.length; i += 6) {
        path.cubicTo(nums[i], nums[i + 1], nums[i + 2], nums[i + 3],
            nums[i + 4], nums[i + 5]);
      }
    }
    nums.clear();
  }

  while (it.moveNext()) {
    final t = it.current;
    if (t == 'M' || t == 'C' || t == 'Z') {
      flush();
      cmd = t;
      if (t == 'Z') path.close();
    } else {
      nums.add(double.parse(t));
    }
  }
  flush();
  return path;
}

final List<Path> _peachPaths = [
  for (final d in kPeachPathData) parsePeachPath(d)
];

/// Persik putih (garis) berukuran [size] x [size].
class PeachLogo extends StatelessWidget {
  const PeachLogo({super.key, required this.size, this.color = Colors.white});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _PeachPainter(color),
      );
}

class _PeachPainter extends CustomPainter {
  _PeachPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _kViewBox;
    canvas.save();
    canvas.scale(k, k);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..color = color;
    for (final p in _peachPaths) {
      canvas.drawPath(p, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PeachPainter old) => old.color != color;
}

/// Kotak logo seperti `.tb-logo` di katalog HTML: kotak aksen membulat dengan
/// persik putih berukuran 72% dari kotak. [shadows] opsional (mis. bayangan
/// aksen yang bisa dimatikan saklar diagnostik).
class PeachLogoBadge extends StatelessWidget {
  const PeachLogoBadge({
    super.key,
    this.size = 34,
    this.shadows = const [],
  });

  final double size;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.accent,
          // Rasio radius katalog HTML: 12 px pada kotak 35 px.
          borderRadius: BorderRadius.circular(size * 12 / 35),
          boxShadow: shadows,
        ),
        child: PeachLogo(size: size * 0.72),
      );
}
