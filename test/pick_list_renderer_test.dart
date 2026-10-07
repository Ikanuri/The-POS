import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  /// Telusuri aliran byte: tiap `GS v 0` harus diikuti TEPAT sebanyak data
  /// rasternya (xL+xH*256)*(yL+yH*256) — kalau tidak, printer kehilangan
  /// sinkron & mencetak sisa sbg teks sampah (laporan user).
  List<({int rows, int bytesPerRow})> rasterCommands(List<int> bytes) {
    final out = <({int rows, int bytesPerRow})>[];
    var i = 0;
    while (i < bytes.length - 8) {
      if (bytes[i] == 0x1D && bytes[i + 1] == 0x76 && bytes[i + 2] == 0x30) {
        final bpr = bytes[i + 4] + bytes[i + 5] * 256;
        final rows = bytes[i + 6] + bytes[i + 7] * 256;
        out.add((rows: rows, bytesPerRow: bpr));
        i += 8 + bpr * rows;
      } else {
        i++;
      }
    }
    return out;
  }

  test(
      'banyak item: tiap perintah raster <= 96 baris & dikirim bertahap '
      '(bukan satu blok raksasa)', () async {
    final many = [
      for (var i = 0; i < 40; i++)
        PickLine(
            qty: i + 1,
            name: 'Produk nomor $i dengan nama agak panjang sedikit',
            unit: 'Dus',
            note: i % 3 == 0 ? 'catatan $i' : null,
            checked: i.isEven),
    ];
    final parts = await PrinterService.buildPickListParts(
      storeName: 'Toko Berkah',
      at: DateTime(2026, 10, 7, 17, 23),
      lines: many,
      settings: const PrinterSettings(),
    );
    expect(parts.length, greaterThan(10), reason: 'dikirim dlm banyak bagian');
    final all = [for (final p in parts) ...p];
    final cmds = rasterCommands(all);
    expect(cmds, isNotEmpty);
    for (final c in cmds) {
      expect(c.rows, lessThanOrEqualTo(PrinterService.pickListStripRows));
      expect(c.bytesPerRow, 48); // 384 dot / 8
    }
    // Setiap bagian berisi paling banyak SATU perintah raster utuh.
    for (final p in parts) {
      expect(rasterCommands(p).length, lessThanOrEqualTo(1));
    }
    // Total baris raster = tinggi semua gambar (tidak ada baris hilang).
    final totalRows = cmds.fold<int>(0, (s, c) => s + c.rows);
    final chunks = PickListRenderer.render([
      for (final l in many)
        PickLine(
            qty: l.qty,
            name: l.name,
            unit: l.unit,
            note: l.note,
            checked: l.checked)
    ], 384);
    expect(totalRows, chunks.fold<int>(0, (s, c) => s + c.height));
  });

  test('kertas 80mm: lebar raster 72 byte/baris, tetap <= 96 baris', () async {
    final parts = await PrinterService.buildPickListParts(
      storeName: 'Toko',
      at: DateTime(2026, 10, 7),
      lines: const [PickLine(qty: 1, name: 'Gula', unit: 'Kg')],
      settings: const PrinterSettings(paperSize: '80'),
    );
    final cmds = rasterCommands([for (final p in parts) ...p]);
    expect(cmds, isNotEmpty);
    for (final c in cmds) {
      expect(c.bytesPerRow, 72);
      expect(c.rows, lessThanOrEqualTo(96));
    }
  });

  test(
      'edge: nama/satuan kosong, non-ASCII, qty pecahan panjang tidak '
      'merusak render', () async {
    final parts = await PrinterService.buildPickListParts(
      storeName: '',
      at: DateTime(2026, 10, 7),
      lines: const [
        PickLine(qty: 1, name: '', unit: ''),
        PickLine(
            qty: 0.3333333333, name: 'Kopi Susu \u2014 Caf\u00e9', unit: 'Kg'),
        PickLine(qty: 12345678, name: 'X', unit: 'Pcs', note: ''),
      ],
      settings: const PrinterSettings(),
    );
    expect(parts, isNotEmpty);
    expect(PickListRenderer.qtyLabel(0.3333333333), '0.333x');
    expect(PickListRenderer.qtyLabel(2.5), '2.5x');
    expect(PickListRenderer.qtyLabel(2.0), '2x');
  });

  // ── Nama & alamat pelanggan di header ────────────────────────────────────
  const oneLine = [PickLine(qty: 1, name: 'Gula', unit: 'Kg')];
  final at = DateTime(2026, 10, 7, 14, 32);

  Future<Uint8List> headerOf({
    String name = '',
    String address = '',
    PrinterSettings settings = const PrinterSettings(),
  }) async {
    final parts = await PrinterService.buildPickListParts(
      storeName: 'Toko Berkah',
      at: at,
      lines: oneLine,
      settings: settings,
      customerName: name,
      customerAddress: address,
    );
    return parts.first;
  }

  int indexOfAscii(List<int> bytes, String needle, [int from = 0]) {
    final n = latin1.encode(needle);
    for (var i = from; i <= bytes.length - n.length; i++) {
      var ok = true;
      for (var k = 0; k < n.length; k++) {
        if (bytes[i + k] != n[k]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  /// Apakah ESC E 1 (bold on) muncul di [from, to).
  bool boldOnBetween(List<int> b, int from, int to) {
    for (var i = from; i + 2 < to; i++) {
      if (b[i] == 0x1B && b[i + 1] == 0x45 && b[i + 2] == 0x01) return true;
    }
    return false;
  }

  test('tanpa pelanggan: header IDENTIK byte-per-byte dgn sebelum fitur', () async {
    final baseline = await headerOf();
    expect(await headerOf(name: ''), baseline);
    expect(await headerOf(name: '   \t ', address: 'Jl. Mawar 1'), baseline,
        reason: 'nama hanya spasi = tanpa pelanggan; alamat tanpa nama diabaikan');
    expect(await headerOf(name: '中文', address: 'Jl. X'), baseline,
        reason: 'nama yang habis setelah sanitasi ASCII = tanpa pelanggan');
    final withName = await headerOf(name: 'Bu Ani');
    expect(withName.length, greaterThan(baseline.length));
  });

  test('nama pelanggan tebal, alamat biasa; keduanya setelah timestamp, '
      'sebelum garis pemisah', () async {
    final h = await headerOf(name: 'Bu Ani', address: 'Jl. Mawar No. 5');
    final stampAt = indexOfAscii(h, '07/10/2026 14:32');
    final nameAt = indexOfAscii(h, 'Bu Ani');
    final addrAt = indexOfAscii(h, 'Jl. Mawar No. 5');
    expect(stampAt, greaterThan(0));
    expect(nameAt, greaterThan(stampAt));
    expect(addrAt, greaterThan(nameAt));
    expect(indexOfAscii(h, '--------', addrAt), greaterThan(addrAt),
        reason: 'garis pemisah (hr) setelah alamat');
    // Bold ON tepat sebelum nama (setelah timestamp), TIDAK ada bold ON
    // antara akhir nama dan awal alamat.
    expect(boldOnBetween(h, stampAt + 16, nameAt), isTrue);
    expect(boldOnBetween(h, nameAt + 6, addrAt), isFalse,
        reason: 'alamat tidak tebal');
  });

  test('pelanggan tetap tanpa alamat: hanya nama', () async {
    final h = await headerOf(name: 'Toko Sumber', address: '  ');
    expect(indexOfAscii(h, 'Toko Sumber'), greaterThan(0));
    final h2 = await headerOf(name: 'Toko Sumber');
    expect(h, h2);
  });

  test('edge: non-ASCII disanitasi, newline alamat jadi baris terpisah, '
      'nama & alamat panjang dipecah per kata sesuai lebar kertas', () async {
    final h = await headerOf(
      name: 'Bu Siti — Café Sumber Rejeki Makmur Sentosa Abadi',
      address: 'Jl. Raya Panjang Sekali No. 123\nRT 01/RW 02 • Kel. Baru',
    );
    // Em-dash & bullet dipetakan ke ASCII ('-' / '*'), bukan dibuang/dikirim.
    // Nama 32 kol: dipecah di batas kata.
    expect(indexOfAscii(h, 'Bu Siti - Cafe Sumber Rejeki'), greaterThan(0));
    expect(indexOfAscii(h, 'Makmur Sentosa Abadi'), greaterThan(0));
    // Newline alamat -> dua baris sendiri-sendiri.
    expect(indexOfAscii(h, 'Jl. Raya Panjang Sekali No. 123'), greaterThan(0));
    expect(indexOfAscii(h, 'RT 01/RW 02 * Kel. Baru'), greaterThan(0));
    // Kata tunggal sangat panjang dipotong paksa, tidak melempar.
    final long = await headerOf(name: 'A' * 70);
    expect(indexOfAscii(long, 'A' * 32), greaterThan(0));
    expect(indexOfAscii(long, 'A' * 33), -1);
  });

  test('kertas 80mm: baris pelanggan selebar 42 kolom', () async {
    final h = await headerOf(
      name: '${'B' * 40} ${'C' * 10}',
      settings: const PrinterSettings(paperSize: '80'),
    );
    expect(indexOfAscii(h, 'B' * 40), greaterThan(0));
    expect(indexOfAscii(h, '${'B' * 40} C'), -1,
        reason: '40+1+10 > 42 -> pindah baris');
  });

  test('daftar kosong -> tidak ada gambar', () {
    expect(PickListRenderer.render(const [], 384), isEmpty);
  });
}
