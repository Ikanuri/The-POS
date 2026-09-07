import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Migrasi v41 -> v42: kolom `prabayar_change_taken_before_checkout` ditambah
/// ke `transaction_payments` (fitur Pra-Bayar — metadata "kembalian yang
/// sudah diambil SEBELUM checkout", lihat dok
/// `TransactionPayments.prabayarChangeTakenBeforeCheckout`). Aditif &
/// nullable, baris lama tetap utuh (kolom baru harus NULL, bukan crash).
void main() {
  test(
      'migrasi v41 -> v42: kolom prabayar_change_taken_before_checkout '
      'ditambah ke transaction_payments, default null, data lama utuh',
      () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig42_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    final v41 = raw.sqlite3.open(path);
    v41.execute('PRAGMA user_version = 41;');
    v41.execute('''
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
        sisa_after INTEGER NOT NULL DEFAULT 0
      );
    ''');
    v41.execute("INSERT INTO transaction_payments "
        "(id, transaction_id, amount, method, paid_at, change_given) "
        "VALUES ('p-lama', 'tx-lama', 50000, 'tunai', 1700000000, 5000);");

    final preCols = v41
        .select("PRAGMA table_info(transaction_payments)")
        .map((r) => r['name'] as String)
        .toSet();
    expect(preCols, isNot(contains('prabayar_change_taken_before_checkout')),
        reason:
            'prakondisi: DB v41 belum punya kolom prabayar_change_taken_before_checkout');
    v41.dispose();

    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final payment = await (db.select(db.transactionPayments)
          ..where((t) => t.id.equals('p-lama')))
        .getSingle();
    expect(payment.amount, 50000, reason: 'data lama lain tidak tersentuh');
    expect(payment.changeGiven, 5000);
    expect(payment.prabayarChangeTakenBeforeCheckout, isNull,
        reason: 'kolom baru NULL utk baris lama, bukan 0/crash');

    // Cek langsung via `PRAGMA table_info` (bukan cuma via query ORM) —
    // `select(table)` drift generate `SELECT *`, yang TETAP sukses & baca
    // null walau kolom fisiknya belum ada sama sekali (tidak membuktikan
    // migrasi benar2 jalan). Assert eksplisit di sini WAJIB supaya test ini
    // benar2 gagal kalau migrasinya lupa/rusak.
    final postCols = await db
        .customSelect("PRAGMA table_info(transaction_payments)")
        .get();
    expect(
        postCols
            .map((r) => r.data['name'] as String)
            .contains('prabayar_change_taken_before_checkout'),
        isTrue,
        reason: 'kolom fisik HARUS benar2 ditambahkan oleh migrasi v42');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 43);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
