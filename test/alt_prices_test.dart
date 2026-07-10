import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Test Tier 1 (DB murni) untuk fitur "Harga Lain" — harga alternatif
/// berlabel bebas per satuan produk (mis. "Harga Toko A" = 3000), tap-untuk-
/// pakai di kasir. Beda dari price_tiers (qty-tier), disimpan di tabel
/// terpisah `alt_prices` dan tidak pernah dipilih otomatis oleh resolver.
void main() {
  test('saveProduct menyimpan harga alternatif berlabel bersama satuan',
      () async {
    final db = AppDatabase(NativeDatabase.memory());

    final productId = await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng'),
      units: [
        ProductUnitsCompanion.insert(
          id: 'u1',
          productId: 'p1',
          isBaseUnit: const Value(true),
        ),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(
              id: 't1', productUnitId: 'u1', price: 2850),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: {
        'u1': [
          AltPricesCompanion.insert(
              id: 'a1',
              productUnitId: 'u1',
              label: 'Harga Toko A',
              price: 3000),
        ],
      },
    );

    final rows = await db.getAltPrices('u1');
    expect(rows, hasLength(1));
    expect(rows.first.label, 'Harga Toko A');
    expect(rows.first.price, 3000);
    expect(productId, 'p1');
    await db.close();
  });

  test(
      'saveProduct ulang MENGGANTI seluruh harga alternatif lama (bukan '
      'menumpuk), sama seperti perilaku price_tiers', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final unit = ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true));
    final product = ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng');

    await db.saveProduct(
      product: product,
      units: [unit],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 2850)
        ]
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: {
        'u1': [
          AltPricesCompanion.insert(
              id: 'a1', productUnitId: 'u1', label: 'Harga Lama', price: 2900),
        ],
      },
    );

    // Simpan ulang dengan set harga alternatif yang berbeda (label baru).
    await db.saveProduct(
      product: product,
      units: [unit],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 2850)
        ]
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: {
        'u1': [
          AltPricesCompanion.insert(
              id: 'a2', productUnitId: 'u1', label: 'Harga Baru', price: 3100),
        ],
      },
    );

    final rows = await db.getAltPrices('u1');
    expect(rows, hasLength(1),
        reason: 'harga alternatif lama harus diganti, bukan ditumpuk');
    expect(rows.first.label, 'Harga Baru');
    expect(rows.first.price, 3100);
    await db.close();
  });

  test(
      'menghapus satuan produk ikut menghapus harga alternatif miliknya '
      '(tidak jadi baris yatim)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final product = ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng');

    await db.saveProduct(
      product: product,
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 2850)
        ]
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: {
        'u1': [
          AltPricesCompanion.insert(
              id: 'a1',
              productUnitId: 'u1',
              label: 'Harga Toko A',
              price: 3000),
        ],
      },
    );

    // Simpan ulang TANPA satuan 'u1' (dihapus dari form) — ganti dengan unit baru.
    await db.saveProduct(
      product: product,
      units: [
        ProductUnitsCompanion.insert(
            id: 'u2', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u2': [
          PriceTiersCompanion.insert(id: 't2', productUnitId: 'u2', price: 2850)
        ]
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    final rows = await db.getAltPrices('u1');
    expect(rows, isEmpty,
        reason: 'harga alternatif milik satuan yang dihapus harus ikut hilang');
    await db.close();
  });
}
