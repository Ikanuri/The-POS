import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/widgets/item_entry_sheet.dart';

import 'helpers/pump_app.dart';

/// Item 19 — tier grosir + Harga Lain milik satuan terpilih tampil di
/// dropdown "Harga lain" di sebelah field Harga (bukan chip menumpuk), dan
/// memilihnya mengisi field harga.
void main() {
  late AppDatabase db;
  late Product product;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Kopi'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    // Harga dasar 5000.
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 'pt1', productUnitId: 'u1', price: 5000));
    // Harga Lain "Harga Grosir" 4000.
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'ap1',
        productUnitId: 'u1',
        label: 'Harga Grosir',
        price: 4000));
    product = (await db.searchProducts('')).first;
  });

  tearDown(() async => db.close());

  TextField priceField(WidgetTester tester) => tester.widget<TextField>(
        find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.prefixText == 'Rp '),
      );

  testWidgets(
      'dropdown "Harga lain (1)" tampil & memilih Harga Grosir mengisi field',
      (tester) async {
    await pumpWithFakeApp(tester, db: db, child: ItemEntrySheet(product: product));

    // Tombol dropdown tampil dengan hitungan opsi non-dasar (1).
    expect(find.text('Harga lain (1)'), findsOneWidget);
    // Harga awal = harga dasar 5000.
    expect(priceField(tester).controller!.text, '5.000');

    await tester.tap(find.text('Harga lain (1)'));
    await tester.pumpAndSettle();
    // Menu memuat Harga dasar + Harga Grosir.
    expect(find.text('Harga Grosir'), findsOneWidget);
    await tester.tap(find.text('Harga Grosir'));
    await tester.pumpAndSettle();

    // Field harga terisi 4.000.
    expect(priceField(tester).controller!.text, '4.000');
  });

  testWidgets(
      'tombol "Harga lain" ikut menampilkan nama opsi terpilih (mis. '
      '"Harga Grosir"), bukan cuma hitungan statis', (tester) async {
    await pumpWithFakeApp(tester, db: db, child: ItemEntrySheet(product: product));

    await tester.tap(find.text('Harga lain (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Harga Grosir'));
    await tester.pumpAndSettle();

    // Tombol sekarang menampilkan nama opsi terpilih, bukan lagi generik.
    expect(find.text('Harga Grosir'), findsOneWidget);
    expect(find.text('Harga lain (1)'), findsNothing);

    // Balik ke Harga dasar → tombol kembali ke label generik.
    await tester.tap(find.text('Harga Grosir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Harga dasar'));
    await tester.pumpAndSettle();
    expect(find.text('Harga lain (1)'), findsOneWidget);
  });
}
