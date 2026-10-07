import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:the_pos/core/services/pick_list_renderer.dart';
import 'package:the_pos/core/services/printer_service.dart';

/// Struk ambil barang: baris dirender jadi gambar monokrom (qty besar, nama,
/// kotak centang persegi tumpul di kanan, TANPA harga). Murni logika
/// gambar/byte — tanpa printer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lines = [
    PickLine(qty: 2, name: 'Sedap Goreng Ayam Bawang', unit: 'Dus'),
    PickLine(
        qty: 10,
        name: 'Gula Pasir',
        unit: 'Kg',
        note: 'yang kemasan baru',
        checked: true),
    PickLine(qty: 0.5, name: 'Tepung Segitiga Biru', unit: 'Kg'),
    PickLine(
        qty: 24,
        name: 'Aqua 600ml Botol Kemasan Dus Isi Dua Puluh Empat Besar Sekali',
        unit: 'Dus',
        isVariant: true),
  ];

  bool isBlack(img.Image im, int x, int y) => im.getPixel(x, y).r < 128;

  test(
      'render: gambar selebar kertas, kotak centang menempel SETELAH nama '
      '(bukan di tepi kanan), tanda centang hanya di baris yang dicentang', () {
    final chunks = PickListRenderer.render(lines, 384);
    expect(chunks, isNotEmpty);
    for (final c in chunks) {
      expect(c.width, 384);
    }
    final all = chunks.first;
    final boxes = PickListRenderer.debugBoxes;
    expect(boxes.length, lines.length);

    // Nama pendek ("Gula Pasir (Kg)") -> kotak jauh dari tepi kanan kertas.
    expect(boxes[1].x, lessThan(250),
        reason: 'kotak menempel setelah nama pendek, bukan di ujung kanan');
    // Nama panjang yang terbungkus -> kotak tetap di dalam kertas.
    for (final b in boxes) {
      expect(b.x + b.size, lessThanOrEqualTo(384 - 4));
    }

    int blackIn(({int x, int y, int size}) b) {
      var n = 0;
      for (var y = b.y + 8; y < b.y + b.size - 8; y++) {
        for (var x = b.x + 8; x < b.x + b.size - 8; x++) {
          if (isBlack(all, x, y)) n++;
        }
      }
      return n;
    }

    expect(blackIn(boxes[0]), 0, reason: 'baris 1 tidak dicentang');
    expect(blackIn(boxes[1]), greaterThan(30),
        reason: 'baris 2 dicentang -> ada tanda centang');
    // Bingkai kotak tergambar (sisi kiri hitam).
    final mid = boxes[0].y + boxes[0].size ~/ 2;
    expect(
        [for (var d = 0; d < 3; d++) isBlack(all, boxes[0].x + d, mid)]
            .any((v) => v),
        isTrue);
  });

  test('wrap: nama panjang terpotong maks 3 baris + ".."', () {
    final w = PickListRenderer.wrap(
        img.arial24,
        'Aqua 600ml Botol Kemasan Dus Isi Dua Puluh Empat Besar Sekali (Dus)',
        200,
        3);
    expect(w.length, 3);
    expect(w.last.endsWith('..'), isTrue);
  });

  test('qtyLabel: bulat tanpa desimal, pecahan apa adanya', () {
    expect(PickListRenderer.qtyLabel(10), '10x');
    expect(PickListRenderer.qtyLabel(0.5), '0.5x');
  });

  test(
      'buildPickListBytes: berisi perintah raster (GS v 0) & tidak kosong; '
      'nama toko non-ASCII disanitasi', () async {
    final bytes = await PrinterService.buildPickListBytes(
      storeName: 'Toko Berkah — Jaya',
      at: DateTime(2026, 10, 7, 14, 32),
      lines: lines,
      settings: const PrinterSettings(),
    );
    expect(bytes.length, greaterThan(500));
    var hasRaster = false;
    for (var i = 0; i < bytes.length - 2; i++) {
      if (bytes[i] == 0x1D && bytes[i + 1] == 0x76 && bytes[i + 2] == 0x30) {
        hasRaster = true;
        break;
      }
    }
    expect(hasRaster, isTrue);
    final dump = Platform.environment['PICKLIST_DUMP'];
    if (dump != null) {
      final chunks = PickListRenderer.render(lines, 384);
      for (var i = 0; i < chunks.length; i++) {
        File('$dump/picklist_$i.png')
            .writeAsBytesSync(img.encodePng(chunks[i]));
      }
    }
  });

  test('daftar kosong -> tidak ada gambar', () {
    expect(PickListRenderer.render(const [], 384), isEmpty);
  });
}
