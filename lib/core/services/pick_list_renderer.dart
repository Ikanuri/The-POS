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
    final qtyFont = img.arial48;
    final nameFont = img.arial24;
    final noteFont = img.arial14;

    var qtyW = 0;
    for (final l in lines) {
      qtyW = _max(qtyW, _textWidth(qtyFont, qtyLabel(l.qty)));
    }
    // Batasi supaya kolom nama tetap lega di kertas 58mm.
    qtyW = qtyW.clamp(54, paperDots ~/ 3);
    final nameX = _margin + qtyW + _gap;
    final boxX = paperDots - _margin - _boxSize;
    final nameW = boxX - _gap - nameX;

    final rows = <img.Image>[];
    for (final l in lines) {
      final indent = l.isVariant ? 14 : 0;
      final nameLines = wrap(
          nameFont,
          l.unit.isEmpty ? l.name : '${l.name} (${l.unit})',
          nameW - indent,
          3);
      final noteLines = (l.note == null || l.note!.trim().isEmpty)
          ? const <String>[]
          : wrap(noteFont, '* ${l.note!.trim()}', nameW - indent, 2);
      const nameLH = 28;
      const noteLH = 17;
      final textH = nameLines.length * nameLH + noteLines.length * noteLH;
      final h = _max(_boxSize, _max(textH, 52)) + _rowPadY * 2;
      final row = img.Image(width: paperDots, height: h, numChannels: 3);
      img.fill(row, color: img.ColorRgb8(255, 255, 255));
      final black = img.ColorRgb8(0, 0, 0);

      // qty besar, rata kanan di kolomnya, sejajar baris nama pertama.
      final q = qtyLabel(l.qty);
      final qw = _textWidth(qtyFont, q);
      img.drawString(row, q,
          font: qtyFont,
          x: _margin + qtyW - qw,
          y: _rowPadY + (_max(textH, _boxSize) - 48) ~/ 2,
          color: black);

      var y = _rowPadY + (_max(textH, _boxSize) - textH) ~/ 2;
      for (final s in nameLines) {
        img.drawString(row, s,
            font: nameFont, x: nameX + indent, y: y, color: black);
        y += nameLH;
      }
      for (final s in noteLines) {
        img.drawString(row, s,
            font: noteFont, x: nameX + indent + _noteIndent, y: y, color: black);
        y += noteLH;
      }

      // Kotak centang persegi bersudut tumpul (rata tengah vertikal).
      final by = (h - _boxSize) ~/ 2;
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
