import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

/// Hasil import CSV.
class CsvImportResult {
  const CsvImportResult({
    required this.imported,
    required this.duplicates,
    required this.noBarcode,
    required this.errors,
  });
  final int imported;
  final int duplicates;
  final int noBarcode;
  final List<String> errors;
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
    final content = String.fromCharCodes(bytes);
    final rows = _parseCsv(content);
    if (rows.isEmpty) {
      return const CsvImportResult(imported: 0, duplicates: 0, noBarcode: 0, errors: []);
    }

    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    final dataRows = rows.skip(1).toList();

    int imported = 0;
    int duplicates = 0;
    int noBarcode = 0;
    final errors = <String>[];

    final unitTypes = await db.getAllUnitTypes();
    final groups = await db.getAllProductGroups();

    final seen = <String>{};

    String col(List<String> aliases, List<String> row) {
      for (final alias in aliases) {
        final idx = header.indexOf(alias);
        if (idx >= 0 && idx < row.length) return row[idx].trim();
      }
      return '';
    }

    for (var rowIdx = 0; rowIdx < dataRows.length; rowIdx++) {
      final row = dataRows[rowIdx];
      if (row.isEmpty || row.every((c) => c.trim().isEmpty)) continue;

      final name = col(['nama', 'name', 'product_name', 'nama_produk'], row);
      if (name.isEmpty) {
        errors.add('Baris ${rowIdx + 2}: nama produk kosong');
        continue;
      }

      final kode = col(['kode', 'kode_produk', 'code', 'sku'], row);
      final grupName = col(['grup', 'group', 'kategori', 'category', 'group_name'], row);
      final satuanName = col(['satuan', 'unit', 'uom', 'unit_type'], row);
      final hargaJual = int.tryParse(col(['harga_jual', 'harga', 'sell_price', 'price'], row)) ?? 0;
      final hargaBeli = int.tryParse(col(['harga_beli', 'cost', 'buy_price', 'cogs'], row)) ?? 0;
      final stok = double.tryParse(col(['stok', 'stock', 'qty', 'quantity'], row)) ?? 0;
      final barcodeStr = col(['barcode', 'kode_barcode', 'ean', 'upc'], row);

      // Resolve unit type — merge ID 7/8 → 1
      int unitTypeId = 1;
      if (satuanName.isNotEmpty) {
        final matched = unitTypes.where(
          (u) => u.name.toLowerCase() == satuanName.toLowerCase(),
        ).firstOrNull;
        if (matched != null) {
          unitTypeId = (matched.id == 7 || matched.id == 8) ? 1 : matched.id;
        }
      }

      // Resolve group ID
      int? productGroupId;
      if (grupName.isNotEmpty) {
        final matched = groups.where(
          (g) => g.name?.toLowerCase() == grupName.toLowerCase(),
        ).firstOrNull;
        productGroupId = matched?.id;
      }

      // Dedup check
      final dedupKey = '${name.toLowerCase()}|$unitTypeId';
      if (seen.contains(dedupKey)) {
        duplicates++;
        continue;
      }
      seen.add(dedupKey);

      if (barcodeStr.isEmpty) noBarcode++;

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

      final unit = ProductUnitsCompanion.insert(
        id: unitId,
        productId: productId,
        unitTypeId: Value(unitTypeId),
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
      duplicates: duplicates,
      noBarcode: noBarcode,
      errors: errors,
    );
  }

  /// Exposed for testing.
  static List<List<String>> testParseCsv(String content) => _parseCsv(content);

  /// Parser CSV minimal: handle quoted fields yang mengandung koma.
  static List<List<String>> _parseCsv(String content) {
    final lines = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final result = <List<String>>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      result.add(_parseLine(line));
    }
    return result;
  }

  static List<String> _parseLine(String line) {
    final fields = <String>[];
    var field = StringBuffer();
    var inQuote = false;

    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuote && i + 1 < line.length && line[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuote = !inQuote;
        }
      } else if (c == ',' && !inQuote) {
        fields.add(field.toString());
        field = StringBuffer();
      } else {
        field.write(c);
      }
    }
    fields.add(field.toString());
    return fields;
  }
}
