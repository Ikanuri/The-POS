import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Membuktikan migrasi schemaVersion 8 -> 9 benar-benar menambah kolom
/// `change_taken` (centang "kembalian sudah diambil" di struk) saat DB lama
/// (tanpa kolom itu) dibuka — bukan sekadar compile.
void main() {
  test(
      'migrasi v8 -> v9: kolom change_taken ditambah, default false, data '
      'lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig9_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── 1. Bangun DB "v8" mentah: transactions TANPA kolom change_taken. ──
    // alt_prices ikut dibuat (tanpa sort_order) — DB v8 ASLI sudah punya
    // tabel ini sejak migrasi 7->8, jadi fixture harus konsisten supaya
    // migrasi lanjutan 9->10 (nambah sort_order) tidak "no such table".
    final v8 = raw.sqlite3.open(path);
    v8.execute('''
      CREATE TABLE transactions(
        id TEXT PRIMARY KEY, local_id TEXT UNIQUE, kasir_id TEXT, customer_id TEXT,
        customer_name TEXT, status TEXT, total INTEGER, paid INTEGER,
        change_amount INTEGER, payment_method TEXT, internal_note TEXT,
        struk_note TEXT, employee_name TEXT, points_earned INTEGER,
        created_at INTEGER, synced_at INTEGER);
      CREATE TABLE alt_prices(
        id TEXT PRIMARY KEY, product_unit_id TEXT, label TEXT,
        price INTEGER, created_at INTEGER);
    ''');
    v8.execute(
        "INSERT INTO transactions(id, local_id, status, total, paid, change_amount, "
        "payment_method, points_earned, created_at) "
        "VALUES('tx1','K1-20260101-0001','lunas',10000,15000,5000,'tunai',0,1600000000)");

    final preCols = v8
        .select("PRAGMA table_info(transactions)")
        .map((r) => r['name'] as String)
        .toSet();
    expect(preCols, isNot(contains('change_taken')),
        reason: 'prakondisi: DB v8 belum punya kolom change_taken');
    v8.execute('PRAGMA user_version = 8;');
    v8.dispose();

    // ── 2. Buka via AppDatabase (schemaVersion 9) → onUpgrade(8,9) berjalan.
    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(tx.changeTaken, isFalse,
        reason: 'kolom baru harus default false, bukan crash/null');
    expect(tx.changeAmount, 5000, reason: 'data lama tetap utuh');

    // Kolom benar-benar bisa ditulis (dipakai toggle di struk).
    await (db.update(db.transactions)..where((t) => t.id.equals('tx1')))
        .write(const TransactionsCompanion(changeTaken: Value(true)));
    final updated = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(updated.changeTaken, isTrue);

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 10);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
