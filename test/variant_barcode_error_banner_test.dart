import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Bug dilaporkan user: kalau varian diberi barcode yang sudah dipakai
/// produk/varian lain, varian TIDAK tersimpan TANPA pesan error apa pun
/// (silent failure) — root cause: `_addVariant`/`_editVariant` di
/// produk_form_screen.dart tidak pernah menangkap exception dari
/// db.createVariant()/updateVariant() (UNIQUE constraint di
/// product_barcodes.barcode bikin seluruh transaksi di-rollback).
void main() {
  Future<String> seedProductWithBarcode(
      AppDatabase db, String name, String barcode) async {
    return db.saveProduct(
      product: ProductsCompanion.insert(id: 'p-$name', name: name),
      units: [
        ProductUnitsCompanion.insert(
            id: 'p-$name-u', productId: 'p-$name', isBaseUnit: const Value(true))
      ],
      tiersByUnitTempId: {
        'p-$name-u': [
          PriceTiersCompanion.insert(
              id: 'p-$name-t', productUnitId: 'p-$name-u', price: 10000)
        ]
      },
      barcodesByUnitTempId: {
        'p-$name-u': [
          ProductBarcodesCompanion.insert(
              id: 'p-$name-bc',
              productUnitId: 'p-$name-u',
              barcode: barcode,
              isPrimary: const Value(true))
        ]
      },
      altPricesByUnitTempId: const {},
    );
  }

  testWidgets(
      'tambah varian dgn barcode BENTROK -> tampil pesan error, varian '
      'TIDAK tersimpan (bukan silent failure)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Produk LAIN yang sudah memegang barcode ini duluan.
    await seedProductWithBarcode(db, 'Sepatu', '888999');
    // Produk yang mau ditambah variannya.
    final parentId = await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p-Kaos', name: 'Kaos'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'p-Kaos-u', productId: 'p-Kaos', isBaseUnit: const Value(true))
      ],
      tiersByUnitTempId: {
        'p-Kaos-u': [
          PriceTiersCompanion.insert(
              id: 'p-Kaos-t', productUnitId: 'p-Kaos-u', price: 50000)
        ]
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    expect(parentId, 'p-Kaos');

    await pumpWithFakeApp(tester,
        db: db, child: ProdukFormScreen(productId: parentId));

    await tester.tap(find.text('Tambah Varian'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Nama Varian *'), 'Merah');
    await tester.enterText(
        find.widgetWithText(TextField, 'Barcode (opsional)'), '888999');
    await tester.tap(find.text('Tambah').last);
    await tester.pumpAndSettle();

    // Pesan error harus muncul (bukan silent failure).
    expect(find.textContaining('sudah dipakai'), findsOneWidget);

    // Varian benar-benar TIDAK tersimpan.
    final variants = await db.getVariants(parentId);
    expect(variants, isEmpty);

    await db.close();
  });
}
