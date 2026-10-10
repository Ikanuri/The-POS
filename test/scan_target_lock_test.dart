import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:the_pos/core/widgets/scan_target_lock.dart';

Barcode bc(String v, double cx, double cy) => Barcode(
      rawValue: v,
      corners: [
        Offset(cx - 20, cy - 10),
        Offset(cx + 20, cy - 10),
        Offset(cx + 20, cy + 10),
        Offset(cx - 20, cy + 10),
      ],
    );

void main() {
  rectFilterTests();
  const img = Size(400, 400);
  final t0 = DateTime(2026, 1, 1, 10);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('mengunci yang terdekat tengah lalu mengabaikan barcode lain', () {
    final lock = ScanTargetLock(release: const Duration(milliseconds: 600));
    var r = lock.select([bc('A', 200, 200), bc('B', 100, 100)], img, at(0));
    expect(r!.rawValue, 'A');
    // B kini lebih dekat ke tengah daripada A, tapi A masih terbaca -> tetap A.
    r = lock.select([bc('A', 330, 330), bc('B', 205, 205)], img, at(100));
    expect(r!.rawValue, 'A');
  });

  test('kode terkunci hilang sebentar -> frame diabaikan (kunci ditahan)', () {
    final lock = ScanTargetLock(release: const Duration(milliseconds: 600));
    lock.select([bc('A', 200, 200)], img, at(0));
    expect(lock.select([bc('B', 200, 200)], img, at(300)), isNull);
    expect(lock.lockedValue, 'A');
    // A muncul lagi sebelum batas -> lanjut.
    expect(lock.select([bc('A', 210, 210)], img, at(500))!.rawValue, 'A');
  });

  test('lepas setelah melewati batas lalu memilih ulang yang terdekat tengah',
      () {
    final lock = ScanTargetLock(release: const Duration(milliseconds: 600));
    lock.select([bc('A', 200, 200)], img, at(0));
    final r = lock
        .select([bc('B', 90, 90), bc('C', 190, 195)], img, at(700)); // > 600 ms
    expect(r!.rawValue, 'C');
    expect(lock.lockedValue, 'C');
  });

  test('tanpa barcode sama sekali -> null, tanpa kunci', () {
    final lock = ScanTargetLock(release: const Duration(milliseconds: 600));
    expect(lock.select([], img, at(0)), isNull);
    expect(lock.lockedValue, isNull);
  });

  test('dua barcode ber-isi sama: dipilih yang terdekat tengah', () {
    final lock = ScanTargetLock(release: const Duration(milliseconds: 600));
    lock.select([bc('A', 200, 200)], img, at(0));
    final r = lock.select([bc('A', 50, 50), bc('A', 195, 205)], img, at(100));
    expect(r!.corners.first.dx, closeTo(175, 0.1));
  });
}

void rectFilterTests() {
  group('ScanRectFilter', () {
    test('lonjakan SATU frame dibuang (kotak tidak melompat)', () {
      final f = ScanRectFilter();
      const base = Rect.fromLTRB(100, 200, 200, 240);
      f.add(base);
      f.add(base);
      // frame ke-3: kotak sesaat naik ke atas barcode
      final out = f.add(const Rect.fromLTRB(100, 140, 200, 180));
      expect(out.top, closeTo(200, 1), reason: 'median menolak lonjakan');
      expect(out.bottom, closeTo(240, 1));
    });

    test('gerak nyata tetap diikuti (bukan membeku)', () {
      final f = ScanRectFilter();
      var r = const Rect.fromLTRB(100, 200, 200, 240);
      Rect out = r;
      for (var i = 0; i < 12; i++) {
        r = r.shift(const Offset(10, 0));
        out = f.add(r);
      }
      expect(out.left, greaterThan(r.left - 30));
      expect(out.left, lessThanOrEqualTo(r.left));
    });

    test('reset: sampel pertama diterima apa adanya', () {
      final f = ScanRectFilter();
      f.add(const Rect.fromLTRB(0, 0, 10, 10));
      f.reset();
      expect(f.add(const Rect.fromLTRB(500, 500, 600, 600)).left, 500);
    });
  });
}
