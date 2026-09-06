import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/utils/price_category_calc.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): jalur "assign ke Kategori Harga" juga berlaku
/// utk VARIAN (bukan cuma satuan produk utama) — ikon `Icons.sell_outlined`
/// di tiap baris Harga Lain dalam dialog Tambah/Edit Varian.
///
/// Beda dari test produk utama (`produk_form_price_category_assign_test.
/// dart`): dialog varian pakai `showDialog` biasa (`Navigator.pop(ctx, ...)`
/// lokal), BUKAN `context.pop()` go_router — jadi cukup `pumpWithFakeApp`
/// (tanpa router sungguhan), sama seperti
/// `produk_form_variant_alt_price_ui_test.dart`.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'assign baris Harga Lain varian ke Kategori Harga -> tersimpan '
      'category-linked di DB', (tester) async {
    final parentId = await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Kopi'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true))
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(
              id: 't1',
              productUnitId: 'u1',
              price: 2000,
              costPrice: const Value(1200)),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    await db.addPriceCategory('Grosir');

    await pumpWithFakeApp(tester,
        db: db, child: ProdukFormScreen(productId: parentId));

    await tester.tap(find.text('Tambah Varian'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Nama Varian *'), 'Sachet');
    final inDialog = find.byType(AlertDialog);
    await tester.tap(find.descendant(
        of: inDialog, matching: find.text('Tambah Harga Lain')));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: inDialog, matching: find.byIcon(Icons.sell_outlined)));
    await tester.pumpAndSettle();

    expect(find.text('Pilih Kategori Harga'), findsOneWidget);
    await tester.tap(find.text('Grosir'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Kategori: Grosir'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Margin'), '10');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    // Baris Label sekarang menampilkan nama kategori (terkunci).
    expect(find.descendant(of: inDialog, matching: find.text('Grosir')),
        findsOneWidget);

    await tester.tap(
        find.descendant(of: inDialog, matching: find.text('Tambah')));
    await tester.pumpAndSettle();

    final variants = await db.getVariants(parentId);
    expect(variants, hasLength(1));
    final unit = (await db.getProductUnits(variants.single.id)).single;
    final alts = await db.getAltPrices(unit.id);
    expect(alts, hasLength(1));
    expect(alts.single.label, 'Grosir');
    expect(alts.single.priceCategoryId, isNotNull);
    expect(alts.single.marginAnchor, kMarginAnchorDasar);
    expect(alts.single.marginType, kMarginTypePercent);
    expect(alts.single.marginValue, 10);
    expect(alts.single.price, 2200); // 2000 * 1.1

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
