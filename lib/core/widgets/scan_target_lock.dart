import 'package:flutter/painting.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'app_scanner.dart';

/// Kunci target pemindai: barcode yang paling dekat ke tengah DIKUNCI
/// berdasarkan ISI kodenya; selama kode itu masih terbaca, barcode lain di
/// sampingnya DIABAIKAN (walau lebih dekat ke tengah, walau kode terkunci
/// bergeser/sebagian keluar bingkai). Kunci lepas bila kode itu tak terbaca
/// selama [release] — baru barcode berikutnya bisa dipilih.
///
/// Logika murni (waktu disuntik lewat `now`) supaya mudah diuji.
class ScanTargetLock {
  ScanTargetLock({required this.release});

  /// Lama kode terkunci boleh tak terbaca sebelum kunci dilepas.
  Duration release;

  String? _value;
  DateTime? _lastSeen;

  /// Isi kode yang sedang terkunci (null = belum ada).
  String? get lockedValue => _value;

  void reset() {
    _value = null;
    _lastSeen = null;
  }

  /// Pilih barcode untuk frame ini. Null = abaikan frame (kode terkunci
  /// sedang tak terbaca tapi belum melewati [release], atau tak ada kode).
  Barcode? select(List<Barcode> list, Size image, DateTime now) {
    final locked = _value;
    if (locked != null) {
      final same = list.where((b) => b.rawValue == locked).toList();
      if (same.isNotEmpty) {
        _lastSeen = now;
        return AppScanner.pickBarcode(same, image) ?? same.first;
      }
      if (now.difference(_lastSeen!) <= release) return null; // tahan kunci
      reset(); // kode lama hilang cukup lama -> boleh pilih yang baru
    }
    final b = AppScanner.pickBarcode(list, image);
    if (b != null) {
      _value = b.rawValue;
      _lastSeen = now;
    }
    return b;
  }
}

/// Penyaring kotak untuk mode kunci target: sudut barcode 1D dari ML Kit
/// sering berubah-ubah antar-frame (kotak sesaat naik/melebar ke teks di
/// sekitarnya). Median 3 sampel per sisi membuang lonjakan SATU frame, lalu
/// perataan eksponensial menghaluskan sisanya. Bekerja di ruang gambar.
class ScanRectFilter {
  ScanRectFilter({this.alpha = 0.6});

  /// Bobot sampel baru pada perataan (1 = tanpa perataan).
  final double alpha;

  final List<Rect> _hist = [];
  Rect? _out;

  void reset() {
    _hist.clear();
    _out = null;
  }

  static double _median3(double a, double b, double c) {
    final l = [a, b, c]..sort();
    return l[1];
  }

  Rect add(Rect r) {
    _hist.add(r);
    if (_hist.length > 3) _hist.removeAt(0);
    final med = _hist.length < 3
        ? r
        : Rect.fromLTRB(
            _median3(_hist[0].left, _hist[1].left, _hist[2].left),
            _median3(_hist[0].top, _hist[1].top, _hist[2].top),
            _median3(_hist[0].right, _hist[1].right, _hist[2].right),
            _median3(_hist[0].bottom, _hist[1].bottom, _hist[2].bottom),
          );
    final prev = _out;
    final out = prev == null ? med : Rect.lerp(prev, med, alpha)!;
    _out = out;
    return out;
  }
}
