import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Migrasi v30 -> v31: tabel `product_aliases` (kamus belajar Penerimaan
/// Barang) dibuat, data lama tidak tersentuh.
void main() {
  test('migrasi v30 -> v31: tabel product_aliases dibuat, data lama utuh',
      () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig31_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    final v30 = raw.sqlite3.open(path);
    v30.execute('PRAGMA user_version = 30;');
    // transaction_payments diperlukan agar migrasi v32 (addColumn
    // sisa_after) tak gagal — riwayat pembayaran rincian retur/edit.
    v30.execute('''
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
    // Tabel-tabel yang disentuh step migrasi TANPA syarat versi awal —
    // wajib ada di fixture manapun (pola sama migration_v26_test).
    v30.execute('''
      CREATE TABLE expenses (
        id TEXT NOT NULL PRIMARY KEY,
        local_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount INTEGER NOT NULL,
        note TEXT,
        reference_id TEXT,
        kasir_id TEXT,
        created_at INTEGER NOT NULL DEFAULT 0,
        synced_at INTEGER,
        deleted_at INTEGER
      );
    ''');
    v30.execute('CREATE TABLE customers(id TEXT PRIMARY KEY);');
    // transactions diperlukan agar migrasi v34 (addColumn method_name) tak gagal.
    v30.execute('CREATE TABLE transactions(id TEXT PRIMARY KEY);');
    v30.execute('''
      CREATE TABLE product_units (
        id TEXT NOT NULL PRIMARY KEY,
        product_id TEXT NOT NULL,
        unit_type_id INTEGER,
        is_base_unit INTEGER NOT NULL DEFAULT 0,
        ratio_to_base REAL NOT NULL DEFAULT 1.0,
        is_non_stock INTEGER NOT NULL DEFAULT 0,
        min_stock INTEGER,
        requires_deposit INTEGER NOT NULL DEFAULT 0,
        follows_parent_price INTEGER NOT NULL DEFAULT 0
      );
    ''');
    v30.execute("INSERT INTO product_units (id, product_id) "
        "VALUES ('u-lama', 'p-lama');");

    final before = v30
        .select("SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='product_aliases'")
        .length;
    expect(before, 0, reason: 'prakondisi: DB v30 belum punya tabel kamus');
    v30.dispose();

    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final exists = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='product_aliases'")
        .get();
    expect(exists, isNotEmpty, reason: 'tabel kamus harus dibuat migrasi v31');

    final units = await db.select(db.productUnits).get();
    expect(units, hasLength(1));
    expect(units.single.id, 'u-lama', reason: 'data lama tidak tersentuh');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 35);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
