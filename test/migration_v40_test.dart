import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Migrasi v39 -> v40 (Fase B "Kategori Harga"): tabel `price_categories`
/// dibuat, dan 4 kolom baru NULLABLE ditambah ke `alt_prices`
/// (`price_category_id`, `margin_anchor`, `margin_type`, `margin_value`) —
/// baris alt_prices LAMA (tanpa kategori) tetap valid apa adanya (semua
/// kolom baru NULL), tidak crash.
void main() {
  test(
      'migrasi v39 -> v40: price_categories dibuat, alt_prices dapat 4 '
      'kolom nullable, baris lama tidak berubah', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig40_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    final v39 = raw.sqlite3.open(path);
    v39.execute('PRAGMA user_version = 39;');
    v39.execute('''
      CREATE TABLE product_units (
        id TEXT NOT NULL PRIMARY KEY,
        product_id TEXT NOT NULL
      );
    ''');
    v39.execute('''
      CREATE TABLE alt_prices (
        id TEXT NOT NULL PRIMARY KEY,
        product_unit_id TEXT NOT NULL,
        label TEXT NOT NULL,
        price INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      );
    ''');
    v39.execute("INSERT INTO product_units (id, product_id) "
        "VALUES ('u1', 'p1');");
    v39.execute("INSERT INTO alt_prices "
        "(id, product_unit_id, label, price, created_at, sort_order) "
        "VALUES ('ap-lama', 'u1', 'Harga Toko A', 5000, 1000, 0);");

    final before = v39.select("PRAGMA table_info(alt_prices)");
    expect(before.any((r) => r['name'] == 'price_category_id'), isFalse,
        reason: 'prakondisi: DB v39 belum punya kolom price_category_id');
    final beforeTables =
        v39.select("SELECT name FROM sqlite_master WHERE type='table'");
    expect(beforeTables.map((r) => r['name']), isNot(contains('price_categories')),
        reason: 'prakondisi: tabel price_categories belum ada di v39');
    v39.dispose();

    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final row = await (db.select(db.altPrices)
          ..where((t) => t.id.equals('ap-lama')))
        .getSingle();
    expect(row.priceCategoryId, isNull,
        reason: 'baris alt_prices lama tidak punya kategori — tetap NULL');
    expect(row.marginAnchor, isNull);
    expect(row.marginType, isNull);
    expect(row.marginValue, isNull);
    expect(row.label, 'Harga Toko A', reason: 'data lama lain tidak tersentuh');
    expect(row.price, 5000);

    // Tabel baru harus benar-benar bisa dipakai (bukan cuma "ada").
    final categories = await db.select(db.priceCategories).get();
    expect(categories, isEmpty);

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 41);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
