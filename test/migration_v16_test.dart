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
    // transaction_items diperlukan agar migrasi v17 (addColumn returned_at)
    // tak gagal — Item 49g.
    v15.execute('CREATE TABLE transaction_items(id TEXT PRIMARY KEY);');
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
    // transaction_payments diperlukan agar migrasi v32 (addColumn
    // sisa_after) tak gagal — riwayat pembayaran rincian retur/edit.
    v15.execute('''
      CREATE TABLE transaction_payments (
        id TEXT NOT NULL PRIMARY KEY,
        transaction_id TEXT NOT NULL,
        amount INTEGER NOT NULL,
        method TEXT NOT NULL,
        paid_at INTEGER NOT NULL DEFAULT 0,
        kasir_id TEXT,
        note TEXT,
        change_given INTEGER NOT NULL DEFAULT 0,
        change_taken INTEGER NOT NULL DEFAULT 0,
        voided INTEGER NOT NULL DEFAULT 0
      );
    ''');
    // Item 61.5 (fix baru) migrasi ALTER TABLE expenses ADD COLUMN
    // deleted_at berlaku TANPA syarat versi — tabel ini WAJIB ada di
    // fixture manapun yang diupgrade sampai schemaVersion terkini.
    v15.execute('''
      CREATE TABLE expenses (
        id TEXT NOT NULL PRIMARY KEY,
        local_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount INTEGER NOT NULL,
        note TEXT,
        reference_id TEXT,
        kasir_id TEXT,
        created_at INTEGER NOT NULL DEFAULT 0,
        synced_at INTEGER
      );
    ''');
    // product_groups diperlukan agar migrasi v19 (addColumn sort_order) tak gagal.
    v15.execute('CREATE TABLE product_groups(id INTEGER PRIMARY KEY, name TEXT);');
    // product_units diperlukan agar migrasi v22 (addColumn requires_deposit) tak gagal.
    v15.execute('CREATE TABLE product_units(id TEXT PRIMARY KEY);');
    // customers diperlukan agar migrasi v28 (addColumn locally_modified) tak gagal.
    v15.execute('CREATE TABLE customers(id TEXT PRIMARY KEY);');
    // transactions diperlukan agar migrasi v34 (addColumn method_name) tak gagal.
    v15.execute('CREATE TABLE transactions(id TEXT PRIMARY KEY);');
    v15.dispose();

    // ── 2. Buka via AppDatabase (schemaVersion 16) → onUpgrade(15,16) jalan.
    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final p = await (db.select(db.products)..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(p.locallyModified, isFalse,
        reason: 'kolom baru harus default false, bukan crash/null');
    expect(p.name, 'Gula', reason: 'data lama tetap utuh');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 36); // schemaVersion terkini

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
