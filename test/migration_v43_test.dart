import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Migrasi v42 -> v43: kolom `price_categories.name` jadi NULLABLE.
///
/// Bug nyata yang mendasari (lihat dok `PriceCategories`/`deletePriceCategory`
/// di `app_database.dart`): sebelum migrasi ini, `name` NOT NULL memaksa
/// `deletePriceCategory` HARD DELETE barisnya — padahal sync satu-arah
/// host->klien (`dumpSince`/`masterData`) tidak pernah propagate DELETE
/// fisik, jadi penghapusan kategori di host tidak akan pernah sampai ke
/// klien. `alterTable` (TableMigration) merekonstruksi tabel dgn definisi
/// Dart TERKINI (`name` nullable) — baris lama (semua non-null) disalin
/// apa adanya, TIDAK ada yang hilang/berubah.
void main() {
  test(
      'migrasi v42 -> v43: price_categories.name jadi nullable, data lama '
      'utuh, bisa ditombstone (name=null) setelah migrasi', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig43_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    final v42 = raw.sqlite3.open(path);
    v42.execute('PRAGMA user_version = 42;');
    v42.execute('''
      CREATE TABLE price_categories(
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      );
    ''');
    v42.execute("INSERT INTO price_categories (id, name, sort_order, "
        "created_at) VALUES ('c1', 'Grosir', 0, 1700000000);");

    final preCol = v42
        .select("PRAGMA table_info(price_categories)")
        .firstWhere((r) => r['name'] == 'name');
    expect(preCol['notnull'], 1,
        reason: 'prakondisi: DB v42 punya name NOT NULL');
    v42.dispose();

    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final row = await (db.select(db.priceCategories)
          ..where((t) => t.id.equals('c1')))
        .getSingle();
    expect(row.name, 'Grosir', reason: 'data lama tidak tersentuh');
    expect(row.sortOrder, 0);

    final postCol = (await db
            .customSelect("PRAGMA table_info(price_categories)")
            .get())
        .map((r) => r.data)
        .firstWhere((r) => r['name'] == 'name');
    expect(postCol['notnull'], 0,
        reason: 'kolom name HARUS jadi nullable setelah migrasi v43');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 43);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
