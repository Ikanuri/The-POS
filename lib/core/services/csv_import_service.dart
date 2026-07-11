import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

/// Hasil import CSV.
class CsvImportResult {
  const CsvImportResult({
    required this.imported,
    this.updated = 0,
    required this.duplicates,
    required this.noBarcode,
    required this.errors,
    this.sameNameDifferentUnit = 0,
  });
  final int imported;

  /// Baris yang cocok dengan produk yang SUDAH ada di database
  /// (barcode → SKU → nama+satuan) — harga jual/beli tier dasarnya
  /// diperbarui, TIDAK dibuat produk baru.
  final int updated;
  final int duplicates;
  final int noBarcode;
  final List<String> errors;

  /// Produk baru yang nama-nya sama dengan produk lain (beda satuan) tapi
  /// TIDAK digabung otomatis jadi satu produk multi-satuan — mis. export
  /// legacy "1 baris = 1 SKU per kemasan" (Griyo POS: "234 12" muncul
  /// sebagai baris terpisah untuk Slop & Pak). Info saja (bukan error) agar
  /// user tahu ada kandidat yang mungkin perlu digabung manual lewat Edit
  /// Produk, karena rasio konversi antar satuan tidak ada di CSV.
  final int sameNameDifferentUnit;
}

/// Import produk dari CSV.
///
/// Kolom yang dikenali (alias fleksibel, case-insensitive):
/// - nama / name / product_name / nama_produk
/// - kode / kode_produk / code / sku
/// - grup / group / kategori / category / group_name
/// - satuan / unit / uom / unit_type
/// - harga_jual / harga / sell_price / price
/// - harga_beli / cost / buy_price / cogs
/// - stok / stock / qty / quantity
/// - barcode / kode_barcode / ean / upc
class CsvImportService {
  CsvImportService._();

  static const _uuid = Uuid();

  static Future<CsvImportResult> importFromBytes({
    required List<int> bytes,
    required AppDatabase db,
  }) async {
    var content = utf8.decode(bytes, allowMalformed: true);
    if (content.startsWith('﻿')) content = content.substring(1);
    final rows = _parseCsv(content);
    if (rows.isEmpty) {
      return const CsvImportResult(imported: 0, duplicates: 0, noBarcode: 0, errors: []);
    }

    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    final dataRows = rows.skip(1).toList();

    int imported = 0;
    int updated = 0;
    int duplicates = 0;
    int noBarcode = 0;
    int sameNameDifferentUnit = 0;
    final errors = <String>[];
    final createdNames = <String>{};

    final unitTypes = await db.getAllUnitTypes();
    final groups = await db.getAllProductGroups();
    // getAllProductGroups() cuma yang sudah dinamai (dipakai UI dropdown) —
    // grup legacy 3-20 dari _seedDefaults sengaja TANPA nama ("diisi manual"
    // belakangan user), jadi untuk validasi ID mentah dari CSV pakai daftar
    // ID lengkap tanpa filter nama.
    final allGroupIds =
        (await db.select(db.productGroups).get()).map((g) => g.id).toSet();
    // Produk yang sudah ada — untuk mencocokkan baris CSV ke produk lama
    // (import ulang = update harga, bukan duplikasi katalog).
    final existingProducts = await db.searchProducts('');

    final seen = <String>{};

    String col(List<String> aliases, List<String> row) {
      for (final alias in aliases) {
        final idx = header.indexOf(alias);
        if (idx >= 0 && idx < row.length) return row[idx].trim();
      }
      return '';
    }

    // Netralkan CSV formula injection: buang prefix berbahaya di awal teks
    // agar tidak tereksekusi bila data diekspor & dibuka di Excel/Sheets.
    // `=` dan `@` selalu formula; `+`/`-` hanya berbahaya bila diikuti
    // angka/kurung (mis. "-2+3") — nama produk sah seperti "-Promo" atau
    // "A-1" tidak boleh ikut terpangkas.
    bool dangerousArithmetic(String s) =>
        s.length >= 2 && '0123456789.('.contains(s[1]);
    String sanitize(String s) {
      var out = s;
      while (out.isNotEmpty &&
          ('=@'.contains(out[0]) ||
              ('+-'.contains(out[0]) && dangerousArithmetic(out)))) {
        out = out.substring(1).trimLeft();
      }
      return out;
    }

    for (var rowIdx = 0; rowIdx < dataRows.length; rowIdx++) {
      final row = dataRows[rowIdx];
      if (row.isEmpty || row.every((c) => c.trim().isEmpty)) continue;

      final name = sanitize(col(
          ['nama', 'name', 'product_name', 'nama_produk', 'produk'], row));
      if (name.isEmpty) {
        errors.add('Baris ${rowIdx + 2}: nama produk kosong');
        continue;
      }

      final kode = sanitize(col(
          ['kode', 'kode_produk', 'code', 'sku', 'kode produk'], row));
      final grupName = col(
          ['grup', 'group', 'kategori', 'category', 'group_name', 'grup produk'],
          row);
      final satuanName = col(['satuan', 'unit', 'uom', 'unit_type'], row);
      final hargaJual = _parseIntPrice(col(
          ['harga_jual', 'harga', 'sell_price', 'price', 'harga jual'], row));
      final hargaBeli = _parseIntPrice(col(
          ['harga_beli', 'cost', 'buy_price', 'cogs', 'harga pokok'], row));
      final stok = double.tryParse(col(['stok', 'stock', 'qty', 'quantity'], row)) ?? 0;
      final barcodeStr = col(['barcode', 'kode_barcode', 'ean', 'upc'], row);

      // Resolve unit type. Export legacy (mis. Griyo POS) menaruh ID satuan
      // MENTAH di kolom ini (angka), bukan nama teks — ID-nya sengaja dibuat
      // sama dengan _kDefaultUnitTypes di app_database.dart. Kalau kolomnya
      // murni angka, pakai langsung sebagai ID (merge legacy 7/8 → 12);
      // kalau bukan angka, cocokkan sebagai nama seperti biasa.
      int unitTypeId = 1;
      if (satuanName.isNotEmpty) {
        final asId = int.tryParse(satuanName);
        if (asId != null) {
          final merged = (asId == 7 || asId == 8) ? 12 : asId;
          if (unitTypes.any((u) => u.id == merged)) unitTypeId = merged;
        } else {
          final matched = unitTypes.where(
            (u) => u.name.toLowerCase() == satuanName.toLowerCase(),
          ).firstOrNull;
          if (matched != null) unitTypeId = matched.id;
        }
      }

      // Resolve group ID — sama seperti satuan, export legacy pakai ID
      // mentah (grup_produk 3-20 di _seedDefaults, tanpa nama).
      int? productGroupId;
      if (grupName.isNotEmpty) {
        final asId = int.tryParse(grupName);
        if (asId != null) {
          if (allGroupIds.contains(asId)) productGroupId = asId;
        } else {
          final matched = groups.where(
            (g) => g.name?.toLowerCase() == grupName.toLowerCase(),
          ).firstOrNull;
          productGroupId = matched?.id;
        }
      }

      // Dedup check — prioritaskan barcode/kode produk (identitas SKU asli)
      // di atas nama+satuan. Nama+satuan saja tidak cukup: dua SKU berbeda
      // (barcode/harga beda) bisa punya nama+satuan yang sama persis (mis.
      // "Sedap Goreng" per Dos dari 2 supplier), dan itu BUKAN duplikat.
      // Fallback ke nama+satuan hanya dipakai kalau baris ini benar-benar
      // tidak punya barcode maupun kode produk sama sekali.
      final dedupKey = barcodeStr.isNotEmpty
          ? 'bc|$barcodeStr'
          : (kode.isNotEmpty
              ? 'kode|$kode'
              : '${name.toLowerCase()}|$unitTypeId');
      if (seen.contains(dedupKey)) {
        duplicates++;
        continue;
      }
      seen.add(dedupKey);

      // ── Cocokkan ke produk yang SUDAH ada (barcode → SKU → nama+satuan).
      // Kalau ketemu: perbarui harga jual/beli tier dasar produk lama —
      // JANGAN membuat produk baru. Tanpa ini, import ulang file yang sama
      // menduplikasi seluruh katalog DAN memindahkan barcode dari produk
      // lama ke duplikat baru (saveProduct menghapus baris barcode manapun
      // yang memegang nilai sama demi UNIQUE), sehingga scan barcode mulai
      // menambah produk duplikat tanpa riwayat stok.
      try {
        final matchedUnitId = await _matchExistingUnit(
          db: db,
          existingProducts: existingProducts,
          name: name,
          kode: kode,
          barcodeStr: barcodeStr,
          unitTypeId: unitTypeId,
        );
        if (matchedUnitId != null) {
          await _updateBaseTier(
            db: db,
            productUnitId: matchedUnitId,
            price: hargaJual,
            costPrice: hargaBeli,
          );
          updated++;
          continue;
        }
      } catch (e) {
        errors.add('Baris ${rowIdx + 2} ($name): $e');
        continue;
      }

      if (barcodeStr.isEmpty) noBarcode++;

      // Info non-blocking: nama sama dengan produk lain (satuan beda) tapi
      // tidak digabung otomatis — lihat dokumentasi sameNameDifferentUnit.
      final nameLower = name.toLowerCase();
      if (createdNames.contains(nameLower) ||
          existingProducts.any((p) => p.name.toLowerCase() == nameLower)) {
        sameNameDifferentUnit++;
      }
      createdNames.add(nameLower);

      final productId = _uuid.v4();
      final unitId = _uuid.v4();
      final now = DateTime.now();

      // Required fields in .insert() are plain Dart types (no Value wrapper).
      // Optional/nullable/with-default fields use Value().
      final product = ProductsCompanion.insert(
        id: productId,
        name: name,
        kodeProduk: Value(kode.isEmpty ? null : kode),
        productGroupId: Value(productGroupId),
        updatedAt: Value(now),
      );

      // isBaseUnit: true — produk hasil import selalu cuma 1 satuan, jadi
      // satuan itu SELALU satuan dasarnya (sama seperti tambah produk manual
      // di produk_form_screen.dart). Tanpa ini, OrderPageService (katalog
      // HTML) yang mensyaratkan ada satuan isBaseUnit (tanpa fallback, beda
      // dari kasir/edit produk/dsb yang semua punya fallback `?? units.first`)
      // akan melewati produk ini sama sekali dari katalog.
      final unit = ProductUnitsCompanion.insert(
        id: unitId,
        productId: productId,
        unitTypeId: Value(unitTypeId),
        isBaseUnit: const Value(true),
      );

      final tiers = <PriceTiersCompanion>[
        PriceTiersCompanion.insert(
          id: _uuid.v4(),
          productUnitId: unitId,
          price: hargaJual,
          costPrice: Value(hargaBeli),
        ),
      ];

      final barcodes = barcodeStr.isNotEmpty
          ? [
              ProductBarcodesCompanion.insert(
                id: _uuid.v4(),
                productUnitId: unitId,
                barcode: barcodeStr,
                isPrimary: const Value(true),
              )
            ]
          : <ProductBarcodesCompanion>[];

      try {
        await db.saveProduct(
          product: product,
          units: [unit],
          tiersByUnitTempId: {unitId: tiers},
          barcodesByUnitTempId: {unitId: barcodes},
        );

        if (stok > 0) {
          await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
            id: _uuid.v4(),
            productUnitId: unitId,
            type: 'opening',
            qtyChange: stok,
            stockAfter: stok,
            note: const Value('Import CSV'),
            createdAt: Value(now),
          ));
        }

        imported++;
      } catch (e) {
        errors.add('Baris ${rowIdx + 2} ($name): $e');
      }
    }

    return CsvImportResult(
      imported: imported,
      updated: updated,
      duplicates: duplicates,
      noBarcode: noBarcode,
      errors: errors,
      sameNameDifferentUnit: sameNameDifferentUnit,
    );
  }

  /// Cari satuan produk lama yang cocok dengan baris CSV, prioritas:
  /// 1. barcode (identitas terkuat), 2. SKU/kode produk, 3. nama+tipe satuan.
  /// Untuk match nama, tipe satuan HARUS sama — nama sama dengan satuan
  /// berbeda dianggap produk lain (konsisten dengan dedupKey nama|satuan).
  static Future<String?> _matchExistingUnit({
    required AppDatabase db,
    required List<Product> existingProducts,
    required String name,
    required String kode,
    required String barcodeStr,
    required int unitTypeId,
  }) async {
    if (barcodeStr.isNotEmpty) {
      final bc = await db.lookupBarcode(barcodeStr);
      if (bc != null) return bc.productUnitId;
    }

    Product? product;
    if (kode.isNotEmpty) {
      final kodeLower = kode.toLowerCase();
      product = existingProducts
          .where((p) => p.kodeProduk?.toLowerCase() == kodeLower)
          .firstOrNull;
    }
    var matchedByName = false;
    if (product == null) {
      final nameLower = name.toLowerCase();
      product = existingProducts
          .where((p) => p.name.toLowerCase() == nameLower)
          .firstOrNull;
      matchedByName = product != null;
    }
    if (product == null) return null;

    final units = await db.getProductUnits(product.id);
    if (units.isEmpty) return null;
    final sameType =
        units.where((u) => u.unitTypeId == unitTypeId).firstOrNull;
    if (sameType != null) return sameType.id;
    // Nama sama tapi tidak ada satuan bertipe sama → bukan produk yang sama.
    if (matchedByName) return null;
    // SKU cocok = identitas kuat → pakai satuan dasar.
    return (units.where((u) => u.isBaseUnit).firstOrNull ?? units.first).id;
  }

  /// Perbarui harga jual/beli tier dasar (minQty = 1) sebuah satuan; buat
  /// tier baru bila belum ada. Stok TIDAK disentuh.
  static Future<void> _updateBaseTier({
    required AppDatabase db,
    required String productUnitId,
    required int price,
    required int costPrice,
  }) async {
    final tiers = await db.getPriceTiers(productUnitId);
    final base = tiers.where((t) => t.minQty == 1).firstOrNull;
    if (base != null) {
      await (db.update(db.priceTiers)..where((t) => t.id.equals(base.id)))
          .write(PriceTiersCompanion(
        price: Value(price),
        costPrice: Value(costPrice),
      ));
    } else {
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: _uuid.v4(),
            productUnitId: productUnitId,
            minQty: const Value(1),
            price: price,
            costPrice: Value(costPrice),
            createdAt: Value(DateTime.now()),
          ));
    }
  }

  /// Parse harga dari berbagai format: "10000", "10.000" (titik ribuan),
  /// "10,000" (koma ribuan barat). Mengembalikan 0 jika tidak dapat di-parse.
  static int _parseIntPrice(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 0;
    final direct = int.tryParse(s);
    if (direct != null) return direct;
    final noThousands = s.replaceAll('.', '');
    final noDots = int.tryParse(noThousands);
    if (noDots != null) return noDots;
    final noCommas = s.replaceAll(',', '');
    final noCommaInt = int.tryParse(noCommas);
    if (noCommaInt != null) return noCommaInt;
    return (double.tryParse(s) ?? 0).round();
  }

  /// Exposed for testing.
  static List<List<String>> testParseCsv(String content) => _parseCsv(content);

  /// Parser CSV minimal: handle quoted fields yang mengandung koma DAN
  /// newline (RFC 4180) — pemindaian karakter atas seluruh isi file, bukan
  /// per-baris, supaya field ber-kutip multi-baris tidak terpotong.
  static List<List<String>> _parseCsv(String content) {
    final src = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final delimiter = _detectDelimiter(src);
    final result = <List<String>>[];
    var fields = <String>[];
    var field = StringBuffer();
    var inQuote = false;
    var rowHasContent = false;

    void endField() {
      fields.add(field.toString());
      field = StringBuffer();
    }

    void endRow() {
      endField();
      if (rowHasContent || fields.any((f) => f.trim().isNotEmpty)) {
        result.add(fields);
      }
      fields = <String>[];
      rowHasContent = false;
    }

    for (var i = 0; i < src.length; i++) {
      final c = src[i];
      if (c == '"') {
        if (inQuote && i + 1 < src.length && src[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuote = !inQuote;
        }
        rowHasContent = true;
      } else if (c == delimiter && !inQuote) {
        endField();
      } else if (c == '\n' && !inQuote) {
        endRow();
      } else {
        field.write(c);
        rowHasContent = true;
      }
    }
    if (field.isNotEmpty || fields.isNotEmpty) endRow();
    return result;
  }

  /// Deteksi pemisah kolom dari baris header: `,` (default/Excel EN) atau
  /// `;` (umum untuk export locale Indonesia, mis. Griyo POS). Dihitung dari
  /// baris pertama saja — cukup untuk header, tidak perlu quote-aware karena
  /// header jarang berisi field ber-kutip.
  static String _detectDelimiter(String src) {
    final firstLine = src.split('\n').first;
    final semicolons = ';'.allMatches(firstLine).length;
    final commas = ','.allMatches(firstLine).length;
    return semicolons > commas ? ';' : ',';
  }
}
