import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Membuktikan migrasi schemaVersion 13 -> 14 benar-benar menambah kolom
/// `marked_out_of_stock` ke `products` (Item 25a — tanda stok habis
/// manual) saat DB lama (tanpa kolom itu) dibuka — bukan sekadar compile.
void main() {
  test(
      'migrasi v13 -> v14: kolom marked_out_of_stock ditambah ke products, '
      'default false, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig14_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── 1. Bangun DB "v13" mentah: products TANPA kolom baru. ──
    final v13 = raw.sqlite3.open(path);
    v13.execute('''
      CREATE TABLE products(
        id TEXT PRIMARY KEY, name TEXT, product_group_id INTEGER,
        kode_produk TEXT, parent_product_id TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
    ''');
    v13.execute(
        "INSERT INTO products(id, name, is_active, created_at, updated_at) "
        "VALUES('p1','Sedap Goreng',1,1700000000,1700000000)");
    // Tabel lain yang TIDAK relevan utk test ini tapi HARUS ada supaya
    // migrasi lanjutan (mis. v14->v15, kolom checked_item_ids/voided) tidak
    // gagal "no such table" saat AppDatabase membuka DB ini sampai versi
    // TERKINI (bukan cuma berhenti di 14).
    v13.execute('''
      CREATE TABLE transactions(
        id TEXT PRIMARY KEY, local_id TEXT UNIQUE, status TEXT NOT NULL,
        total INTEGER NOT NULL, paid INTEGER NOT NULL,
        change_amount INTEGER NOT NULL, payment_method TEXT NOT NULL,
        created_at INTEGER NOT NULL);
    ''');
    v13.execute('''
      CREATE TABLE transaction_payments(
        id TEXT PRIMARY KEY, transaction_id TEXT NOT NULL,
        amount INTEGER NOT NULL, method TEXT NOT NULL,
        paid_at INTEGER NOT NULL);
    ''');
    // transaction_items diperlukan agar migrasi v17 (addColumn returned_at)
    // tak gagal — Item 49g.
    v13.execute('CREATE TABLE transaction_items(id TEXT PRIMARY KEY);');

    final preCols = v13
        .select('PRAGMA table_info(products)')
        .map((r) => r['name'] as String)
        .toSet();
    expect(preCols, isNot(contains('marked_out_of_stock')),
        reason: 'prakondisi: DB v13 belum punya kolom marked_out_of_stock');
    v13.execute('PRAGMA user_version = 13;');
    // product_groups diperlukan agar migrasi v19 (addColumn sort_order) tak gagal.
    v13.execute('CREATE TABLE product_groups(id INTEGER PRIMARY KEY, name TEXT);');
    v13.dispose();

    // ── 2. Buka via AppDatabase (schemaVersion 14) → onUpgrade(13,14) jalan.
    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final p =
        await (db.select(db.products)..where((t) => t.id.equals('p1')))
            .getSingle();
    expect(p.markedOutOfStock, isFalse,
        reason: 'kolom baru harus default false, bukan crash/null');
    expect(p.name, 'Sedap Goreng', reason: 'data lama tetap utuh');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 20);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
