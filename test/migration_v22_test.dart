import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Item 52 ("Laci Meja") — migrasi schemaVersion 21 -> 22 wajib: (1) buat 3
/// tabel baru (left_behind_items/borrowed_items/preorder_entries) tanpa
/// menyentuh data lama, (2) tambah kolom `requires_deposit` (default false)
/// ke `product_units` yang SUDAH ADA, data lama utuh.
void main() {
  test('migrasi v21 -> v22: 3 tabel baru dibuat, kolom requires_deposit '
      'ditambah ke product_units, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig22_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── 1. Bangun DB "v21" mentah: product_units SUDAH ADA TANPA
    // requires_deposit, berisi 1 baris data lama. Tabel Laci Meja belum ada.
    final v21 = raw.sqlite3.open(path);
    v21.execute('PRAGMA user_version = 21;');
    // transaction_payments diperlukan agar migrasi v32 (addColumn
    // sisa_after) tak gagal — riwayat pembayaran rincian retur/edit.
    v21.execute('''
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
    v21.execute('''
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
    v21.execute('CREATE TABLE products(id TEXT PRIMARY KEY, name TEXT);');
    // customers diperlukan agar migrasi v28 (addColumn locally_modified) tak gagal.
    v21.execute('CREATE TABLE customers(id TEXT PRIMARY KEY);');
    // transactions diperlukan agar migrasi v34 (addColumn method_name) tak gagal.
    v21.execute('CREATE TABLE transactions(id TEXT PRIMARY KEY);');
    v21.execute('''
      CREATE TABLE product_units (
        id TEXT NOT NULL PRIMARY KEY,
        product_id TEXT NOT NULL,
        unit_type_id INTEGER,
        is_base_unit INTEGER NOT NULL DEFAULT 0,
        ratio_to_base REAL NOT NULL DEFAULT 1.0,
        is_non_stock INTEGER NOT NULL DEFAULT 0,
        min_stock INTEGER
      );
    ''');
    v21.execute('''
      INSERT INTO product_units (id, product_id, is_base_unit)
      VALUES ('u-lama', 'p-lama', 1);
    ''');
    final preCols = v21
        .select("PRAGMA table_info('product_units')")
        .map((r) => r['name'] as String)
        .toSet();
    expect(preCols, isNot(contains('requires_deposit')),
        reason: 'prakondisi: DB v21 belum punya kolom requires_deposit');
    v21.dispose();

    // ── 2. Buka via AppDatabase (schemaVersion 22) → onUpgrade(21,22) jalan.
    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final postCols = (await db
            .customSelect("PRAGMA table_info('product_units')")
            .get())
        .map((r) => r.data['name'] as String)
        .toSet();
    expect(postCols, contains('requires_deposit'),
        reason: 'migrasi harus menambah kolom requires_deposit');

    final units = await db.select(db.productUnits).get();
    expect(units, hasLength(1));
    expect(units.single.id, 'u-lama');
    expect(units.single.requiresDeposit, isFalse,
        reason: 'default false, data lama tidak berubah perilaku');

    for (final table in ['left_behind_items', 'borrowed_items', 'preorder_entries']) {
      final exists = await db
          .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
              variables: [Variable(table)])
          .get();
      expect(exists, isNotEmpty, reason: 'tabel $table harus dibuat');
    }

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 41); // schemaVersion terkini

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
