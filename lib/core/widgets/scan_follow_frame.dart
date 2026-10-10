import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

/// Bingkai pemindai yang MENGIKUTI kode — porting perilaku
/// `CameraScanActivity` Telegram (lihat docs/ANALISIS-QR-SCANNER-TELEGRAM.md):
///
/// * kotak tengah (sisi = min(lebar,tinggi)/1,5) saat belum ada kode;
/// * setiap hasil deteksi: bingkai berpindah ke kotak pembatas 4 sudut kode
///   (+ padding 25x15) dengan interpolasi LINEAR 75 ms dari posisi yang
///   sedang tampil;
/// * kotak tengah <-> kotak kode dicampur oleh pegas `useRecognized`
///   (damping 1,0 / stiffness 500);
/// * saat kamera siap, bingkai muncul membesar (0,5 -> 1) dgn pegas
///   (damping 0,8 / stiffness 250) — sudut menyusut dari sisi kotak penuh ke
///   kaki 20dp, lebar garis 0 -> 4dp;
/// * redup di luar bingkai 0,5 -> 0,75 saat terkunci (300 ms);
/// * kode hilang > ~4 sampel (di sini ~450 ms tanpa laporan) = kembali ke
///   kotak tengah.

/// Memetakan titik di ruang gambar analisis [image] ke ruang tampilan [view]
/// untuk preview ber-`BoxFit.cover` (atau `contain`).
Offset mapImagePointToView(Offset p, Size image, Size view,
    {BoxFit fit = BoxFit.cover}) {
  if (image.isEmpty || view.isEmpty) return Offset.zero;
  final sx = view.width / image.width;
  final sy = view.height / image.height;
  final s = fit == BoxFit.contain ? math.min(sx, sy) : math.max(sx, sy);
  final ox = (view.width - image.width * s) / 2;
  final oy = (view.height - image.height * s) / 2;
  return Offset(p.dx * s + ox, p.dy * s + oy);
}

/// Kotak pembatas titik-titik (ruang tampilan), diberi padding [padX]/[padY].
Rect boundsOf(List<Offset> pts, {double padX = 0, double padY = 0}) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final p in pts) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  return Rect.fromLTRB(minX - padX, minY - padY, maxX + padX, maxY + padY);
}

/// Kendali bingkai: dipanggil dari `onDetect` pemindai.
class ScanFollowController {
  _ScanFollowOverlayState? _state;

  /// Laporkan satu deteksi. [corners] = titik sudut kode di ruang gambar
  /// analisis berukuran [imageSize]; kosong = kode terbaca tanpa posisi.
  void report(List<Offset> corners, Size imageSize) =>
      _state?._report(corners, imageSize);

  /// Lepas kunci (kembali ke kotak tengah) — mis. setelah satu barang
  /// diproses pada mode scan beruntun.
  void release() => _state?._setRecognized(false);

  /// Lama tanpa laporan sebelum bingkai kembali ke tengah (Telegram ~450 ms).
  /// Mode kunci target memperpanjangnya agar bingkai tidak mantul ke tengah
  /// selama kode terkunci masih ditahan.
  Duration lostAfter = const Duration(milliseconds: 450);

  /// true = lama interpolasi mengikuti jarak antar-laporan (75-280 ms) supaya
  /// gerak mulus dan tidak "berhenti-jalan" saat deteksi hanya ~4x/detik.
  bool smooth = false;

  /// Tahan bingkai di posisi terakhir (kode terkunci sedang tak terbaca):
  /// hanya memperpanjang umur kunci tampilan, tanpa menggeser kotak.
  void hold() => _state?._hold();

  /// Mulai animasi muncul (dipanggil saat kamera siap).
  void appear() => _state?._appear();

  bool get recognized => _state?._recognized ?? false;

  @visibleForTesting
  Rect? get debugBounds => _state?._currentBounds();
  @visibleForTesting
  double get debugUseRecognized => _state?._useRecognized.value ?? 0;
  @visibleForTesting
  double get debugAppearing => _state?._appearing.value ?? 0;
}

class ScanFollowOverlay extends StatefulWidget {
  const ScanFollowOverlay({
    super.key,
    required this.controller,
    this.fit = BoxFit.cover,
  });

  final ScanFollowController controller;
  final BoxFit fit;

  @override
  State<ScanFollowOverlay> createState() => _ScanFollowOverlayState();
}

class _ScanFollowOverlayState extends State<ScanFollowOverlay>
    with TickerProviderStateMixin {
  static const _baseBoundsMs = 75;
  int _boundsMs = _baseBoundsMs;
  final Stopwatch _wall = Stopwatch()..start();
  int _lastReportMs = -1;

  // Pegas (padanan SpringForce Android, massa 1).
  static final _appearSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 250, ratio: 0.8);
  static final _lockSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 500, ratio: 1.0);

  // Jam bingkai: Ticker yang hanya berjalan selama interpolasi 75 ms aktif.
  // Waktu-dinding (bukan "restart animasi") seperti `elapsedRealtime` di
  // Telegram: laporan yang datang lebih rapat dari frame TIDAK mengulang
  // dari nol sehingga gerak tidak tersendat.
  late final Ticker _clock = createTicker(_onTick);
  final ValueNotifier<int> _tick = ValueNotifier(0);
  Duration _now = Duration.zero;
  Duration _lastUpdate = Duration.zero;
  late final AnimationController _appearing = AnimationController.unbounded(
      vsync: this, value: 0);
  late final AnimationController _useRecognized =
      AnimationController.unbounded(vsync: this, value: 0);
  late final AnimationController _recognizedT = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));

  Size _view = Size.zero;
  Rect _from = Rect.zero;
  Rect _to = Rect.zero;
  bool _hasBounds = false;
  bool _recognized = false;
  Timer? _lostTimer;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(ScanFollowOverlay old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._state = null;
      widget.controller._state = this;
    }
  }

  @override
  void dispose() {
    _lostTimer?.cancel();
    if (widget.controller._state == this) widget.controller._state = null;
    _clock.dispose();
    _tick.dispose();
    _appearing.dispose();
    _useRecognized.dispose();
    _recognizedT.dispose();
    super.dispose();
  }

  // ── Geometri ──────────────────────────────────────────────────────────
  Rect get _normal {
    final side = math.min(_view.width, _view.height) / 1.5;
    return Rect.fromLTWH((_view.width - side) / 2, (_view.height - side) / 2,
        side, side);
  }

  double get _boundsT => ((_now - _lastUpdate).inMicroseconds /
          (_boundsMs * 1000))
      .clamp(0.0, 1.0);

  Rect _recognizedBounds() =>
      Rect.lerp(_from, _to, _boundsT) ?? _to; // linear 75 ms

  void _onTick(Duration e) {
    _now = e;
    _tick.value++;
    if (_hasBounds && e - _lastUpdate > Duration(milliseconds: _boundsMs)) {
      _clock.stop();
    }
  }

  Rect _currentBounds() {
    if (_view.isEmpty) return Rect.zero;
    final rec = _hasBounds ? _recognizedBounds() : _normal;
    final u = _useRecognized.value.clamp(0.0, 1.0);
    return u < 1 ? (Rect.lerp(_normal, rec, u) ?? rec) : rec;
  }

  // ── Masukan ───────────────────────────────────────────────────────────
  void _appear() {
    _appearing
      ..stop()
      ..value = 0;
    _appearing.animateWith(SpringSimulation(_appearSpring, 0, 1, 0));
  }

  void _setRecognized(bool v) {
    if (_recognized == v) return;
    _recognized = v;
    // 300 ms CubicBezier(.25,.1,.25,1) — gelapkan latar saat terkunci.
    _recognizedT.animateTo(v ? 1 : 0,
        curve: const Cubic(0.25, 0.1, 0.25, 1));
    // Pegas campuran kotak tengah <-> kotak kode.
    _useRecognized.animateWith(
        SpringSimulation(_lockSpring, _useRecognized.value, v ? 1 : 0, 0));
  }

  void _armLost() {
    _lostTimer?.cancel();
    _lostTimer = Timer(widget.controller.lostAfter, () {
      if (mounted) _setRecognized(false);
    });
  }

  void _hold() {
    if (!mounted || !_recognized) return;
    _armLost();
  }

  void _report(List<Offset> corners, Size imageSize) {
    if (!mounted || _view.isEmpty) return;
    _armLost();
    _setRecognized(true);
    final nowMs = _wall.elapsedMilliseconds;
    if (widget.controller.smooth && _lastReportMs >= 0) {
      _boundsMs = (nowMs - _lastReportMs).clamp(_baseBoundsMs, 280);
    } else {
      _boundsMs = _baseBoundsMs;
    }
    _lastReportMs = nowMs;
    if (corners.isEmpty || imageSize.isEmpty) return; // terbaca tanpa posisi
    final pts = [
      for (final c in corners)
        mapImagePointToView(c, imageSize, _view, fit: widget.fit)
    ];
    // Padding 25 x 15 dp (nilai Telegram).
    final nb = boundsOf(pts, padX: 25, padY: 15);
    if (!_clock.isActive) {
      _clock.start();
      _now = Duration.zero;
      _lastUpdate = Duration.zero;
    }
    if (!_hasBounds) {
      _hasBounds = true;
      _from = nb;
      _to = nb;
    } else {
      // Mulai dari posisi yang SEDANG tampil lalu menuju target baru.
      _from = _recognizedBounds();
      _to = nb;
    }
    _lastUpdate = _now;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _view = Size(c.maxWidth, c.maxHeight);
      return RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _FramePainter(
            listenable: Listenable.merge(
                [_tick, _appearing, _useRecognized, _recognizedT]),
            bounds: _currentBounds,
            appearing: () => _appearing.value,
            recognizedT: () => _recognizedT.value,
          ),
        ),
      );
    });
  }
}

/// Pelukis bingkai — padanan `drawChild` Telegram.
class _FramePainter extends CustomPainter {
  _FramePainter({
    required Listenable listenable,
    required this.bounds,
    required this.appearing,
    required this.recognizedT,
  }) : super(repaint: listenable);

  final Rect Function() bounds;
  final double Function() appearing;
  final double Function() recognizedT;

  static double _lerp(num a, num b, num t) => (a + (b - a) * t).toDouble();

  Rect _around(double x, double y, double r) =>
      Rect.fromLTRB(x - r, y - r, x + r, y + r);

  static double _rad(double deg) => deg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final b = bounds();
    if (b.isEmpty && b.width == 0) return;
    final app = appearing();
    final backShadowAlpha = 0.5 + recognizedT() * 0.25;

    var sx = b.width * (0.5 + app * 0.5);
    var sy = b.height * (0.5 + app * 0.5);
    final cx = b.center.dx, cy = b.center.dy;
    final x = cx - sx / 2, y = cy - sy / 2;

    final a = math.min(1.0, math.max(0.0, app));
    // Redup di luar bingkai.
    final dim = Paint()
      ..color = Colors.black
          .withOpacity((1 - (1 - backShadowAlpha) * a).clamp(0.0, 1.0));
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, y), dim);
    canvas.drawRect(Rect.fromLTRB(0, y + sy, size.width, size.height), dim);
    canvas.drawRect(Rect.fromLTRB(0, y, x, y + sy), dim);
    canvas.drawRect(Rect.fromLTRB(x + sx, y, size.width, y + sy), dim);
    // Isi dalam memudar saat bingkai muncul.
    canvas.drawRect(
        Rect.fromLTWH(x, y, sx, sy),
        Paint()
          ..color =
              Colors.black.withOpacity(math.max(0.0, 1 - app).clamp(0.0, 1.0)));

    final lw = _lerp(0, 4, math.min(1, app * 20));
    final half = lw / 2;
    final ll = _lerp(math.min(sx, sy), 20, math.min(1.2, math.pow(app, 1.8)));
    final corner = Paint()
      ..color = Colors.white.withOpacity(math.min(1.0, math.max(0.0, app)))
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path = Path();
    void arc(Rect r, double start, double sweep) =>
        path.arcTo(r, _rad(start), _rad(sweep), false);

    // Kiri-atas.
    path.reset();
    arc(_around(x, y + ll, half), 0, 180);
    arc(_around(x + lw * 1.5, y + lw * 1.5, lw * 2), 180, 90);
    arc(_around(x + ll, y, half), 270, 180);
    path.lineTo(x + half, y + half);
    arc(_around(x + lw * 1.5, y + lw * 1.5, lw), 270, -90);
    path.close();
    canvas.drawPath(path, corner);

    // Kanan-atas.
    path.reset();
    arc(_around(x + sx, y + ll, half), 180, -180);
    arc(_around(x + sx - lw * 1.5, y + lw * 1.5, lw * 2), 0, -90);
    arc(_around(x + sx - ll, y, half), 270, -180);
    arc(_around(x + sx - lw * 1.5, y + lw * 1.5, lw), 270, 90);
    path.close();
    canvas.drawPath(path, corner);

    // Kiri-bawah.
    path.reset();
    arc(_around(x, y + sy - ll, half), 0, -180);
    arc(_around(x + lw * 1.5, y + sy - lw * 1.5, lw * 2), 180, -90);
    arc(_around(x + ll, y + sy, half), 90, -180);
    arc(_around(x + lw * 1.5, y + sy - lw * 1.5, lw), 90, 90);
    path.close();
    canvas.drawPath(path, corner);

    // Kanan-bawah.
    path.reset();
    arc(_around(x + sx, y + sy - ll, half), 180, 180);
    arc(_around(x + sx - lw * 1.5, y + sy - lw * 1.5, lw * 2), 0, 90);
    arc(_around(x + sx - ll, y + sy, half), 90, 180);
    arc(_around(x + sx - lw * 1.5, y + sy - lw * 1.5, lw), 90, -90);
    path.close();
    canvas.drawPath(path, corner);
  }

  @override
  bool shouldRepaint(_FramePainter old) => true;
}
