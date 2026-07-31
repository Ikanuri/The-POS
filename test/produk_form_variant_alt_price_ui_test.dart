import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): "Harga Lain" untuk varian, dikelola lewat
/// dialog Tambah/Edit Varian yang sudah ada (tanpa drag-reorder spt produk
/// utama — dialog varian memang sengaja ringkas).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'tambah varian dgn Harga Lain lewat dialog -> tersimpan di DB',
      (tester) async {
    final parentId = await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true))
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000)
        ]
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    await pumpWithFakeApp(tester,
        db: db, child: ProdukFormScreen(productId: parentId));

    await tester.tap(find.text('Tambah Varian'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Nama Varian *'), 'Coklat');
    final inDialog = find.byType(AlertDialog);
    await tester.tap(find.descendant(
        of: inDialog, matching: find.text('Tambah Harga Lain')));
    await tester.pumpAndSettle();

    final labelField = find.descendant(
        of: inDialog, matching: find.widgetWithText(TextField, 'Label'));
    await tester.enterText(labelField, 'Toko A');
    // Baris Harga Lain (Label+Harga berdampingan dalam satu Row) — cari
    // TextField "Harga" yang SATU Row dgn field Label (field Harga dasar
    // varian di atasnya juga berlabel "Harga", jadi harus discope per-Row
    // spy tidak ambigu).
    final altPriceRow = find.ancestor(of: labelField, matching: find.byType(Row));
    await tester.enterText(
        find.descendant(
            of: altPriceRow, matching: find.widgetWithText(TextField, 'Harga')),
        '4500');
    await tester.tap(
        find.descendant(of: inDialog, matching: find.text('Tambah')));
    await tester.pumpAndSettle();

    final variants = await db.getVariants(parentId);
    expect(variants, hasLength(1));
    final unit = (await db.getProductUnits(variants.single.id)).single;
    final alts = await db.getAltPrices(unit.id);
    expect(alts, hasLength(1));
    expect(alts.single.label, 'Toko A');
    expect(alts.single.price, 4500);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
