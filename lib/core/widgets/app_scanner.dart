import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../providers/scan_frame_provider.dart';
import 'scan_follow_frame.dart';
import 'scan_target_lock.dart';

/// Pembungkus `MobileScanner` untuk SEMUA pemindai app. Bila "Bingkai
/// pemindai ala Telegram" (eksperimental) aktif, menumpuk [ScanFollowOverlay]
/// yang mengikuti kode; bila mati, perilaku persis `MobileScanner` biasa +
/// [legacyOverlay] milik pemanggil.
///
/// * [lockDelay] > 0 (mode satu-tembak, mis. QR sync): hasil diteruskan ke
///   [onDetect] SETELAH bingkai terkunci selama [lockDelay] (Telegram: 1 dtk)
///   — jadi pengguna melihat bingkai menempel di kode sebelum layar menutup.
/// * [releaseAfter] (mode beruntun, mis. Kasir): setelah hasil diteruskan,
///   bingkai dilepas kembali ke tengah setelah jeda ini (Telegram
///   `TYPE_QR_WEB_BOT`: 500 ms) lalu mengikuti kode berikutnya.
class AppScanner extends ConsumerStatefulWidget {
  const AppScanner({
    super.key,
    this.controller,
    required this.onDetect,
    this.lockDelay = Duration.zero,
    this.releaseAfter,
    this.legacyOverlay,
    this.fit = BoxFit.cover,
    this.accept,
    this.errorBuilder,
  });

  final MobileScannerController? controller;
  final void Function(BarcodeCapture capture) onDetect;
  final Duration lockDelay;
  final Duration? releaseAfter;
  final Widget? legacyOverlay;
  final BoxFit fit;

  /// Saring kode yang boleh DIIKUTI bingkai & dikunci (mis. hanya QR sync
  /// yang valid) — kode lain diabaikan bingkai, tetap diteruskan apa adanya
  /// bila [lockDelay] nol.
  final bool Function(Barcode barcode)? accept;

  final Widget Function(BuildContext, MobileScannerException, Widget?)?
      errorBuilder;

  /// Pilih barcode yang diikuti bingkai: yang bertitik sudut & paling dekat
  /// ke tengah gambar (bidikan banyak barcode sekaligus).
  static Barcode? pickBarcode(List<Barcode> list, Size image) {
    Barcode? best;
    var bestD = double.infinity;
    final center = Offset(image.width / 2, image.height / 2);
    for (final b in list) {
      if ((b.rawValue ?? '').isEmpty) continue;
      if (b.corners.isEmpty) {
        best ??= b;
        continue;
      }
      final r = _bbox(b.corners);
      final d = (r.center - center).distance;
      if (d < bestD) {
        bestD = d;
        best = b;
      }
    }
    return best;
  }

  static Rect _bbox(List<Offset> pts) => boundsOf(pts);

  @override
  ConsumerState<AppScanner> createState() => _AppScannerState();
}

class _AppScannerState extends ConsumerState<AppScanner> {
  late final MobileScannerController _ctrl;
  late final bool _ownsCtrl;
  final _follow = ScanFollowController();
  bool _appeared = false;
  Timer? _lockTimer;
  Timer? _releaseTimer;
  BarcodeCapture? _latest;
  final _lock = ScanTargetLock(release: Duration.zero);
  final _rect = ScanRectFilter();
  String? _rectFor;

  @override
  void initState() {
    super.initState();
    _ownsCtrl = widget.controller == null;
    _ctrl = widget.controller ?? MobileScannerController();
    _ctrl.addListener(_onCamera);
  }

  void _onCamera() {
    final v = _ctrl.value;
    if (!_appeared && v.isRunning && !v.size.isEmpty) {
      _appeared = true;
      _follow.appear();
    }
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _releaseTimer?.cancel();
    _ctrl.removeListener(_onCamera);
    if (_ownsCtrl) _ctrl.dispose();
    super.dispose();
  }

  Size _imageSize(BarcodeCapture cap) =>
      _ctrl.value.size.isEmpty ? cap.size : _ctrl.value.size;

  void _handle(BarcodeCapture cap) {
    final telegram = ref.read(scanFrameTelegramProvider);
    final lockMs = ref.read(scanLockMsProvider);
    final size = _imageSize(cap);
    final accept = widget.accept;
    final candidates =
        accept == null ? cap.barcodes : cap.barcodes.where(accept).toList();

    // Kunci target (eksperimental, 0 = mati): hanya kode terkunci yang
    // diteruskan; barcode lain di sampingnya diabaikan.
    Barcode? locked;
    _follow.smooth = lockMs > 0;
    if (lockMs > 0) {
      _lock.release = Duration(milliseconds: lockMs);
      // Bingkai bertahan selama kunci ditahan (tidak mantul ke tengah).
      _follow.lostAfter = Duration(milliseconds: lockMs < 450 ? 450 : lockMs);
      locked = _lock.select(candidates, size, DateTime.now());
      if (locked == null) {
        // Kode terkunci sedang tak terbaca: tahan bingkai di tempatnya.
        if (_lock.lockedValue != null) _follow.hold();
        return;
      }
      cap = BarcodeCapture(
          barcodes: [locked], image: cap.image, raw: cap.raw, size: cap.size);
    } else {
      _lock.reset();
      _rect.reset();
      _rectFor = null;
      _follow.lostAfter = const Duration(milliseconds: 450);
    }

    if (!telegram) {
      widget.onDetect(cap);
      return;
    }
    final b = locked ?? AppScanner.pickBarcode(candidates, size);
    if (b != null) {
      var corners = b.corners;
      if (lockMs > 0 && corners.isNotEmpty) {
        // Ganti target = mulai penyaring dari nol (tak mewarisi kotak lama).
        if (_rectFor != b.rawValue) {
          _rect.reset();
          _rectFor = b.rawValue;
        }
        final r = _rect.add(boundsOf(corners));
        corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
      }
      _follow.report(corners, size);
    }

    if (widget.lockDelay > Duration.zero) {
      // Satu-tembak: teruskan hasil TERBARU setelah bingkai terkunci.
      if (b == null) return;
      _latest = cap;
      _lockTimer ??= Timer(widget.lockDelay, () {
        _lockTimer = null;
        final c = _latest;
        _latest = null;
        if (mounted && c != null) widget.onDetect(c);
      });
      return;
    }
    widget.onDetect(cap);
    if (b != null && widget.releaseAfter != null) {
      _releaseTimer?.cancel();
      _releaseTimer = Timer(widget.releaseAfter!, _follow.release);
    }
  }

  @override
  Widget build(BuildContext context) {
    final telegram = ref.watch(scanFrameTelegramProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _ctrl,
          fit: widget.fit,
          onDetect: _handle,
          errorBuilder: widget.errorBuilder,
        ),
        if (telegram)
          IgnorePointer(
            child: ScanFollowOverlay(controller: _follow, fit: widget.fit),
          )
        else if (widget.legacyOverlay != null)
          widget.legacyOverlay!,
      ],
    );
  }
}
