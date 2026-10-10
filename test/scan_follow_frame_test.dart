import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:the_pos/core/widgets/app_scanner.dart';
import 'package:the_pos/core/widgets/scan_follow_frame.dart';

/// Bingkai pemindai ala Telegram (`CameraScanActivity`): pemetaan koordinat,
/// kotak tengah, pegas muncul/kunci, interpolasi 75 ms, hilang -> kembali.
void main() {
  group('pemetaan koordinat', () {
    test(
        'cover: gambar potret 1080x1920 di view 360x400 (sisi atas/bawah terpotong)',
        () {
      const image = Size(1080, 1920);
      const view = Size(360, 400);
      // skala = max(360/1080, 400/1920) = 0.3333; tinggi gambar 640 > 400 -> oy = -120
      final p = mapImagePointToView(const Offset(540, 960), image, view);
      expect(p.dx, closeTo(180, 1e-6));
      expect(p.dy, closeTo(200, 1e-6), reason: 'tengah gambar = tengah view');
      final topLeft = mapImagePointToView(Offset.zero, image, view);
      expect(topLeft.dx, closeTo(0, 1e-6));
      expect(topLeft.dy, closeTo(-120, 1e-6));
    });

    test('contain: ada letterbox', () {
      final p = mapImagePointToView(
          Offset.zero, const Size(100, 200), const Size(400, 400),
          fit: BoxFit.contain);
      expect(p.dx, closeTo(100, 1e-6)); // skala 2 -> lebar 200, offset 100
      expect(p.dy, closeTo(0, 1e-6));
    });

    test('boundsOf + padding', () {
      final r = boundsOf(const [
        Offset(10, 20),
        Offset(50, 20),
        Offset(50, 40),
        Offset(10, 40)
      ], padX: 25, padY: 15);
      expect(r, const Rect.fromLTRB(-15, 5, 75, 55));
    });
  });

  group('AppScanner.pickBarcode', () {
    Barcode bc(String? v, List<Offset> corners) =>
        Barcode(rawValue: v, corners: corners);
    const img = Size(1000, 1000);
    List<Offset> box(double cx, double cy) => [
          Offset(cx - 20, cy - 20),
          Offset(cx + 20, cy - 20),
          Offset(cx + 20, cy + 20),
          Offset(cx - 20, cy + 20),
        ];

    test('memilih yang paling dekat ke tengah; mengabaikan nilai kosong', () {
      final far = bc('A', box(100, 100));
      final near = bc('B', box(480, 520));
      final empty = bc('', box(500, 500));
      expect(AppScanner.pickBarcode([far, empty, near], img)!.rawValue, 'B');
      expect(AppScanner.pickBarcode([empty], img), isNull);
    });

    test('tanpa titik sudut tetap dipilih (terbaca tanpa posisi)', () {
      final x = bc('C', const []);
      expect(AppScanner.pickBarcode([x], img)!.rawValue, 'C');
    });
  });

  group('ScanFollowOverlay', () {
    const image = Size(360, 640); // 1:1 dgn view -> koordinat sama
    late ScanFollowController ctl;
    // Ticker baru mulai di frame berikutnya: majukan waktu dgn langkah 16 ms.
    Future<void> advance(WidgetTester tester, int ms) async {
      for (var t = 0; t < ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    // Kamera melaporkan terus (~30 Hz) selama kode terlihat.
    Future<void> track(
        WidgetTester tester, List<Offset> corners, int ms) async {
      for (var t = 0; t < ms; t += 32) {
        ctl.report(corners, image);
        await tester.pump(const Duration(milliseconds: 32));
      }
    }

    Future<void> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      ctl = ScanFollowController();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
              width: 360,
              height: 640,
              child: ScanFollowOverlay(controller: ctl)),
        ),
      ));
      await tester.pump();
    }

    List<Offset> qr(double cx, double cy, double half) => [
          Offset(cx - half, cy - half),
          Offset(cx + half, cy - half),
          Offset(cx + half, cy + half),
          Offset(cx - half, cy + half),
        ];

    testWidgets('awal: kotak tengah sisi min(w,h)/1,5, belum terkunci',
        (tester) async {
      await pump(tester);
      final b = ctl.debugBounds!;
      expect(b.width, closeTo(240, 1e-6));
      expect(b.height, closeTo(240, 1e-6));
      expect(b.center, const Offset(180, 320));
      expect(ctl.recognized, isFalse);
      expect(ctl.debugAppearing, 0);
    });

    testWidgets('appear(): pegas membal lalu menetap di 1', (tester) async {
      await pump(tester);
      ctl.appear();
      await advance(tester, 100);
      expect(ctl.debugAppearing, greaterThan(0));
      var maxV = 0.0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        maxV = ctl.debugAppearing > maxV ? ctl.debugAppearing : maxV;
      }
      expect(maxV, greaterThan(1.0), reason: 'damping 0,8 = sedikit melampaui');
      await tester.pumpAndSettle();
      expect(ctl.debugAppearing, closeTo(1, 0.01));
    });

    testWidgets(
        'report(): terkunci, bingkai menetap di kotak kode + padding 25x15',
        (tester) async {
      await pump(tester);
      ctl.appear();
      ctl.report(qr(100, 150, 40), image);
      expect(ctl.recognized, isTrue);
      // Pegas kunci + lerp 75 ms selesai (kamera terus melapor).
      await track(tester, qr(100, 150, 40), 1500);
      expect(ctl.debugUseRecognized, closeTo(1, 0.01));
      final b = ctl.debugBounds!;
      expect(b.left, closeTo(100 - 40 - 25, 0.5));
      expect(b.right, closeTo(100 + 40 + 25, 0.5));
      expect(b.top, closeTo(150 - 40 - 15, 0.5));
      expect(b.bottom, closeTo(150 + 40 + 15, 0.5));
      // timer 'hilang' dibatalkan agar test bersih
      await advance(tester, 1000);
    });

    testWidgets('laporan kedua: bergeser LINEAR 75 ms dari posisi tampil',
        (tester) async {
      await pump(tester);
      ctl.report(qr(100, 150, 40), image);
      await track(tester, qr(100, 150, 40), 1500);
      final before = ctl.debugBounds!.center;
      ctl.report(qr(260, 150, 40), image); // geser 160 px ke kanan
      await tester.pump(); // frame awal t=0
      await tester.pump(const Duration(milliseconds: 37));
      final mid = ctl.debugBounds!.center.dx;
      expect(mid, greaterThan(before.dx + 50));
      expect(mid, lessThan(260 - 50), reason: 'belum sampai di ~37 ms');
      // Laporan berulang ke target yang sama: tiap laporan memulai ulang lerp
      // dari posisi tampil (perilaku Telegram) -> konvergen mulus ke target.
      await track(tester, qr(260, 150, 40), 128);
      final converging = ctl.debugBounds!.center.dx;
      expect(converging, greaterThan(mid));
      await advance(tester, 160); // tanpa laporan baru: lerp terakhir selesai
      expect(ctl.debugBounds!.center.dx, closeTo(260, 1));
      await advance(tester, 1000);
    });

    testWidgets('tanpa laporan ~450 ms: terlepas & kembali ke kotak tengah',
        (tester) async {
      await pump(tester);
      ctl.report(qr(100, 150, 40), image);
      await advance(tester, 600);
      expect(ctl.recognized, isFalse, reason: 'timer hilang menembak');
      await advance(tester, 1500);
      expect(ctl.debugUseRecognized, closeTo(0, 0.01));
      expect(ctl.debugBounds!.center.dx, closeTo(180, 0.5));
    });

    testWidgets(
        'hold(): kode terkunci tak terbaca -> bingkai TETAP di posisi, tak mantul ke tengah',
        (tester) async {
      await pump(tester);
      ctl.lostAfter = const Duration(milliseconds: 1000);
      await track(tester, qr(100, 150, 40), 1500);
      final before = ctl.debugBounds!.center;
      // 1600 ms (> lostAfter 1000 ms) tanpa laporan, tapi di-hold tiap 100 ms.
      for (var t = 0; t < 1600; t += 100) {
        ctl.hold();
        await advance(tester, 100);
      }
      expect(ctl.recognized, isTrue);
      expect(ctl.debugBounds!.center.dx, closeTo(before.dx, 0.5));
      expect(ctl.debugBounds!.center.dy, closeTo(before.dy, 0.5));
      // Berhenti hold & lapor -> lepas setelah lostAfter (1000 ms).
      await advance(tester, 1200);
      expect(ctl.recognized, isFalse);
    });

    testWidgets('lostAfter diperpanjang: 600 ms tanpa laporan belum lepas',
        (tester) async {
      await pump(tester);
      ctl.lostAfter = const Duration(milliseconds: 1000);
      ctl.report(qr(100, 150, 40), image);
      await advance(tester, 600);
      expect(ctl.recognized, isTrue);
    });

    testWidgets('release() melepas kunci manual', (tester) async {
      await pump(tester);
      ctl.report(qr(100, 150, 40), image);
      await tester.pump();
      ctl.release();
      expect(ctl.recognized, isFalse);
      await advance(tester, 2000);
    });

    testWidgets(
        'terbaca tanpa titik sudut: terkunci tapi bingkai tetap di tengah',
        (tester) async {
      await pump(tester);
      ctl.report(const [], image);
      expect(ctl.recognized, isTrue);
      await advance(tester, 100);
      expect(ctl.debugBounds!.center, const Offset(180, 320));
      await advance(tester, 1000);
    });
  });
}
