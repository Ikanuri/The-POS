import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 46 — helper stok tersisa (satuan dasar + konversi satuan lain dlm
/// kurung) & deteksi produk yang stoknya menipis pasca-jual.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  // Gula: base "Biji" (id 12), Pak (id 4, isi 20), Dos (id 14, isi 100).
  Future<void> seedGula({required int minStock}) async {
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'gula', name: 'Gula'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'biji',
            productId: 'gula',
            unitTypeId: const Value(12),
            isBaseUnit: const Value(true),
            ratioToBase: const Value(1.0),
            minStock: Value(minStock)),
        ProductUnitsCompanion.insert(
            id: 'pak',
            productId: 'gula',
            unitTypeId: const Value(4),
            ratioToBase: const Value(20.0)),
        ProductUnitsCompanion.insert(
            id: 'dus',
            productId: 'gula',
            unitTypeId: const Value(14),
            ratioToBase: const Value(100.0)),
      ],
      tiersByUnitTempId: {
        'biji': [
          PriceTiersCompanion.insert(id: 'tb', productUnitId: 'biji', price: 500)
        ],
        'pak': [
          PriceTiersCompanion.insert(id: 'tp', productUnitId: 'pak', price: 9000)
        ],
        'dus': [
          PriceTiersCompanion.insert(
              id: 'td', productUnitId: 'dus', price: 45000)
        ],
      },
      barcodesByUnitTempId: const {},
    );
  }

  test(
      'stockBreakdownText: satuan dasar apa adanya + satuan lain (konversi >=1) '
      'dalam kurung', () async {
    await seedGula(minStock: 100);
    await db.adjustStock(productUnitId: 'biji', newQty: 100);

    expect(await db.stockBreakdownText('gula'), '100 Biji (5 Pak, 1 Dos)',
        reason: '100 biji = 5 pak (÷20) = 1 dus (÷100)');
  });

  test('stockBreakdownText: satuan lain dgn konversi < 1 tidak ikut', () async {
    await seedGula(minStock: 100);
    await db.adjustStock(productUnitId: 'biji', newQty: 40); // 2 pak, 0.4 dus

    // Dos (0.4) dilewati; Pak (2) ikut.
    expect(await db.stockBreakdownText('gula'), '40 Biji (2 Pak)');
  });

  // Dua skenario ambang dipisah ke test terpisah (db baru per test via
  // setUp) — SENGAJA tidak dua kali adjustStock pada unit yang sama dalam
  // satu test, karena created_at stock_ledger presisi detik + tie-break id
  // UUID acak bisa salah pilih baris kalau dua penulisan jatuh di detik yang
  // sama (Item 38 PLAN.md; bikin test flaky di full-suite).
  test('lowStockAlertsForProducts: stok == minStock → pesan menipis',
      () async {
    await seedGula(minStock: 100);
    await db.adjustStock(productUnitId: 'biji', newQty: 100);
    expect(await db.lowStockAlertsForProducts({'gula'}),
        ['Stok Gula menipis: sisa 100 Biji (5 Pak, 1 Dos)']);
  });

  test('lowStockAlertsForProducts: stok > minStock → kosong', () async {
    await seedGula(minStock: 100);
    await db.adjustStock(productUnitId: 'biji', newQty: 150);
    expect(await db.lowStockAlertsForProducts({'gula'}), isEmpty);
  });

  test('lowStockAlertsForProducts: produk tanpa minStock tak pernah menipis',
      () async {
    await seedGula(minStock: 0); // minStock 0 → praktis tidak pernah <= kecuali 0
    await db.adjustStock(productUnitId: 'biji', newQty: 5);
    // minStock 0, stok 5 > 0 → tidak menipis.
    expect(await db.lowStockAlertsForProducts({'gula'}), isEmpty);
  });
}
