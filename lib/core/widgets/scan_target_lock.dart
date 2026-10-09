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
