import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Membuktikan migrasi schemaVersion 9 -> 10 benar-benar menambah kolom
/// `sort_order` ke `alt_prices` (reorder "Harga Lain" via drag-handle) saat
/// DB lama (tanpa kolom itu) dibuka — bukan sekadar compile.
void main() {
  test(
      'migrasi v9 -> v10: kolom sort_order ditambah ke alt_prices, default '
      '0, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig10_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── 1. Bangun DB "v9" mentah: alt_prices TANPA kolom sort_order. ──
    final v9 = raw.sqlite3.open(path);
    v9.execute('''
      CREATE TABLE alt_prices(
        id TEXT PRIMARY KEY, product_unit_id TEXT, label TEXT,
        price INTEGER, created_at INTEGER);
    ''');
    // product_units diperlukan agar migrasi v11 (addColumn min_stock) tak gagal.
    v9.execute('''
      CREATE TABLE product_units(
        id TEXT PRIMARY KEY, product_id TEXT, unit_type_id INTEGER,
        is_base_unit INTEGER, ratio_to_base REAL, is_non_stock INTEGER);
    ''');
    // transaction_payments diperlukan agar migrasi v13 (addColumn
    // change_given/change_taken) tak gagal.
    v9.execute('''
      CREATE TABLE transaction_payments(
        id TEXT PRIMARY KEY, transaction_id TEXT, amount INTEGER, method TEXT,
        paid_at INTEGER, kasir_id TEXT, note TEXT);
    ''');
    // products diperlukan agar migrasi v14 (addColumn marked_out_of_stock) tak gagal.
    v9.execute('CREATE TABLE products(id TEXT PRIMARY KEY);');
    // transactions diperlukan agar migrasi v15 (addColumn checked_item_ids) tak gagal.
    v9.execute('CREATE TABLE transactions(id TEXT PRIMARY KEY);');
    // transaction_items diperlukan agar migrasi v17 (addColumn returned_at)
    // tak gagal — Item 49g.
    v9.execute('CREATE TABLE transaction_items(id TEXT PRIMARY KEY);');
    v9.execute(
        "INSERT INTO alt_prices(id, product_unit_id, label, price, created_at) "
        "VALUES('a1','u1','Harga Toko A',3000,1700000000)");

    final preCols = v9
        .select("PRAGMA table_info(alt_prices)")
        .map((r) => r['name'] as String)
        .toSet();
    expect(preCols, isNot(contains('sort_order')),
        reason: 'prakondisi: DB v9 belum punya kolom sort_order');
    v9.execute('PRAGMA user_version = 9;');
    // product_groups diperlukan agar migrasi v19 (addColumn sort_order) tak gagal.
    v9.execute('CREATE TABLE product_groups(id INTEGER PRIMARY KEY, name TEXT);');
    v9.dispose();

    // ── 2. Buka via AppDatabase (schemaVersion 10) → onUpgrade(9,10) jalan.
    // readOnly:true — DB raw ini cuma berisi tabel alt_prices (sengaja,
    // supaya fokus ke migrasi kolom itu saja), jadi seed beforeOpen (yang
    // menulis ke unit_types dkk.) harus dilewati.
    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final alt = await (db.select(db.altPrices)
          ..where((t) => t.id.equals('a1')))
        .getSingle();
    expect(alt.sortOrder, 0,
        reason: 'kolom baru harus default 0, bukan crash/null');
    expect(alt.label, 'Harga Toko A', reason: 'data lama tetap utuh');

    // Kolom benar-benar bisa ditulis (dipakai saat simpan hasil reorder).
    await (db.update(db.altPrices)..where((t) => t.id.equals('a1')))
        .write(const AltPricesCompanion(sortOrder: Value(5)));
    final updated = await (db.select(db.altPrices)
          ..where((t) => t.id.equals('a1')))
        .getSingle();
    expect(updated.sortOrder, 5);

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 20);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });

  test('getAltPrices() mengurut berdasar sortOrder, BUKAN createdAt', () async {
    final db = AppDatabase(NativeDatabase.memory());

    // Sengaja simpan dengan createdAt "salah urut" dibanding sortOrder yang
    // diinginkan — reorder harus menang, bukan waktu insert/buat.
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 2850),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: {
        'u1': [
          AltPricesCompanion.insert(
              id: 'a-early',
              productUnitId: 'u1',
              label: 'Dibuat duluan, tapi urutan terakhir',
              price: 1000,
              createdAt: Value(DateTime(2026, 1, 1)),
              sortOrder: const Value(1)),
          AltPricesCompanion.insert(
              id: 'a-late',
              productUnitId: 'u1',
              label: 'Dibuat belakangan, tapi urutan pertama',
              price: 2000,
              createdAt: Value(DateTime(2026, 6, 1)),
              sortOrder: const Value(0)),
        ],
      },
    );

    final result = await db.getAltPrices('u1');
    expect(result.map((a) => a.id).toList(), ['a-late', 'a-early'],
        reason: 'urutan harus ikut sortOrder (0 dulu), bukan createdAt');

    await db.close();
  });
}
