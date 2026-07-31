import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/widgets/item_entry_sheet.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): "Apa fungsi lacak stok varian? Bagaimana
/// kita tahu jika varian tertentu kosong stoknya?" — dicek: stok varian
/// SUDAH dilacak di DB (tiap varian punya stock_ledger sendiri via
/// unitId-nya), tapi sebelumnya TIDAK PERNAH ditampilkan di mana pun.
/// Kasir bisa jual varian yang stoknya sudah 0 tanpa peringatan sama
/// sekali. Fix: tampilkan "Stok N" / "Habis" / "Non-stok" di baris varian.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> setStock(String unitId, double after) =>
      db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
            id: 'sl-$unitId',
            productUnitId: unitId,
            type: 'opening',
            qtyChange: after,
            stockAfter: after,
          ));

  Future<Product> seedParentWithVariants() async {
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers)
        .insert(PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000));

    // Varian "Coklat" — stok DILACAK & KOSONG (habis).
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v-habis', name: 'Coklat', parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'vu-habis',
        productId: 'v-habis',
        isBaseUnit: const Value(true),
        isNonStock: const Value(false)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'vt-habis', productUnitId: 'vu-habis', price: 5500));
    await setStock('vu-habis', 0);

    // Varian "Strawberry" — stok DILACAK & masih ADA (10).
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v-ada', name: 'Strawberry', parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'vu-ada',
        productId: 'v-ada',
        isBaseUnit: const Value(true),
        isNonStock: const Value(false)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'vt-ada', productUnitId: 'vu-ada', price: 5500));
    await setStock('vu-ada', 10);

    // Varian "Melon" — TIDAK lacak stok (non-stok).
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v-nonstok', name: 'Melon', parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'vu-nonstok',
        productId: 'v-nonstok',
        isBaseUnit: const Value(true),
        isNonStock: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'vt-nonstok', productUnitId: 'vu-nonstok', price: 5500));

    return (await db.searchProducts('')).firstWhere((p) => p.id == 'p1');
  }

  testWidgets(
      'varian stoknya kosong -> label "Habis" tampil; varian stoknya ada '
      '-> "Stok 10"', (tester) async {
    final product = await seedParentWithVariants();
    await pumpWithFakeApp(tester,
        db: db, child: ItemEntrySheet(product: product));

    final habisRow = find.ancestor(
        of: find.text('Coklat'),
        matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_VariantRow'));
    expect(find.descendant(of: habisRow, matching: find.text('Habis')),
        findsOneWidget);

    final adaRow = find.ancestor(
        of: find.text('Strawberry'),
        matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_VariantRow'));
    expect(
        find.descendant(
            of: adaRow, matching: find.textContaining('Stok 10')),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('varian yang tidak lacak stok tampil "Non-stok", bukan Habis',
      (tester) async {
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000));
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v-nonstok', name: 'Melon', parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'vu-nonstok',
        productId: 'v-nonstok',
        isBaseUnit: const Value(true),
        isNonStock: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'vt-nonstok', productUnitId: 'vu-nonstok', price: 5500));
    final product = (await db.searchProducts('')).firstWhere((p) => p.id == 'p1');

    await pumpWithFakeApp(tester,
        db: db, child: ItemEntrySheet(product: product));

    final nonStokRow = find.ancestor(
        of: find.text('Melon'),
        matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_VariantRow'));
    expect(
        find.descendant(
            of: nonStokRow, matching: find.textContaining('Non-stok')),
        findsOneWidget);
    expect(find.descendant(of: nonStokRow, matching: find.text('Habis')),
        findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
