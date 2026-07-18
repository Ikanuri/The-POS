import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Membuktikan migrasi schemaVersion 15 -> 16 benar-benar menambah kolom
/// `locally_modified` ke `products` (Item 40 — usulan harga/produk dari
/// device non-owner via sync LAN) saat DB lama (tanpa kolom itu) dibuka —
/// bukan sekadar compile.
void main() {
  test(
      'migrasi v15 -> v16: locally_modified (products) ditambah, default '
      'false, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig16_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── 1. Bangun DB "v15" mentah: products TANPA kolom locally_modified. ──
    final v15 = raw.sqlite3.open(path);
    v15.execute('''
      CREATE TABLE products(
        id TEXT PRIMARY KEY, name TEXT NOT NULL, product_group_id INTEGER,
        kode_produk TEXT, parent_product_id TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        marked_out_of_stock INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
    ''');
    v15.execute(
        "INSERT INTO products(id, name, created_at, updated_at) "
        "VALUES('p1','Gula',1700000000,1700000000)");

    final preCols = v15
        .select('PRAGMA table_info(products)')
        .map((r) => r['name'] as String)
        .toSet();
    expect(preCols, isNot(contains('locally_modified')),
        reason: 'prakondisi: DB v15 belum punya kolom locally_modified');
    v15.execute('PRAGMA user_version = 15;');
    v15.dispose();

    // ── 2. Buka via AppDatabase (schemaVersion 16) → onUpgrade(15,16) jalan.
    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final p = await (db.select(db.products)..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(p.locallyModified, isFalse,
        reason: 'kolom baru harus default false, bukan crash/null');
    expect(p.name, 'Gula', reason: 'data lama tetap utuh');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 16);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
