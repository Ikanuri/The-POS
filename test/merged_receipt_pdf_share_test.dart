import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/kasir/merged_receipt_screen.dart';

/// Bug dilaporkan user: struk GABUNGAN dgn banyak item (mis. 67 item dari 3
/// nota) hasil "Bagikan" jadi gambar PNG yang SANGAT tinggi (lebar tetap 300,
/// tinggi bertambah linear per item, dikali `pixelRatio: 3.0`). WhatsApp/app
/// share lain mengompresi paksa gambar sepanjang itu ke sisi terpanjang
/// ~1600px (perilaku umum "kirim sbg foto") — teks jadi remuk tak terbaca.
/// Fix: bungkus capture yang SAMA jadi 1 halaman PDF pas ukurannya (bukan
/// foto) — dikirim sbg dokumen, tidak ikut dikompresi ulang berapa pun
/// panjangnya.
///
/// Test ini menguji `buildReceiptPdfBytes` (fungsi murni diekstrak dari
/// `_share()`) langsung, BUKAN lewat widget+tap tombol Bagikan — di
/// environment `flutter test` (host Linux), `share_plus` otomatis pakai
/// `SharePlusLinuxPlugin` (bukan `MethodChannel` Android), jadi mock
/// MethodChannel platform TIDAK PERNAH ke-hit di sini; menguji logika PDF
/// murni menghindari masalah itu sepenuhnya.
Future<Uint8List> _tinyPngBytes({int width = 10, int height = 10}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

void main() {
  test(
      'buildReceiptPdfBytes() menghasilkan 1 halaman PDF valid berukuran '
      'pas ukuran logis yang diberikan (bukan A4/ukuran baku)', () async {
    final png = await _tinyPngBytes();

    final pdfBytes = await MergedReceiptScreen.buildReceiptPdfBytes(
      pngBytes: png,
      logicalWidth: 300,
      logicalHeight: 3000,
    );

    // Magic bytes PDF valid — bukan file kosong/rusak.
    expect(utf8.decode(pdfBytes.take(5).toList(), allowMalformed: true),
        '%PDF-');

    // Ukuran halaman (dalam points, 1:1 dgn logicalWidth/Height yg diberikan)
    // harus tertulis di dalam PDF-nya (MediaBox) — bukti halaman dibuat pas
    // konten, BUKAN dipaksa ke A4/ukuran baku seperti ekspor laporan biasa.
    final content = latin1.decode(pdfBytes, allowInvalid: true);
    expect(content, contains('/MediaBox'));
    expect(content, contains('300'));
    expect(content, contains('3000'));
  });

  test(
      'buildReceiptPdfBytes() tetap 1 halaman PDF valid utk rasio SANGAT '
      'memanjang (mis. 67 item struk gabungan, ~900x9000 logis)', () async {
    final png = await _tinyPngBytes(width: 30, height: 300);

    final pdfBytes = await MergedReceiptScreen.buildReceiptPdfBytes(
      pngBytes: png,
      logicalWidth: 300,
      logicalHeight: 9000,
    );

    expect(utf8.decode(pdfBytes.take(5).toList(), allowMalformed: true),
        '%PDF-');
    expect(pdfBytes.length, greaterThan(100),
        reason: 'PDF harus benar-benar berisi halaman + gambar, bukan kosong');
  });
}
