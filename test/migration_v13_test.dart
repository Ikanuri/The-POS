import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Membuktikan migrasi schemaVersion 12 -> 13 benar-benar menambah kolom
/// `change_given`/`change_taken` ke `transaction_payments` (kembalian
/// per-pembayaran) saat DB lama (tanpa kolom itu) dibuka — bukan sekadar
/// compile.
void main() {
  test(
      'migrasi v12 -> v13: kolom change_given/change_taken ditambah ke '
      'transaction_payments, default 0/false, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig13_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── 1. Bangun DB "v12" mentah: transaction_payments TANPA kolom baru. ──
    final v12 = raw.sqlite3.open(path);
    v12.execute('''
      CREATE TABLE transaction_payments(
        id TEXT PRIMARY KEY, transaction_id TEXT, amount INTEGER, method TEXT,
        paid_at INTEGER, kasir_id TEXT, note TEXT);
    ''');
    // products diperlukan agar migrasi v14 (addColumn marked_out_of_stock) tak gagal.
    v12.execute('CREATE TABLE products(id TEXT PRIMARY KEY);');
    v12.execute(
        "INSERT INTO transaction_payments(id, transaction_id, amount, method, paid_at) "
        "VALUES('p1','tx1',50000,'tunai',1700000000)");

    final preCols = v12
        .select("PRAGMA table_info(transaction_payments)")
        .map((r) => r['name'] as String)
        .toSet();
    expect(preCols, isNot(contains('change_given')),
        reason: 'prakondisi: DB v12 belum punya kolom change_given');
    v12.execute('PRAGMA user_version = 12;');
    v12.dispose();

    // ── 2. Buka via AppDatabase (schemaVersion 13) → onUpgrade(12,13) jalan.
    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final p = await (db.select(db.transactionPayments)
          ..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(p.changeGiven, 0,
        reason: 'kolom baru harus default 0, bukan crash/null');
    expect(p.changeTaken, isFalse);
    expect(p.amount, 50000, reason: 'data lama tetap utuh');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 14);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
