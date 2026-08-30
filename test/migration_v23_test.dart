import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Item 52 susulan — migrasi schemaVersion 22 -> 23 menambah kolom
/// `transaction_item_id` (nullable) ke `left_behind_items` yang SUDAH ADA
/// (dibuat di migrasi v22), tanpa mengganggu data lama.
void main() {
  test(
      'migrasi v22 -> v23: kolom transaction_item_id ditambah ke '
      'left_behind_items, default null, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig23_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── DB "v22" mentah: left_behind_items ada TANPA transaction_item_id.
    final v22 = raw.sqlite3.open(path);
    v22.execute('PRAGMA user_version = 22;');
    // transaction_payments diperlukan agar migrasi v32 (addColumn
    // sisa_after) tak gagal — riwayat pembayaran rincian retur/edit.
    v22.execute('''
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
    v22.execute('''
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
    // customers diperlukan agar migrasi v28 (addColumn locally_modified) tak gagal.
    v22.execute('CREATE TABLE customers(id TEXT PRIMARY KEY);');
    // transactions diperlukan agar migrasi v34 (addColumn method_name) tak gagal.
    v22.execute('CREATE TABLE transactions(id TEXT PRIMARY KEY);');
    v22.execute('''
      CREATE TABLE left_behind_items (
        id TEXT NOT NULL PRIMARY KEY,
        transaction_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        jenis TEXT NOT NULL,
        customer_id TEXT,
        customer_name_text TEXT,
        note TEXT,
        locally_modified INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        collected_at INTEGER
      );
    ''');
    v22.execute('''
      INSERT INTO left_behind_items (id, transaction_id, item_name, jenis)
      VALUES ('l-lama', 'tx-lama', 'Payung', 'titip');
    ''');
    // borrowed_items juga harus ada (dibuat step v22) — DB ini diupgrade
    // TERUS sampai schemaVersion current (24), yang step v24-nya menyentuh
    // tabel ini (`ALTER TABLE borrowed_items ADD COLUMN transaction_item_id`).
    v22.execute('''
      CREATE TABLE borrowed_items (
        id TEXT NOT NULL PRIMARY KEY,
        transaction_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        customer_id TEXT,
        customer_name_text TEXT,
        qty REAL NOT NULL,
        qty_returned REAL NOT NULL DEFAULT 0,
        note TEXT,
        locally_modified INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        fully_returned_at INTEGER
      );
    ''');
    // `product_units` juga harus ada — DB ini diupgrade TERUS sampai
    // schemaVersion terkini, yang step v27-nya (`follows_parent_price`)
    // menyentuh tabel ini via `ALTER TABLE ADD COLUMN` tanpa syarat versi.
    v22.execute('''
      CREATE TABLE product_units (
        id TEXT NOT NULL PRIMARY KEY,
        product_id TEXT NOT NULL,
        unit_type_id INTEGER,
        is_base_unit INTEGER NOT NULL DEFAULT 0,
        ratio_to_base REAL NOT NULL DEFAULT 1.0,
        is_non_stock INTEGER NOT NULL DEFAULT 0,
        min_stock INTEGER,
        requires_deposit INTEGER NOT NULL DEFAULT 0
      );
    ''');
    final preCols = v22
        .select("PRAGMA table_info('left_behind_items')")
        .map((r) => r['name'] as String)
        .toSet();
    expect(preCols, isNot(contains('transaction_item_id')),
        reason: 'prakondisi: DB v22 belum punya kolom itu');
    v22.dispose();

    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final postCols = (await db
            .customSelect("PRAGMA table_info('left_behind_items')")
            .get())
        .map((r) => r.data['name'] as String)
        .toSet();
    expect(postCols, contains('transaction_item_id'));

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.itemName, 'Payung');
    expect(rows.single.transactionItemId, isNull,
        reason: 'entri lama memang tidak punya tautan ke baris nota');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 34); // schemaVersion terkini

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
