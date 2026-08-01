import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/utils/input_formatters.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Item 53 (permintaan user): saklar "Ikut harga satuan dasar" di dialog
/// Tambah/Edit Varian.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true))
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 1000)
        ]
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
  });
  tearDown(() async => db.close());

  Finder inDialog(Finder f) =>
      find.descendant(of: find.byType(AlertDialog), matching: f);

  TextField priceField(WidgetTester tester) => tester.widget<TextField>(
      inDialog(find.widgetWithText(TextField, 'Harga')));

  testWidgets(
      'nyalakan saklar -> field Harga jadi read-only & terisi pratinjau '
      '(harga satuan dasar x isi per satuan)', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ProdukFormScreen(productId: 'p1'));
    await tester.tap(find.text('Tambah Varian'));
    await tester.pumpAndSettle();

    expect(inDialog(find.text('Ikut harga satuan dasar')), findsOneWidget);
    expect(priceField(tester).readOnly, isFalse);

    await tester.enterText(
        inDialog(find.widgetWithText(TextField, 'Isi per Satuan')), '10');
    await tester.tap(inDialog(find.text('Ikut harga satuan dasar')));
    await tester.pumpAndSettle();

    expect(priceField(tester).readOnly, isTrue);
    expect(priceField(tester).controller!.text,
        ThousandsSeparatorFormatter.format(10000),
        reason: 'pratinjau = 1000 (harga satuan dasar) x 10 (isi)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'matikan saklar lagi -> field Harga kembali bisa diketik manual',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ProdukFormScreen(productId: 'p1'));
    await tester.tap(find.text('Tambah Varian'));
    await tester.pumpAndSettle();

    await tester.tap(inDialog(find.text('Ikut harga satuan dasar')));
    await tester.pumpAndSettle();
    expect(priceField(tester).readOnly, isTrue);

    await tester.tap(inDialog(find.text('Ikut harga satuan dasar')));
    await tester.pumpAndSettle();
    expect(priceField(tester).readOnly, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'simpan varian dgn saklar aktif isi 10 -> tersimpan followsParentPrice '
      'true & harga = 10000', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ProdukFormScreen(productId: 'p1'));
    await tester.tap(find.text('Tambah Varian'));
    await tester.pumpAndSettle();

    await tester.enterText(
        inDialog(find.widgetWithText(TextField, 'Nama Varian *')), 'Pedas');
    await tester.enterText(
        inDialog(find.widgetWithText(TextField, 'Isi per Satuan')), '10');
    await tester.tap(inDialog(find.text('Ikut harga satuan dasar')));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('Tambah')));
    await tester.pumpAndSettle();

    final variant = (await db.getVariants('p1')).single;
    final saleUnit =
        AppDatabase.variantSaleUnit(await db.getProductUnits(variant.id))!;
    expect(saleUnit.followsParentPrice, isTrue);
    final tier = (await db.getPriceTiers(saleUnit.id))
        .firstWhere((t) => t.minQty == 1);
    expect(tier.price, 10000);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'Edit Varian yg sudah followsParentPrice=true pra-isi saklar dlm '
      'keadaan menyala', (tester) async {
    final variantId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Pedas',
      price: 10000,
      costPrice: 7000,
      unitTypeId: 1,
      baseUnitTypeId: 1,
      contentPerUnit: 10,
      followsParentPrice: true,
    );

    await pumpWithFakeApp(tester,
        db: db, child: const ProdukFormScreen(productId: 'p1'));
    await tester.tap(find.text('Pedas'));
    await tester.pumpAndSettle();

    final toggle = tester.widget<SwitchListTile>(inDialog(
        find.widgetWithText(SwitchListTile, 'Ikut harga satuan dasar')));
    expect(toggle.value, isTrue);
    expect(priceField(tester).readOnly, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    // Hindari unused_local_variable lint kalau variantId tak dipakai lagi.
    expect(variantId, isNotEmpty);
  });
}
