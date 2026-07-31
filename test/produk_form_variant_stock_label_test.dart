import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): status stok varian ditampilkan di layar Edit
/// Produk (daftar Varian), bukan cuma di ItemEntrySheet kasir — owner perlu
/// tahu varian mana yang kosong tanpa harus buka kasir.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'daftar Varian di Edit Produk menampilkan "Habis" utk varian yang '
      'stoknya kosong', (tester) async {
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000));

    final variantId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Coklat',
      price: 5500,
      costPrice: 3000,
      isNonStock: false,
    );
    final vUnit = (await db.getProductUnits(variantId)).single;
    await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
          id: 'sl1',
          productUnitId: vUnit.id,
          type: 'opening',
          qtyChange: 0,
          stockAfter: 0,
        ));

    await pumpWithFakeApp(tester,
        db: db, child: const ProdukFormScreen(productId: 'p1'));
    // FutureBuilder butuh 1 frame ekstra setelah Future selesai.
    await tester.pumpAndSettle();

    expect(find.text('Coklat'), findsOneWidget);
    expect(find.text('Habis'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
