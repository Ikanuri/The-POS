import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Membuktikan migrasi schemaVersion 16 -> 17 benar-benar menambah kolom
/// `returned_at` ke `transaction_items` (Item 49g — retur nota LUNAS tanpa
/// nota baru) saat DB lama (tanpa kolom itu) dibuka — bukan sekadar compile.
void main() {
  test(
      'migrasi v16 -> v17: returned_at (transaction_items) ditambah, '
      'default null, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig17_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── 1. Bangun DB "v16" mentah: transaction_items TANPA returned_at,
    // TAPI SUDAH punya added_at (kolom dari migrasi v6, jadi harus ada di
    // fixture v16). transactions stub minimal (FK reference).
    final v16 = raw.sqlite3.open(path);
    v16.execute('CREATE TABLE transactions(id TEXT PRIMARY KEY);');
    v16.execute('''
      CREATE TABLE transaction_items(
        id TEXT PRIMARY KEY, transaction_id TEXT NOT NULL,
        product_id TEXT NOT NULL, product_unit_id TEXT NOT NULL,
        qty REAL NOT NULL, price_at_sale INTEGER NOT NULL,
        original_price INTEGER NOT NULL,
        price_overridden INTEGER NOT NULL DEFAULT 0,
        cost_at_sale INTEGER NOT NULL DEFAULT 0,
        item_note TEXT, subtotal INTEGER NOT NULL, added_at INTEGER);
    ''');
    v16.execute('''
      INSERT INTO transaction_items(
        id, transaction_id, product_id, product_unit_id, qty,
        price_at_sale, original_price, subtotal)
      VALUES('i1','tx1','p1','u1',1,10000,10000,10000)
    ''');

    final preCols = v16
        .select('PRAGMA table_info(transaction_items)')
        .map((r) => r['name'] as String)
        .toSet();
    expect(preCols, isNot(contains('returned_at')),
        reason: 'prakondisi: DB v16 belum punya kolom returned_at');
    v16.execute('PRAGMA user_version = 16;');
    // transaction_payments diperlukan agar migrasi v32 (addColumn
    // sisa_after) tak gagal — riwayat pembayaran rincian retur/edit.
    v16.execute('''
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
    v16.execute('''
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
    v16.execute('CREATE TABLE product_groups(id INTEGER PRIMARY KEY, name TEXT);');
    // product_units diperlukan agar migrasi v22 (addColumn requires_deposit) tak gagal.
    v16.execute('CREATE TABLE product_units(id TEXT PRIMARY KEY);');
    // customers diperlukan agar migrasi v28 (addColumn locally_modified) tak gagal.
    v16.execute('CREATE TABLE customers(id TEXT PRIMARY KEY);');
    v16.dispose();

    // ── 2. Buka via AppDatabase (schemaVersion 17) → onUpgrade(16,17) jalan.
    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final item = await (db.select(db.transactionItems)
          ..where((t) => t.id.equals('i1')))
        .getSingle();
    expect(item.returnedAt, isNull,
        reason: 'kolom baru harus default null, bukan crash');
    expect(item.qty, 1.0, reason: 'data lama tetap utuh');
    expect(item.subtotal, 10000);

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 32); // schemaVersion terkini

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
