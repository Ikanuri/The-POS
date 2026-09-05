import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Bug nyata dilaporkan user: FK `customer_id -> customers` di
/// `left_behind_items`/`borrowed_items` bikin usulan Laci Meja yang menaut
/// pelanggan AD-HOC (dibuat di device kasir, tidak pernah tersinkron balik
/// ke host — pelanggan = master data satu-arah host->klien) GAGAL PERMANEN
/// saat diterapkan di host ("FOREIGN KEY constraint failed"). Migrasi v26
/// merekonstruksi kedua tabel TANPA FK itu (`m.alterTable`), data lama
/// disalin apa adanya.
void main() {
  test(
      'migrasi v25 -> v26: FK customer_id dihapus dari left_behind_items & '
      'borrowed_items, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig26_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── DB "v25" mentah: kedua tabel MASIH punya FK customer_id -> customers
    // (skema lama, sebelum fix).
    final v25 = raw.sqlite3.open(path);
    v25.execute('PRAGMA user_version = 25;');
    // transaction_payments diperlukan agar migrasi v32 (addColumn
    // sisa_after) tak gagal — riwayat pembayaran rincian retur/edit.
    v25.execute('''
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
    v25.execute('''
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
    v25.execute('''
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY
      );
    ''');
    v25.execute('''
      CREATE TABLE customers (
        id TEXT NOT NULL PRIMARY KEY
      );
    ''');
    v25.execute('''
      CREATE TABLE left_behind_items (
        id TEXT NOT NULL PRIMARY KEY,
        transaction_id TEXT NOT NULL REFERENCES transactions(id),
        item_name TEXT NOT NULL,
        transaction_item_id TEXT,
        jenis TEXT NOT NULL,
        customer_id TEXT REFERENCES customers(id),
        customer_name_text TEXT,
        note TEXT,
        locally_modified INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        collected_at INTEGER,
        qty REAL
      );
    ''');
    v25.execute('''
      CREATE TABLE borrowed_items (
        id TEXT NOT NULL PRIMARY KEY,
        transaction_id TEXT NOT NULL REFERENCES transactions(id),
        item_name TEXT NOT NULL,
        transaction_item_id TEXT,
        customer_id TEXT REFERENCES customers(id),
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
    v25.execute('''
      CREATE TABLE preorder_entries (
        id TEXT NOT NULL PRIMARY KEY,
        product_id TEXT NOT NULL,
        product_unit_id TEXT NOT NULL,
        transaction_id TEXT REFERENCES transactions(id),
        customer_name TEXT NOT NULL,
        phone TEXT,
        qty_ordered REAL NOT NULL,
        deposit_qty REAL NOT NULL DEFAULT 0,
        paid INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        locally_modified INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        fulfilled_at INTEGER,
        cancelled_at INTEGER
      );
    ''');
    // `product_units` juga harus ada — DB ini diupgrade TERUS sampai
    // schemaVersion terkini, yang step v27-nya (`follows_parent_price`)
    // menyentuh tabel ini via `ALTER TABLE ADD COLUMN` tanpa syarat versi.
    v25.execute('''
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
    v25.execute('''
      INSERT INTO transactions (id) VALUES ('tx-lama');
    ''');
    v25.execute('''
      INSERT INTO left_behind_items
        (id, transaction_id, item_name, jenis, qty)
      VALUES ('l-lama', 'tx-lama', 'Payung Lama', 'ketinggalan', 1);
    ''');
    v25.execute('''
      INSERT INTO borrowed_items (id, transaction_id, item_name, qty)
      VALUES ('b-lama', 'tx-lama', 'Galon Lama', 2);
    ''');

    final fkBefore = v25
        .select("PRAGMA foreign_key_list('left_behind_items')")
        .map((r) => r['table'] as String)
        .toList();
    expect(fkBefore, contains('customers'),
        reason: 'prakondisi: DB v25 MASIH punya FK ke customers');
    v25.dispose();

    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final fkAfterLeftBehind = (await db
            .customSelect("PRAGMA foreign_key_list('left_behind_items')")
            .get())
        .map((r) => r.data['table'] as String)
        .toList();
    final fkAfterBorrowed = (await db
            .customSelect("PRAGMA foreign_key_list('borrowed_items')")
            .get())
        .map((r) => r.data['table'] as String)
        .toList();
    expect(fkAfterLeftBehind, isNot(contains('customers')),
        reason: 'FK ke customers WAJIB sudah hilang setelah migrasi v26');
    expect(fkAfterBorrowed, isNot(contains('customers')),
        reason: 'FK ke customers WAJIB sudah hilang setelah migrasi v26');
    // transactionId tetap FK (transaksi SELALU tersinkron client->host,
    // beda dari customer yg satu-arah host->klien) — sengaja TIDAK dihapus.
    expect(fkAfterLeftBehind, contains('transactions'));

    final leftBehindRows = await db.select(db.leftBehindItems).get();
    expect(leftBehindRows, hasLength(1));
    expect(leftBehindRows.single.itemName, 'Payung Lama');

    final borrowedRows = await db.select(db.borrowedItems).get();
    expect(borrowedRows, hasLength(1));
    expect(borrowedRows.single.itemName, 'Galon Lama');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 40);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
