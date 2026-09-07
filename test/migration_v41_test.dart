import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Migrasi v40 -> v41: kolom `updated_at` ditambah ke `suppliers` & ke
/// `purchases` (keduanya sebelumnya cuma punya `created_at`, jadi delta sync
/// LAN tidak bisa membedakan baris yang baru DIUBAH dari baris lama).
/// `purchase_items` sebelumnya malah tidak punya timestamp SAMA SEKALI —
/// dapat kolom `created_at` (bukan `updated_at`, krn baris ini immutable).
/// Baris lama harus tetap utuh & kolom baru terisi default (bukan crash).
void main() {
  test(
      'migrasi v40 -> v41: suppliers/purchases dapat updated_at, '
      'purchase_items dapat created_at, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig41_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    final v40 = raw.sqlite3.open(path);
    v40.execute('PRAGMA user_version = 40;');
    v40.execute('''
      CREATE TABLE suppliers (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT NULL,
        outstanding_debt INTEGER NOT NULL DEFAULT 0,
        notes TEXT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      );
    ''');
    v40.execute('''
      CREATE TABLE purchases (
        id TEXT NOT NULL PRIMARY KEY,
        local_id TEXT NOT NULL UNIQUE,
        supplier_id TEXT NULL,
        kasir_id TEXT NULL,
        status TEXT NOT NULL,
        total INTEGER NOT NULL DEFAULT 0,
        paid INTEGER NOT NULL DEFAULT 0,
        note TEXT NULL,
        created_at INTEGER NOT NULL,
        synced_at INTEGER NULL
      );
    ''');
    v40.execute('''
      CREATE TABLE purchase_items (
        id TEXT NOT NULL PRIMARY KEY,
        purchase_id TEXT NOT NULL REFERENCES purchases(id),
        product_unit_id TEXT NOT NULL,
        qty REAL NOT NULL,
        price_per_unit INTEGER NOT NULL,
        subtotal INTEGER NOT NULL
      );
    ''');
    v40.execute("INSERT INTO suppliers "
        "(id, name, phone, outstanding_debt, notes, is_active, created_at) "
        "VALUES ('sup-lama', 'Toko Grosir Jaya', '0812', 15000, NULL, 1, 1000);");
    v40.execute("INSERT INTO purchases "
        "(id, local_id, supplier_id, kasir_id, status, total, paid, note, "
        "created_at, synced_at) "
        "VALUES ('pur-lama', 'loc-1', 'sup-lama', NULL, 'draft', 50000, 0, "
        "NULL, 1000, NULL);");
    v40.execute("INSERT INTO purchase_items "
        "(id, purchase_id, product_unit_id, qty, price_per_unit, subtotal) "
        "VALUES ('pi-lama', 'pur-lama', 'unit-1', 2.0, 25000, 50000);");

    final beforeSup = v40.select("PRAGMA table_info(suppliers)");
    expect(beforeSup.any((r) => r['name'] == 'updated_at'), isFalse,
        reason: 'prakondisi: suppliers v40 belum punya updated_at');
    final beforePur = v40.select("PRAGMA table_info(purchases)");
    expect(beforePur.any((r) => r['name'] == 'updated_at'), isFalse,
        reason: 'prakondisi: purchases v40 belum punya updated_at');
    final beforePi = v40.select("PRAGMA table_info(purchase_items)");
    expect(beforePi.any((r) => r['name'] == 'created_at'), isFalse,
        reason: 'prakondisi: purchase_items v40 belum punya timestamp apa pun');
    v40.dispose();

    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final supplier = await (db.select(db.suppliers)
          ..where((t) => t.id.equals('sup-lama')))
        .getSingle();
    expect(supplier.name, 'Toko Grosir Jaya',
        reason: 'data lama lain tidak tersentuh');
    expect(supplier.outstandingDebt, 15000);
    expect(supplier.updatedAt, isNotNull,
        reason: 'kolom baru terisi default, bukan null/crash');

    final purchase = await (db.select(db.purchases)
          ..where((t) => t.id.equals('pur-lama')))
        .getSingle();
    expect(purchase.status, 'draft');
    expect(purchase.total, 50000);
    expect(purchase.updatedAt, isNotNull);

    final item = await (db.select(db.purchaseItems)
          ..where((t) => t.id.equals('pi-lama')))
        .getSingle();
    expect(item.subtotal, 50000);
    expect(item.createdAt, isNotNull,
        reason: 'purchase_items dapat created_at baru, terisi default');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 43);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
