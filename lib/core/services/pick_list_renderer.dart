import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;

/// Satu baris "struk ambil barang" (daftar pengambilan untuk pegawai gudang,
/// dicetak SEBELUM checkout) — TANPA harga.
class PickLine {
  const PickLine({
    required this.qty,
    required this.name,
    required this.unit,
    this.note,
    this.checked = false,
    this.isVariant = false,
  });

  final double qty;
  final String name;
  final String unit;
  final String? note;

  /// true = kotak sudah dicentang di keranjang -> tercetak berisi tanda centang.
  final bool checked;
  final bool isVariant;
}

/// Merender baris-baris [PickLine] jadi gambar monokrom untuk printer thermal
/// (di-raster, lihat `PrinterService.printPickList`). Dirender sebagai GAMBAR
/// (bukan teks ESC/POS) karena kotak centang bersudut tumpul mustahil lewat
/// karakter ASCII, dan font bisa dipilih lebih besar dari teks printer
/// (efisiensi ruang bekas kolom harga). Pola sama dgn logo QRIS struk.
///
/// Semua teks WAJIB sudah ASCII (font bitmap bawaan `image` hanya ASCII) —
/// pemanggil (`PrinterService`) yang menyanitasi.
class PickListRenderer {
  PickListRenderer._();

  static const _margin = 4;
  static const _boxSize = 44;
  static const _gap = 8;
  static const _rowPadY = 8;
  static const _noteIndent = 0;

  /// Test-only: posisi kotak centang hasil render terakhir (y absolut).
  @visibleForTesting
  static final List<({int x, int y, int size})> debugBoxes = [];

  /// Lebar kolom qty = qty terlebar di daftar (dibatasi) supaya nama sejajar.
  static int _textWidth(img.BitmapFont font, String s) {
    var w = 0;
    for (final c in s.codeUnits) {
      w += font.characters[c]?.xAdvance ?? (font.size ~/ 2);
    }
    return w;
  }

  /// Pecah [text] jadi baris-baris selebar [maxW] (per kata; kata terlalu
  /// panjang dipotong per karakter). Maks [maxLines], sisanya "..".
  static List<String> wrap(
      img.BitmapFont font, String text, int maxW, int maxLines) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final lines = <String>[];
    var cur = '';
    void flush() {
      if (cur.isNotEmpty) lines.add(cur);
      cur = '';
    }

    for (var word in words) {
      // Kata lebih lebar dari baris -> potong.
      while (_textWidth(font, word) > maxW) {
        var cut = word.length - 1;
        while (cut > 1 && _textWidth(font, word.substring(0, cut)) > maxW) {
          cut--;
        }
        flush();
        lines.add(word.substring(0, cut));
        word = word.substring(cut);
      }
      final trial = cur.isEmpty ? word : '$cur $word';
      if (_textWidth(font, trial) <= maxW) {
        cur = trial;
      } else {
        flush();
        cur = word;
      }
    }
    flush();
    if (lines.length > maxLines) {
      final kept = lines.sublist(0, maxLines);
      var last = kept.last;
      while (last.length > 1 && _textWidth(font, '$last..') > maxW) {
        last = last.substring(0, last.length - 1);
      }
      kept[maxLines - 1] = '$last..';
      return kept;
    }
    return lines;
  }

  static String qtyLabel(double q) =>
      '${q % 1 == 0 ? q.toInt().toString() : q.toString()}x';

  /// Render semua baris; hasilnya daftar gambar (tiap gambar = kumpulan baris,
  /// tinggi dibatasi [chunkMax] supaya perintah raster tidak terlalu besar).
  static List<img.Image> render(List<PickLine> lines, int paperDots,
      {int chunkMax = 640}) {
    if (lines.isEmpty) return const [];
    // Qty kecil & biasa; NAMA produk yang tebal (font bitmap tak punya bold ->
    // digambar dua kali dengan geser 1px). Kotak centang menempel SETELAH
    // nama (bukan di tepi kanan kertas).
    final qtyFont = img.arial24;
    final nameFont = img.arial24;
    final noteFont = img.arial14;

    var qtyW = 0;
    for (final l in lines) {
      qtyW = _max(qtyW, _textWidth(qtyFont, qtyLabel(l.qty)));
    }
    qtyW = qtyW.clamp(34, paperDots ~/ 4);
    final nameX = _margin + qtyW + _gap;
    final maxNameW = paperDots - _margin - _boxSize - _gap - nameX;

    debugBoxes.clear();
    var yBase = 0;
    final rows = <img.Image>[];
    for (final l in lines) {
      final indent = l.isVariant ? 14 : 0;
      final nameLines = wrap(
          nameFont,
          l.unit.isEmpty ? l.name : '${l.name} (${l.unit})',
          maxNameW - indent,
          3);
      final noteLines = (l.note == null || l.note!.trim().isEmpty)
          ? const <String>[]
          : wrap(noteFont, '* ${l.note!.trim()}', maxNameW - indent, 2);
      const nameLH = 28;
      const noteLH = 17;
      final textH = nameLines.length * nameLH + noteLines.length * noteLH;
      final h = _max(_boxSize, _max(textH, 40)) + _rowPadY * 2;
      final row = img.Image(width: paperDots, height: h, numChannels: 3);
      img.fill(row, color: img.ColorRgb8(255, 255, 255));
      final black = img.ColorRgb8(0, 0, 0);
      final blockH = _max(textH, _boxSize);

      // qty kecil, rata kanan di kolomnya, sejajar baris nama pertama.
      final q = qtyLabel(l.qty);
      final qw = _textWidth(qtyFont, q);
      img.drawString(row, q,
          font: qtyFont,
          x: _margin + qtyW - qw,
          y: _rowPadY + (blockH - textH) ~/ 2,
          color: black);

      var y = _rowPadY + (blockH - textH) ~/ 2;
      var widest = 0;
      for (final s in nameLines) {
        // Tebal palsu: gambar dua kali, geser 1px.
        img.drawString(row, s,
            font: nameFont, x: nameX + indent, y: y, color: black);
        img.drawString(row, s,
            font: nameFont, x: nameX + indent + 1, y: y, color: black);
        widest = _max(widest, _textWidth(nameFont, s) + 1);
        y += nameLH;
      }
      for (final s in noteLines) {
        img.drawString(row, s,
            font: noteFont, x: nameX + indent + _noteIndent, y: y, color: black);
        y += noteLH;
      }

      // Kotak: tepat setelah teks nama/catatan terlebar (bukan di tepi kanan).
      var textRight = nameX + indent + widest;
      for (final s in noteLines) {
        textRight =
            _max(textRight, nameX + indent + _textWidth(noteFont, s));
      }
      final boxX = (textRight + _gap + 6).clamp(0, paperDots - _margin - _boxSize);

      // Kotak centang persegi bersudut tumpul (rata tengah vertikal).
      final by = (h - _boxSize) ~/ 2;
      debugBoxes.add((x: boxX, y: yBase + by, size: _boxSize));
      img.drawRect(row,
          x1: boxX,
          y1: by,
          x2: boxX + _boxSize - 1,
          y2: by + _boxSize - 1,
          color: black,
          thickness: 3,
          radius: 9);
      if (l.checked) {
        // Tanda centang tebal di dalam kotak.
        img.drawLine(row,
            x1: boxX + 10,
            y1: by + 23,
            x2: boxX + 19,
            y2: by + 33,
            color: black,
            thickness: 4);
        img.drawLine(row,
            x1: boxX + 19,
            y1: by + 33,
            x2: boxX + 34,
            y2: by + 11,
            color: black,
            thickness: 4);
      }

      // Garis pemisah titik-titik di dasar baris.
      for (var x = _margin; x < paperDots - _margin; x += 6) {
        row.setPixelRgb(x, h - 1, 0, 0, 0);
        row.setPixelRgb(x + 1, h - 1, 0, 0, 0);
      }
      rows.add(row);
      yBase += h;
    }

    // Gabungkan jadi gambar-gambar setinggi <= chunkMax.
    final chunks = <img.Image>[];
    var group = <img.Image>[];
    var groupH = 0;
    void flushGroup() {
      if (group.isEmpty) return;
      final big = img.Image(width: paperDots, height: groupH, numChannels: 3);
      img.fill(big, color: img.ColorRgb8(255, 255, 255));
      var yy = 0;
      for (final r in group) {
        img.compositeImage(big, r, dstX: 0, dstY: yy);
        yy += r.height;
      }
      chunks.add(big);
      group = [];
      groupH = 0;
    }

    for (final r in rows) {
      if (groupH + r.height > chunkMax) flushGroup();
      group.add(r);
      groupH += r.height;
    }
    flushGroup();
    return chunks;
  }

  static int _max(int a, int b) => a > b ? a : b;
}
