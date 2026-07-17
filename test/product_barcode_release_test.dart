import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug dilaporkan user: produk yang "dihapus" (deactivateProduct/deleteVariant)
/// cuma di-soft-delete (isActive=false) — barcode-nya TIDAK pernah dilepas,
/// jadi barcode itu terkunci selamanya (UNIQUE constraint product_barcodes.
/// barcode) dan tidak bisa dipakai ulang produk lain. Contoh nyata: refactor
/// dua produk single-varian (Pop Ice Coklat/Strawberry) jadi satu produk
/// dengan dua varian gagal karena barcode lama masih dipegang produk lama.
void main() {
  Future<String> seedProductWithBarcode(
      AppDatabase db, String id, String name, String barcode) async {
    return db.saveProduct(
      product: ProductsCompanion.insert(id: id, name: name),
      units: [
        ProductUnitsCompanion.insert(
            id: '$id-u', productId: id, isBaseUnit: const Value(true))
      ],
      tiersByUnitTempId: {
        '$id-u': [
          PriceTiersCompanion.insert(
              id: '$id-t', productUnitId: '$id-u', price: 10000)
        ]
      },
      barcodesByUnitTempId: {
        '$id-u': [
          ProductBarcodesCompanion.insert(
              id: '$id-bc',
              productUnitId: '$id-u',
              barcode: barcode,
              isPrimary: const Value(true))
        ]
      },
      altPricesByUnitTempId: const {},
    );
  }

  test('deactivateProduct melepas barcode -> bisa dipakai produk baru', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await seedProductWithBarcode(db, 'p-lama', 'Produk Lama', '12345');

    await db.deactivateProduct('p-lama');

    // Barcode asli sekarang bebas dipakai produk baru — tidak boleh throw
    // UNIQUE constraint.
    final newId = await seedProductWithBarcode(db, 'p-baru', 'Produk Baru', '12345');
    expect(newId, 'p-baru');

    // Baris barcode lama TETAP ADA (bukan dihapus) — cuma nilainya dimutasi,
    // supaya tetap ke-sync (full-dump) ke device lain sebagai pelepasan.
    final oldBarcodeRows = await (db.select(db.productBarcodes)
          ..where((t) => t.id.equals('p-lama-bc')))
        .get();
    expect(oldBarcodeRows, hasLength(1));
    expect(oldBarcodeRows.single.barcode, startsWith('RELEASED:'));
    expect(oldBarcodeRows.single.barcode, contains('12345'));

    await db.close();
  });

  test('deleteVariant melepas barcode varian -> bisa dipakai varian/produk lain',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final parentId = await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p-induk', name: 'Pop Ice'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'p-induk-u', productId: 'p-induk', isBaseUnit: const Value(true))
      ],
      tiersByUnitTempId: {
        'p-induk-u': [
          PriceTiersCompanion.insert(
              id: 'p-induk-t', productUnitId: 'p-induk-u', price: 3000)
        ]
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    final variantId = await db.createVariant(
      parentProductId: parentId,
      name: 'Coklat',
      price: 3000,
      costPrice: 2000,
      barcode: '999888',
    );

    await db.deleteVariant(variantId);

    // Barcode varian yang dihapus sekarang bebas dipakai varian baru.
    final newVariantId = await db.createVariant(
      parentProductId: parentId,
      name: 'Coklat (baru)',
      price: 3000,
      costPrice: 2000,
      barcode: '999888',
    );
    expect(newVariantId, isNotEmpty);

    await db.close();
  });
}
