import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Membuktikan migrasi schemaVersion 7 -> 8 benar-benar membuat tabel
/// `alt_prices` (harga alternatif berlabel, fitur "Harga Lain") saat DB lama
/// (tanpa tabel itu) dibuka — bukan sekadar compile.
void main() {
  test('migrasi v7 -> v8: tabel alt_prices dibuat, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig8_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── 1. Bangun DB "v7" mentah: produk + satuan + indeks pembayaran (v7),
    //       TANPA tabel alt_prices sama sekali (persis instalasi lama). ────
    final v7 = raw.sqlite3.open(path);
    v7.execute('''
      CREATE TABLE products(
        id TEXT PRIMARY KEY, name TEXT, kode_produk TEXT,
        product_group_id INTEGER, parent_product_id TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER, updated_at INTEGER);
      CREATE TABLE product_units(
        id TEXT PRIMARY KEY, product_id TEXT, unit_type_id INTEGER,
        is_base_unit INTEGER NOT NULL DEFAULT 0, ratio_to_base REAL NOT NULL DEFAULT 1,
        is_non_stock INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE transaction_payments(
        id TEXT PRIMARY KEY, transaction_id TEXT, amount INTEGER, method TEXT,
        paid_at INTEGER, kasir_id TEXT, note TEXT);
      CREATE INDEX idx_tp_transaction ON transaction_payments(transaction_id);
      CREATE INDEX idx_tp_paid_at ON transaction_payments(paid_at);
      CREATE TABLE transactions(
        id TEXT PRIMARY KEY, local_id TEXT UNIQUE, kasir_id TEXT, customer_id TEXT,
        customer_name TEXT, status TEXT, total INTEGER, paid INTEGER,
        change_amount INTEGER, payment_method TEXT, internal_note TEXT,
        struk_note TEXT, employee_name TEXT, points_earned INTEGER,
        created_at INTEGER, synced_at INTEGER);
      CREATE TABLE transaction_items(
        id TEXT PRIMARY KEY, transaction_id TEXT, product_id TEXT,
        product_unit_id TEXT, qty REAL, price_at_sale INTEGER,
        original_price INTEGER, price_overridden INTEGER, cost_at_sale INTEGER,
        item_note TEXT, subtotal INTEGER, added_at INTEGER);
    ''');
    v7.execute("INSERT INTO products(id, name, is_active) "
        "VALUES('p1','Gula Pasir',1)");
    v7.execute("INSERT INTO product_units(id, product_id, is_base_unit) "
        "VALUES('u1','p1',1)");

    // Prakondisi: v7, alt_prices belum ada sama sekali.
    final preTables = v7
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'] as String)
        .toSet();
    expect(preTables, isNot(contains('alt_prices')),
        reason: 'prakondisi: DB v7 belum punya tabel alt_prices');
    v7.execute('PRAGMA user_version = 7;');
    // product_groups diperlukan agar migrasi v19 (addColumn sort_order) tak gagal.
    v7.execute('CREATE TABLE product_groups(id INTEGER PRIMARY KEY, name TEXT);');
    v7.dispose();

    // ── 2. Buka via AppDatabase (schemaVersion 8) → onUpgrade(7,8) berjalan.
    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    final tableNames = tables.map((r) => r.data['name'] as String).toSet();
    expect(tableNames, contains('alt_prices'),
        reason: 'migrasi 7->8 harus membuat tabel alt_prices');

    // Data lama (produk & satuan) tetap utuh setelah migrasi.
    final product = await db.customSelect(
        'SELECT name FROM products WHERE id = ?',
        variables: [Variable.withString('p1')]).getSingle();
    expect(product.data['name'], 'Gula Pasir');

    // Tabel baru benar-benar bisa dipakai (insert + select via Drift API).
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
          id: 'a1',
          productUnitId: 'u1',
          label: 'Harga Toko A',
          price: 3000,
        ));
    final rows = await db.getAltPrices('u1');
    expect(rows, hasLength(1));
    expect(rows.first.label, 'Harga Toko A');
    expect(rows.first.price, 3000);

    // Versi schema benar-benar naik ke skema terkini (10 — migrasi lanjutan
    // menambah change_taken & sort_order, tapi test ini fokus ke migrasi 7->8).
    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 19);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
