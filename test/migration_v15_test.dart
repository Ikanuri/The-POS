import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Membuktikan migrasi schemaVersion 14 -> 15 benar-benar menambah kolom
/// `checked_item_ids` ke `transactions` (persist centang verifikasi
/// serah-terima) dan `voided` ke `transaction_payments` (fitur "Batalkan
/// Pembayaran") saat DB lama (tanpa kolom itu) dibuka — bukan sekadar
/// compile.
void main() {
  test(
      'migrasi v14 -> v15: checked_item_ids (transactions) & voided '
      '(transaction_payments) ditambah, default aman, data lama utuh',
      () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig15_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── 1. Bangun DB "v14" mentah: kedua tabel TANPA kolom baru. ──
    final v14 = raw.sqlite3.open(path);
    // products diperlukan agar migrasi v16 (addColumn locally_modified) tak gagal.
    v14.execute('CREATE TABLE products(id TEXT PRIMARY KEY);');
    v14.execute('''
      CREATE TABLE transactions(
        id TEXT PRIMARY KEY, local_id TEXT UNIQUE, kasir_id TEXT,
        customer_id TEXT, customer_name TEXT, status TEXT NOT NULL,
        total INTEGER NOT NULL, paid INTEGER NOT NULL,
        change_amount INTEGER NOT NULL, payment_method TEXT NOT NULL,
        internal_note TEXT, struk_note TEXT, employee_name TEXT,
        points_earned INTEGER NOT NULL DEFAULT 0,
        change_taken INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL, synced_at INTEGER);
    ''');
    v14.execute('''
      CREATE TABLE transaction_payments(
        id TEXT PRIMARY KEY, transaction_id TEXT NOT NULL,
        amount INTEGER NOT NULL, method TEXT NOT NULL,
        paid_at INTEGER NOT NULL, kasir_id TEXT, note TEXT,
        change_given INTEGER NOT NULL DEFAULT 0,
        change_taken INTEGER NOT NULL DEFAULT 0);
    ''');
    // transaction_items diperlukan agar migrasi v17 (addColumn returned_at)
    // tak gagal — Item 49g.
    v14.execute('CREATE TABLE transaction_items(id TEXT PRIMARY KEY);');
    v14.execute(
        "INSERT INTO transactions(id, local_id, status, total, paid, "
        "change_amount, payment_method, created_at) VALUES('t1','K1-1',"
        "'lunas',10000,10000,0,'tunai',1700000000)");
    v14.execute(
        "INSERT INTO transaction_payments(id, transaction_id, amount, "
        "method, paid_at) VALUES('p1','t1',10000,'tunai',1700000000)");

    final preTxCols = v14
        .select('PRAGMA table_info(transactions)')
        .map((r) => r['name'] as String)
        .toSet();
    final prePayCols = v14
        .select('PRAGMA table_info(transaction_payments)')
        .map((r) => r['name'] as String)
        .toSet();
    expect(preTxCols, isNot(contains('checked_item_ids')),
        reason: 'prakondisi: DB v14 belum punya kolom checked_item_ids');
    expect(prePayCols, isNot(contains('voided')),
        reason: 'prakondisi: DB v14 belum punya kolom voided');
    v14.execute('PRAGMA user_version = 14;');
    v14.dispose();

    // ── 2. Buka via AppDatabase (schemaVersion 15) → onUpgrade(14,15) jalan.
    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals('t1')))
        .getSingle();
    expect(tx.checkedItemIds, isNull,
        reason: 'kolom baru harus default null, bukan crash');
    expect(tx.localId, 'K1-1', reason: 'data lama tetap utuh');

    final pay = await (db.select(db.transactionPayments)
          ..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(pay.voided, isFalse,
        reason: 'kolom baru harus default false, bukan crash/null');
    expect(pay.amount, 10000, reason: 'data lama tetap utuh');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 18);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
