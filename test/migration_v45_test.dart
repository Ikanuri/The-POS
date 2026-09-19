import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Migrasi v44 -> v45: kolom `updated_at` ditambah ke `transaction_payments`.
///
/// Bug nyata yang mendasari (lihat dok kolom `TransactionPayments.updatedAt`
/// & Item 81 di `app_database.dart`): tabel ini diperlakukan append-only
/// murni oleh `dumpSince`/`mergeRows` (persis bug Item 62/63 yang sudah
/// pernah diperbaiki utk `transactions`/`transaction_items`, tapi tabel ini
/// sebelumnya tidak punya kolom timestamp apa pun) — `voidPayment`
/// ("Batalkan Pembayaran") meng-UPDATE `voided` pada baris yang sudah ada,
/// tidak pernah tersinkron ke device lain sebelum kolom ini ada.
void main() {
  test(
      'migrasi v44 -> v45: transaction_payments.updated_at ditambah, default '
      'null, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig45_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    final v44 = raw.sqlite3.open(path);
    v44.execute('PRAGMA user_version = 44;');
    v44.execute('''
      CREATE TABLE transaction_payments(
        id TEXT PRIMARY KEY,
        transaction_id TEXT,
        amount INTEGER,
        method TEXT,
        method_name TEXT,
        paid_at INTEGER,
        kasir_id TEXT,
        note TEXT,
        change_given INTEGER NOT NULL DEFAULT 0,
        change_taken INTEGER NOT NULL DEFAULT 0,
        voided INTEGER NOT NULL DEFAULT 0,
        sisa_after INTEGER NOT NULL DEFAULT 0,
        prabayar_change_taken_before_checkout INTEGER
      );
    ''');
    v44.execute("INSERT INTO transaction_payments "
        "(id, transaction_id, amount, method, paid_at) VALUES "
        "('pay-lama', 'tx-lama', 10000, 'tunai', 1000);");

    final preCols = v44
        .select("PRAGMA table_info(transaction_payments)")
        .map((r) => r['name'] as String)
        .toSet();
    expect(preCols, isNot(contains('updated_at')),
        reason: 'prakondisi: DB v44 belum punya kolom updated_at');
    v44.dispose();

    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final pay = await (db.select(db.transactionPayments)
          ..where((t) => t.id.equals('pay-lama')))
        .getSingle();
    expect(pay.amount, 10000, reason: 'data lama lain tidak tersentuh');
    expect(pay.voided, isFalse);
    expect(pay.updatedAt, isNull,
        reason: 'kolom baru NULL utk baris lama, bukan crash');

    // Cek langsung via `PRAGMA table_info` (bukan cuma via query ORM) --
    // `select(table)` drift generate `SELECT *`, yang TETAP sukses & baca
    // null walau kolom fisiknya belum ada sama sekali (tidak membuktikan
    // migrasi benar2 jalan). Assert eksplisit di sini WAJIB supaya test ini
    // benar2 gagal kalau migrasinya lupa/rusak.
    final postCols = await db
        .customSelect("PRAGMA table_info(transaction_payments)")
        .get();
    expect(
        postCols.map((r) => r.data['name'] as String).contains('updated_at'),
        isTrue,
        reason: 'kolom fisik HARUS benar2 ditambahkan oleh migrasi v45');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 45);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
