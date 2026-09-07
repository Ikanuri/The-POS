import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Migrasi v32 -> v33 (PLAN.md Item 54): tabel `laci_meja_events` dibuat, DAN
/// akumulasi pengembalian pinjaman LAMA (`borrowed_items.qty_returned`, yang
/// dulu ditulis tanpa jejak per-momen) di-backfill jadi satu baris log
/// historis. Tanpa backfill, pinjaman yang qty-nya sudah berkurang akan
/// tampil "belum pernah ada pengembalian" di riwayat baru — seolah datanya
/// hilang.
void main() {
  test('migrasi v32 -> v33: laci_meja_events dibuat + qty_returned lama '
      'di-backfill jadi baris log', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig33_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    final v32 = raw.sqlite3.open(path);
    v32.execute('PRAGMA user_version = 32;');
    v32.execute('''
      CREATE TABLE borrowed_items (
        id TEXT NOT NULL PRIMARY KEY,
        transaction_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        transaction_item_id TEXT,
        customer_id TEXT,
        customer_name_text TEXT,
        qty REAL NOT NULL,
        qty_returned REAL NOT NULL DEFAULT 0,
        note TEXT,
        locally_modified INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        fully_returned_at INTEGER
      );
    ''');
    // Satu pinjaman yang sudah kembali sebagian (3 dari 5) di era sebelum log
    // ada, satu lagi yang belum pernah kembali sama sekali.
    v32.execute("INSERT INTO borrowed_items "
        "(id, transaction_id, item_name, qty, qty_returned, created_at, updated_at) "
        "VALUES ('b-lama', 'tx1', 'Krat botol', 5, 3, 1000, 2000);");
    v32.execute("INSERT INTO borrowed_items "
        "(id, transaction_id, item_name, qty, qty_returned, created_at, updated_at) "
        "VALUES ('b-utuh', 'tx1', 'Galon', 2, 0, 1000, 1000);");

    final before = v32
        .select("SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='laci_meja_events'")
        .length;
    expect(before, 0, reason: 'prakondisi: DB v32 belum punya tabel log');
    // transactions/transaction_payments diperlukan agar migrasi v34
    // (addColumn method_name) tak gagal.
    v32.execute('CREATE TABLE transactions(id TEXT PRIMARY KEY);');
    v32.execute('CREATE TABLE transaction_payments(id TEXT PRIMARY KEY);');
    v32.dispose();

    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final exists = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='laci_meja_events'")
        .get();
    expect(exists, isNotEmpty, reason: 'tabel log harus dibuat migrasi v33');

    final events = await db.select(db.laciMejaEvents).get();
    expect(events, hasLength(1),
        reason: 'HANYA pinjaman yang qty_returned > 0 yang di-backfill');
    final e = events.single;
    expect(e.entryId, 'b-lama');
    expect(e.entityType, 'pinjaman');
    expect(e.aksi, 'kembali');
    expect(e.qty, 3, reason: 'seluruh akumulasi lama jadi satu baris');
    expect(e.id, 'bf-b-lama',
        reason: 'id deterministik supaya migrasi terulang tidak menggandakan');
    expect(e.createdAt.millisecondsSinceEpoch ~/ 1000, 2000,
        reason: 'pakai updated_at baris itu = perkiraan waktu kembali terakhir');

    // Hasil hitung ulang dari log HARUS sama dgn nilai kolom cache lamanya —
    // ini yang bikin `returnBorrowedItemQty` (yang kini menghitung ulang dari
    // log) tidak mengubah angka data lama.
    expect((await db.getLaciMejaTakenQty(['b-lama']))['b-lama'], 3);

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 42);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
