// PLAN Item 90 tahap 5 — "Tempel hasil AI": AI dipakai DI LUAR aplikasi
// (Claude/Meta AI, prompt universal). Aplikasi hanya punya SATU parser tetap
// + validator di file ini. Keputusan desain (lihat PLAN.md Item 90):
//  * AI TIDAK boleh mengeluarkan kode — keluarannya DATA (JSON).
//  * AI hanya MEMBACA; aplikasi yang MENGHITUNG (HPP/PPN/diskon) & semua
//    hitungan AI diperlakukan sbg pembanding (validasi), bukan sumber.
//  * CSV produk minimal (TANPA harga jual/HPP) ikut dilampirkan ke AI supaya
//    AI bisa menyarankan `product_unit_id` — tetap SARAN yang harus
//    dikonfirmasi pengguna (aturan "tidak fuzzy otomatis").
// Format mengikuti faktur nyata (contoh Indomarco): PPN hanya di total,
// potongan per baris (% & Rp), kuantitas dua bagian ("5 0" = 5 besar + 0
// kecil) dgn isi per satuan besar ("4 /ZAK").
import 'dart:convert';

/// Versi format JSON — naikkan bila struktur berubah (parser menerima versi
/// lama selama masih kompatibel).
const kPurchaseAiFormatVersion = 1;

/// Satu baris faktur hasil baca AI (sudah dinormalisasi).
class AiInvoiceLine {
  AiInvoiceLine({
    required this.name,
    required this.unit,
    required this.qty,
    required this.unitPrice,
    required this.discount,
    this.lineNet,
    this.productUnitId,
    this.confident = true,
    this.problems = const [],
  });

  /// Nama barang apa adanya di faktur.
  final String name;

  /// Satuan besar apa adanya di faktur (mis. "ZAK", "CAR").
  final String unit;

  /// Jumlah dalam satuan besar (besar + kecil/isi).
  final double qty;

  /// Harga per satuan besar apa adanya di faktur (0 = tidak terbaca).
  final int unitPrice;

  /// Potongan rupiah baris (dari kolom Rp, atau dihitung dari %).
  final int discount;

  /// "Jumlah bersih" yang TERCETAK di faktur — pembanding validasi.
  final int? lineNet;

  /// Saran AI dari CSV produk (harus dikonfirmasi pengguna).
  final String? productUnitId;

  /// AI menandai baris ini terbaca yakin.
  final bool confident;

  /// Masalah validasi (kosong = aman).
  final List<String> problems;
}

/// Satu faktur hasil baca AI.
class AiInvoice {
  AiInvoice({
    required this.lines,
    this.invoiceNo,
    this.invoiceDate,
    this.supplier,
    this.priceIncludesTax = true,
    this.invoiceDiscount = 0,
    this.printedTotal,
    this.printedTax,
    this.problems = const [],
  });

  final List<AiInvoiceLine> lines;
  final String? invoiceNo;
  final DateTime? invoiceDate;
  final String? supplier;
  final bool priceIncludesTax;
  final int invoiceDiscount;

  /// Total yang dibayar & total PPN TERCETAK — pembanding validasi.
  final int? printedTotal;
  final int? printedTax;

  /// Masalah validasi tingkat faktur.
  final List<String> problems;
}

/// Hasil parse: daftar faktur, atau [error] bila teks tidak bisa dibaca.
class AiParseResult {
  AiParseResult({this.invoices = const [], this.error});
  final List<AiInvoice> invoices;
  final String? error;
  bool get ok => error == null;
}

/// Prompt universal utk AI (Claude/Meta AI dkk). [taxRate] tarif PPN toko.
String buildPurchaseAiPrompt({double taxRate = 11}) {
  final rate = taxRate % 1 == 0 ? taxRate.toInt().toString() : '$taxRate';
  return '''Kamu membantu toko grosir membaca FAKTUR PEMBELIAN dari supplier.
Lampiran: foto faktur (boleh lebih dari satu) dan file CSV daftar produk toko
(kolom: product_unit_id, nama_produk, satuan, isi_dalam_satuan_dasar, satuan_dasar).

TUGAS: baca faktur APA ADANYA, lalu balas HANYA dengan satu blok JSON
(tanpa penjelasan lain) mengikuti format di bawah.

ATURAN PENTING:
1. JANGAN menghitung, membulatkan, atau menebak. Salin angka persis seperti
   tercetak. Kalau tidak terbaca jelas, isi null dan set "yakin": false.
2. Angka ditulis sebagai angka polos tanpa pemisah ribuan
   (contoh: 167621, bukan "167,621" atau "167.621").
3. Kuantitas sering tercetak dua bagian, mis. "5 0" = 5 satuan besar + 0
   satuan kecil, dan kolom satuan "4 /ZAK" = isi 4 per ZAK. Isi "qty_besar",
   "qty_kecil", "satuan", dan "isi" sesuai yang tercetak.
4. "potongan_persen" & "potongan_rupiah" diambil dari kolom potongan per
   baris (0 bila kosong). "jumlah_bersih" = nilai baris yang tercetak.
5. "harga_termasuk_ppn": true bila faktur menyatakan harga sudah termasuk
   PPN (umumnya tertulis "Harga sudah termasuk PPN"). Tarif PPN toko: $rate%.
6. "product_unit_id": cocokkan barang ke CSV produk HANYA bila jelas sama
   (merek, varian, ukuran, DAN satuan sama). Kalau ragu, isi null.
   Jangan pernah mengarang id yang tidak ada di CSV.
7. Satu faktur = satu objek di "faktur". Beberapa foto faktur = beberapa objek.
8. JANGAN menulis kode program. Keluaran hanya data JSON.

FORMAT:
{
  "versi": $kPurchaseAiFormatVersion,
  "faktur": [
    {
      "nomor": "124256-RPS",
      "tanggal": "2026-09-28",
      "supplier": "PT Indomarco Adi Prima",
      "harga_termasuk_ppn": true,
      "potongan_faktur": 0,
      "total_bayar": 4983779,
      "total_ppn": 493888,
      "baris": [
        {
          "nama": "TPY5KGIS14-Terigu Payung 5 kg x 4 Pa",
          "satuan": "ZAK",
          "isi": 4,
          "qty_besar": 5,
          "qty_kecil": 0,
          "harga_satuan": 167621,
          "potongan_persen": 0,
          "potongan_rupiah": 0,
          "jumlah_bersih": 838106,
          "product_unit_id": null,
          "yakin": true
        }
      ]
    }
  ]
}''';
}

/// Satu baris CSV produk utk dilampirkan ke AI.
typedef AiCsvProductRow = ({
  String productUnitId,
  String productName,
  String unitName,
  double ratioToBase,
  String baseUnitName,
});

/// CSV produk MINIMAL (tanpa harga jual/HPP — privasi modal toko).
String buildPurchaseAiCsv(List<AiCsvProductRow> rows) {
  String esc(String v) {
    final needs = v.contains(',') || v.contains('"') || v.contains('\n');
    final t = v.replaceAll('"', '""');
    return needs ? '"$t"' : t;
  }

  String num(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();
  final b = StringBuffer(
      'product_unit_id,nama_produk,satuan,isi_dalam_satuan_dasar,satuan_dasar\n');
  for (final r in rows) {
    b.writeln([
      esc(r.productUnitId),
      esc(r.productName),
      esc(r.unitName),
      num(r.ratioToBase),
      esc(r.baseUnitName),
    ].join(','));
  }
  return b.toString();
}

/// Ambil blok JSON dari balasan AI yang mungkin dibungkus kalimat/pagar kode.
String? extractJsonBlock(String text) {
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  final src = fence != null ? fence.group(1)! : text;
  final start = src.indexOf('{');
  final end = src.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  return src.substring(start, end + 1);
}

/// Angka toleran: num, atau string berformat Indonesia/Inggris
/// ("167.621", "167,621", "1.234,5", "Rp 5.000"). null bila tak terbaca.
double? parseLooseNumber(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is! String) return null;
  var t = v.replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (t.isEmpty || t == '-') return null;
  final hasDot = t.contains('.');
  final hasComma = t.contains(',');
  if (hasDot && hasComma) {
    // Pemisah desimal = yang muncul TERAKHIR.
    if (t.lastIndexOf(',') > t.lastIndexOf('.')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else {
      t = t.replaceAll(',', '');
    }
  } else if (hasDot || hasComma) {
    final sep = hasDot ? '.' : ',';
    final parts = t.split(sep);
    // "167.621" / "167,621" (kelompok 3 digit) = ribuan; "12,5" = desimal.
    final thousands = parts.length > 1 &&
        parts.skip(1).every((p) => p.length == 3) &&
        parts.first.isNotEmpty;
    t = thousands ? parts.join() : t.replaceAll(',', '.');
  }
  return double.tryParse(t);
}

DateTime? _parseDate(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  final iso = DateTime.tryParse(v.trim());
  if (iso != null) return iso;
  final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})$')
      .firstMatch(v.trim());
  if (m == null) return null;
  var y = int.parse(m.group(3)!);
  if (y < 100) y += 2000;
  return DateTime(y, int.parse(m.group(2)!), int.parse(m.group(1)!));
}

/// Toleransi selisih pembulatan (Rp) saat membandingkan angka tercetak.
const _kTolerance = 2;

/// Parse balasan AI. [knownUnitIds] = id satuan yang ADA di DB (saran AI di
/// luar daftar ini dibuang & ditandai). [taxRate] utk validasi total PPN.
AiParseResult parsePurchaseAiResponse(
  String text, {
  required Set<String> knownUnitIds,
  double taxRate = 11,
}) {
  final block = extractJsonBlock(text);
  if (block == null) {
    return AiParseResult(
        error: 'Tidak menemukan data JSON. Pastikan menyalin SELURUH balasan '
            'AI.');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(block);
  } catch (_) {
    return AiParseResult(
        error: 'Format JSON rusak/terpotong. Minta AI mengulang balasannya.');
  }
  List<Object?> rawInvoices;
  if (decoded is Map && decoded['faktur'] is List) {
    rawInvoices = decoded['faktur'] as List;
  } else if (decoded is Map && decoded['baris'] is List) {
    rawInvoices = [decoded];
  } else {
    return AiParseResult(error: 'JSON tidak berisi "faktur".');
  }
  final invoices = <AiInvoice>[];
  for (final raw in rawInvoices) {
    if (raw is! Map) continue;
    final inc = raw['harga_termasuk_ppn'];
    final includesTax = inc is bool ? inc : true;
    final lines = <AiInvoiceLine>[];
    var sumNet = 0;
    for (final rl in (raw['baris'] is List ? raw['baris'] as List : const [])) {
      if (rl is! Map) continue;
      final problems = <String>[];
      final name = (rl['nama'] ?? '').toString().trim();
      final unit = (rl['satuan'] ?? '').toString().trim();
      final isi = parseLooseNumber(rl['isi']) ?? 0;
      final big = parseLooseNumber(rl['qty_besar']) ??
          parseLooseNumber(rl['qty']) ??
          0;
      final small = parseLooseNumber(rl['qty_kecil']) ?? 0;
      var qty = big;
      if (small > 0) {
        if (isi > 0) {
          qty = big + small / isi;
        } else {
          problems.add('Ada qty kecil ($small) tapi isi per satuan tidak '
              'terbaca');
        }
      }
      final price = (parseLooseNumber(rl['harga_satuan']) ?? 0).round();
      if (price <= 0) problems.add('Harga satuan tidak terbaca');
      if (qty <= 0) problems.add('Jumlah tidak terbaca');
      final gross = (qty * price).round();
      final pct = parseLooseNumber(rl['potongan_persen']) ?? 0;
      final rp = (parseLooseNumber(rl['potongan_rupiah']) ?? 0).round();
      final discount = rp > 0 ? rp : (gross * pct / 100).round();
      final netPrinted = parseLooseNumber(rl['jumlah_bersih'])?.round();
      final net = gross - discount;
      if (netPrinted != null &&
          price > 0 &&
          (netPrinted - net).abs() > _kTolerance) {
        problems.add('Jumlah bersih tercetak Rp$netPrinted beda dgn hitungan '
            'Rp$net — cek jumlah/harga/potongan');
      }
      sumNet += net;
      var unitId = rl['product_unit_id'] is String
          ? (rl['product_unit_id'] as String).trim()
          : null;
      if (unitId != null && unitId.isEmpty) unitId = null;
      if (unitId != null && !knownUnitIds.contains(unitId)) {
        problems.add('Saran produk dari AI tidak dikenal — pilih manual');
        unitId = null;
      }
      final yakin = rl['yakin'];
      lines.add(AiInvoiceLine(
        name: name,
        unit: unit,
        qty: qty,
        unitPrice: price,
        discount: discount,
        lineNet: netPrinted,
        productUnitId: unitId,
        confident: yakin is bool ? yakin : true,
        problems: problems,
      ));
    }
    final invDiscount =
        (parseLooseNumber(raw['potongan_faktur']) ?? 0).round();
    final printedTotal = parseLooseNumber(raw['total_bayar'])?.round();
    final printedTax = parseLooseNumber(raw['total_ppn'])?.round();
    final problems = <String>[];
    if (lines.isEmpty) problems.add('Faktur tanpa baris barang');
    final computedTotal = sumNet - invDiscount;
    if (printedTotal != null &&
        (printedTotal - computedTotal).abs() > _kTolerance * lines.length) {
      problems.add('Total faktur tercetak Rp$printedTotal beda dgn jumlah '
          'baris Rp$computedTotal — ada baris yang salah baca/terlewat');
    }
    if (printedTax != null && printedTotal != null && includesTax) {
      final expectedTax =
          (printedTotal - printedTotal / (1 + taxRate / 100)).round();
      if ((printedTax - expectedTax).abs() > _kTolerance * 10) {
        problems.add('PPN tercetak Rp$printedTax bukan $taxRate% dari total '
            '(harusnya ±Rp$expectedTax) — kemungkinan ada barang bebas PPN');
      }
    }
    invoices.add(AiInvoice(
      lines: lines,
      invoiceNo: (raw['nomor'] as Object?)?.toString().trim(),
      invoiceDate: _parseDate(raw['tanggal']),
      supplier: (raw['supplier'] as Object?)?.toString().trim(),
      priceIncludesTax: includesTax,
      invoiceDiscount: invDiscount,
      printedTotal: printedTotal,
      printedTax: printedTax,
      problems: problems,
    ));
  }
  if (invoices.isEmpty) {
    return AiParseResult(error: 'Tidak ada faktur yang terbaca.');
  }
  return AiParseResult(invoices: invoices);
}
