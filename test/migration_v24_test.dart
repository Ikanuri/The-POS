import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Item 52 redesain — migrasi schemaVersion 23 -> 24 menambah kolom
/// `transaction_item_id` (nullable) ke `borrowed_items` yang SUDAH ADA
/// (dibuat di migrasi v22), tanpa mengganggu data lama. Pola identik migrasi
/// v23 (`left_behind_items.transaction_item_id`).
void main() {
  test(
      'migrasi v23 -> v24: kolom transaction_item_id ditambah ke '
      'borrowed_items, default null, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig24_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── DB "v23" mentah: borrowed_items ada TANPA transaction_item_id.
    final v23 = raw.sqlite3.open(path);
    v23.execute('PRAGMA user_version = 23;');
    v23.execute('''
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
    v23.execute('''
      INSERT INTO borrowed_items (id, transaction_id, item_name, qty)
      VALUES ('b-lama', 'tx-lama', 'Galon Aqua', 2);
    ''');
    // `left_behind_items` juga HARUS ada di DB v23 sungguhan (dibuat sejak
    // v22, `transaction_item_id` ditambah di migrasi v22->v23) — tanpa ini,
    // migrasi v24->v25 (susulan: kolom `qty` parsial) yg jalan SETELAH
    // migrasi ini akan gagal "no such table" krn tabelnya memang tidak ada
    // di DB sintetis test ini.
    v23.execute('''
      CREATE TABLE left_behind_items (
        id TEXT NOT NULL PRIMARY KEY,
        transaction_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        transaction_item_id TEXT,
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
    final preCols = v23
        .select("PRAGMA table_info('borrowed_items')")
        .map((r) => r['name'] as String)
        .toSet();
    expect(preCols, isNot(contains('transaction_item_id')),
        reason: 'prakondisi: DB v23 belum punya kolom itu');
    v23.dispose();

    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final postCols = (await db
            .customSelect("PRAGMA table_info('borrowed_items')")
            .get())
        .map((r) => r.data['name'] as String)
        .toSet();
    expect(postCols, contains('transaction_item_id'));

    final rows = await db.select(db.borrowedItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.itemName, 'Galon Aqua');
    expect(rows.single.transactionItemId, isNull,
        reason: 'entri lama memang tidak punya tautan ke baris nota');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    // schemaVersion TERKINI (25, bukan cuma 24) — migrasi berjalan
    // berurutan s.d. versi terbaru, bukan berhenti di step fokus test ini.
    expect(ver.data.values.first, 25);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
