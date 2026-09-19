import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Migrasi v43 -> v44: kolom `updated_at` ditambah ke `transaction_items`.
///
/// Bug nyata yang mendasari (lihat dok kolom `TransactionItems.updatedAt` &
/// Item 63 di `app_database.dart`): tabel ini diperlakukan append-only murni
/// oleh `dumpSince`/`mergeRows` (persis bug Item 62 yang sudah pernah
/// diperbaiki utk `transactions`, tapi di level baris item) — koreksi
/// post-insert (retur, edit item, DP pre-order) tidak pernah tersinkron ke
/// device lain sebelum kolom ini ada.
void main() {
  test(
      'migrasi v43 -> v44: transaction_items.updated_at ditambah, default '
      'null, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig44_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    final v43 = raw.sqlite3.open(path);
    v43.execute('PRAGMA user_version = 43;');
    v43.execute('''
      CREATE TABLE transaction_items(
        id TEXT PRIMARY KEY,
        transaction_id TEXT,
        product_id TEXT,
        product_unit_id TEXT,
        qty REAL,
        price_at_sale INTEGER,
        original_price INTEGER,
        price_overridden INTEGER NOT NULL DEFAULT 0,
        cost_at_sale INTEGER NOT NULL DEFAULT 0,
        item_note TEXT,
        subtotal INTEGER,
        added_at INTEGER,
        returned_at INTEGER
      );
    ''');
    v43.execute("INSERT INTO transaction_items "
        "(id, transaction_id, product_id, product_unit_id, qty, "
        "price_at_sale, original_price, subtotal) VALUES "
        "('ti-lama', 'tx-lama', 'P1', 'U1', 1, 10000, 10000, 10000);");

    final preCols = v43
        .select("PRAGMA table_info(transaction_items)")
        .map((r) => r['name'] as String)
        .toSet();
    expect(preCols, isNot(contains('updated_at')),
        reason: 'prakondisi: DB v43 belum punya kolom updated_at');
    v43.dispose();

    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final item = await (db.select(db.transactionItems)
          ..where((t) => t.id.equals('ti-lama')))
        .getSingle();
    expect(item.priceAtSale, 10000, reason: 'data lama lain tidak tersentuh');
    expect(item.subtotal, 10000);
    expect(item.updatedAt, isNull,
        reason: 'kolom baru NULL utk baris lama, bukan crash');

    // Cek langsung via `PRAGMA table_info` (bukan cuma via query ORM) —
    // `select(table)` drift generate `SELECT *`, yang TETAP sukses & baca
    // null walau kolom fisiknya belum ada sama sekali (tidak membuktikan
    // migrasi benar2 jalan). Assert eksplisit di sini WAJIB supaya test ini
    // benar2 gagal kalau migrasinya lupa/rusak.
    final postCols = await db
        .customSelect("PRAGMA table_info(transaction_items)")
        .get();
    expect(
        postCols.map((r) => r.data['name'] as String).contains('updated_at'),
        isTrue,
        reason: 'kolom fisik HARUS benar2 ditambahkan oleh migrasi v44');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 45);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
