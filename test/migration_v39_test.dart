import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Migrasi v38 -> v39 (permintaan user, log void): kolom `voided_by` &
/// `void_reason` ditambah ke `transactions`, nullable — nota lama tetap
/// valid apa adanya (NULL di kedua kolom).
void main() {
  test(
      'migrasi v38 -> v39: kolom voided_by & void_reason ditambah, '
      'nota lama tetap NULL', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig39_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    final v38 = raw.sqlite3.open(path);
    v38.execute('PRAGMA user_version = 38;');
    v38.execute('''
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        local_id TEXT NOT NULL,
        kasir_id TEXT,
        customer_id TEXT,
        customer_name TEXT,
        status TEXT NOT NULL,
        total INTEGER NOT NULL,
        paid INTEGER NOT NULL,
        change_amount INTEGER NOT NULL,
        payment_method TEXT NOT NULL,
        method_name TEXT,
        internal_note TEXT,
        struk_note TEXT,
        employee_name TEXT,
        points_earned INTEGER NOT NULL DEFAULT 0,
        change_taken INTEGER NOT NULL DEFAULT 0,
        checked_item_ids TEXT,
        created_at INTEGER NOT NULL DEFAULT 0,
        synced_at INTEGER,
        updated_at INTEGER
      );
    ''');
    v38.execute("INSERT INTO transactions "
        "(id, local_id, status, total, paid, change_amount, payment_method, created_at) "
        "VALUES ('tx-lama', 'K1-20260101-0001', 'void', 10000, 10000, 0, 'tunai', 1000);");

    final before = v38.select("PRAGMA table_info(transactions)");
    expect(before.any((r) => r['name'] == 'voided_by'), isFalse,
        reason: 'prakondisi: DB v38 belum punya kolom voided_by');
    v38.dispose();

    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx-lama')))
        .getSingle();
    expect(tx.voidedBy, isNull,
        reason: 'nota lama tidak punya jejak siapa yang void — tetap NULL');
    expect(tx.voidReason, isNull,
        reason: 'nota lama tidak punya alasan void — tetap NULL');
    expect(tx.status, 'void', reason: 'data lama lain tidak tersentuh');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 42);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
