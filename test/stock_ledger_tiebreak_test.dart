import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 38 (PLAN.md, ditemukan tak sengaja lewat test Stock Opname 25 Juli
/// — akhirnya TERBUKTI berdampak nyata, bukan cuma teoretis) —
/// `AppDatabase._rawBaseStock` (dipakai `currentStock`/`commitOpname`)
/// mengambil baris `stock_ledger` terbaru via `ORDER BY created_at DESC,
/// id DESC`. `created_at` presisi DETIK, `id` UUID v4 ACAK — kalau 2
/// penulisan stok jatuh di detik yang SAMA PERSIS (lazim: setup awal stok
/// langsung disusul stock opname beberapa milidetik kemudian, mis. alur
/// otomatis atau kasir yang cepat), tie-break `id DESC` bisa memilih baris
/// LAMA (UUID acak tidak berkorelasi dgn urutan insert) — stok yang dibaca
/// jadi versi lebih lama, bukan yang terakhir ditulis. Fix: tie-break
/// kedua pakai `rowid` (SQLite built-in, monoton naik sesuai urutan
/// insert).
void main() {
  Future<String> addProduct(AppDatabase db, String name) async {
    final id = 'p-$name';
    final unitId = '$id-u';
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: id, name: name));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: id,
          isBaseUnit: const Value(true),
        ));
    return unitId;
  }

  test(
      'currentStock ambil baris ledger TERAKHIR ditulis, bukan yang '
      'kebetulan menang tie-break id/UUID acak, walau created_at SAMA '
      'PERSIS (2 penulisan stok di detik yang sama)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final unitId = await addProduct(db, 'Indomie');

    // Simulasikan 2 penulisan stok yang jatuh PERSIS di detik yang sama
    // (created_at identik) — skenario yang ditemukan lewat Stock Opname:
    // setup awal (stok jadi 20) langsung disusul opname (stok jadi 100).
    final sameSecond = DateTime(2026, 7, 25, 10, 0, 0);

    // Baris PERTAMA ditulis (stok awal 20) — id SENGAJA "lebih besar" secara
    // leksikografis drpd baris kedua, supaya tie-break lama (`id DESC`)
    // PASTI salah pilih baris ini (deterministik, bukan untung-untungan
    // UUID acak) kalau fix belum diterapkan.
    await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
          id: 'zzz-ditulis-duluan',
          productUnitId: unitId,
          type: 'adjustment',
          qtyChange: 20,
          stockAfter: 20,
          createdAt: Value(sameSecond),
        ));
    // Baris KEDUA ditulis SESUDAHNYA (stok opname, stok jadi 100) — id
    // SENGAJA "lebih kecil" leksikografis (huruf 'a') drpd baris pertama,
    // walau `rowid`-nya (urutan insert sungguhan) lebih besar.
    await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
          id: 'aaa-ditulis-belakangan',
          productUnitId: unitId,
          type: 'adjustment',
          qtyChange: 80,
          stockAfter: 100,
          createdAt: Value(sameSecond),
        ));

    expect(await db.currentStock(unitId), 100,
        reason: 'harus ambil baris yang TERAKHIR ditulis (rowid lebih '
            'besar), bukan menang-kalah acak lewat UUID id');
  });

  test(
      'commitOpname (2 penulisan stok berurutan cepat, created_at sama) '
      'hasil akhirnya konsisten = penulisan TERAKHIR', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final unitId = await addProduct(db, 'Sabun');

    await db.adjustStock(productUnitId: unitId, newQty: 20);
    await db.commitOpname(
      entries: [(productUnitId: unitId, newQty: 100)],
      note: 'Opname test',
    );

    expect(await db.currentStock(unitId), 100);
  });

  test(
      'SEMUA jalur baca stok sepakat di detik yang sama — currentStock (Drift) '
      'DAN query raw SQL (watchStockOverview/getInventoryRows/dll) sama-sama '
      'tie-break pakai rowid, bukan UUID acak', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final unitId = await addProduct(db, 'Gajah Baru');

    final sameSecond = DateTime(2026, 7, 25, 17, 11, 0);
    // Ditulis DULU, id leksikografis LEBIH BESAR (menang tie-break lama).
    await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
          id: 'zzz-duluan',
          productUnitId: unitId,
          type: 'adjustment',
          qtyChange: 5,
          stockAfter: 5,
          createdAt: Value(sameSecond),
        ));
    // Ditulis BELAKANGAN (yang benar), id lebih kecil.
    await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
          id: 'aaa-belakangan',
          productUnitId: unitId,
          type: 'adjustment',
          qtyChange: 95,
          stockAfter: 100,
          createdAt: Value(sameSecond),
        ));

    // Jalur Drift (dipakai commitOpname/adjustStock).
    expect(await db.currentStock(unitId), 100);

    // Jalur raw SQL yang memasok layar Cek Stok & Stock Opname — dulu masih
    // `sl.id DESC` walau `_rawBaseStock` sudah diperbaiki, jadi kedua jalur
    // bisa MENAMPILKAN ANGKA BERBEDA untuk produk yang sama.
    final overview = await db.watchStockOverview().first;
    expect(overview.single.stock, 100,
        reason: 'watchStockOverview harus setuju dgn currentStock');
  });
}
