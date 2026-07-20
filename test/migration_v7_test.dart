import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Membuktikan migrasi schemaVersion 6 -> 7 benar-benar dieksekusi saat DB lama
/// (tanpa indeks pembayaran) dibuka — bukan sekadar compile. Memakai sqlite3
/// polos (bukan SQLCipher); logika migrasi tidak bergantung enkripsi.
void main() {
  test('migrasi v6 -> v7: indeks transaction_payments ditambahkan, data utuh',
      () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── 1. Bangun DB "v6" mentah: hanya tabel yang disentuh migrasi, TANPA
    //       indeks pembayaran (persis kondisi instalasi lama). ─────────────
    final v6 = raw.sqlite3.open(path);
    // product_units diperlukan agar migrasi v11 (addColumn min_stock) tak gagal.
    v6.execute('CREATE TABLE product_units(id TEXT PRIMARY KEY, product_id TEXT, unit_type_id INTEGER, is_base_unit INTEGER, ratio_to_base REAL, is_non_stock INTEGER);');
    // products diperlukan agar migrasi v14 (addColumn marked_out_of_stock) tak gagal.
    v6.execute('CREATE TABLE products(id TEXT PRIMARY KEY);');
    v6.execute('''
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
      CREATE TABLE transaction_payments(
        id TEXT PRIMARY KEY, transaction_id TEXT, amount INTEGER, method TEXT,
        paid_at INTEGER, kasir_id TEXT, note TEXT);
      CREATE TABLE stock_ledger(
        id TEXT PRIMARY KEY, product_unit_id TEXT, type TEXT, qty_change REAL,
        stock_after REAL, reference_id TEXT, kasir_id TEXT, note TEXT,
        created_at INTEGER, synced_at INTEGER);
    ''');
    v6.execute(
        "INSERT INTO transactions(id, local_id, status, total, paid, change_amount, "
        "payment_method, points_earned, created_at) "
        "VALUES('tx1','K1-20260101-0001','lunas',5000,5000,0,'tunai',0,1600000000)");
    v6.execute(
        "INSERT INTO transaction_payments(id, transaction_id, amount, method, paid_at) "
        "VALUES('p1','tx1',5000,'tunai',1600000000)");

    // Pastikan prakondisi benar: v6 & belum ada indeks pembayaran.
    v6.execute('PRAGMA user_version = 6;');
    final preIdx = v6
        .select("SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name='transaction_payments'")
        .map((r) => r['name'] as String)
        .toSet();
    expect(preIdx, isNot(contains('idx_tp_transaction')),
        reason: 'prakondisi: DB v6 belum punya indeks pembayaran');
    v6.dispose();

    // ── 2. Buka via AppDatabase (schemaVersion 7) → onUpgrade(6,7) berjalan.
    //       readOnly:true melewati seed beforeOpen (butuh tabel lain), tapi
    //       migrasi tetap dieksekusi. ──────────────────────────────────────
    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final idxRows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name='transaction_payments'")
        .get();
    final names = idxRows.map((r) => r.data['name'] as String).toSet();

    expect(names, contains('idx_tp_transaction'),
        reason: 'migrasi harus menambah indeks transaction_id');
    expect(names, contains('idx_tp_paid_at'),
        reason: 'migrasi harus menambah indeks paid_at');

    // Versi schema benar-benar naik ke skema terkini (10 — migrasi lanjutan
    // menambah alt_prices, change_taken & sort_order, tapi test ini fokus
    // ke migrasi 6->7).
    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 17);

    // Data lama tetap utuh setelah migrasi.
    final pay = await db.customSelect(
        'SELECT amount FROM transaction_payments WHERE transaction_id = ?',
        variables: [Variable.withString('tx1')]).getSingle();
    expect(pay.data['amount'], 5000);

    // Indeks benar-benar dipakai query planner (bukan full-scan).
    final plan = await db.customSelect(
        'EXPLAIN QUERY PLAN SELECT * FROM transaction_payments '
        'WHERE transaction_id = ?',
        variables: [Variable.withString('tx1')]).get();
    final planText = plan.map((r) => r.data.values.join(' ')).join(' | ');
    expect(planText.toLowerCase(), contains('idx_tp_transaction'),
        reason: 'query pembayaran harus memakai indeks, bukan SCAN');

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });

  test('DB baru (onCreate) langsung punya indeks pembayaran', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final idxRows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name='transaction_payments'")
        .get();
    final names = idxRows.map((r) => r.data['name'] as String).toSet();
    expect(names, containsAll(['idx_tp_transaction', 'idx_tp_paid_at']));
    await db.close();
  });
}
