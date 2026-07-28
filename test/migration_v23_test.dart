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
    expect(ver.data.values.first, 25); // schemaVersion terkini

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
