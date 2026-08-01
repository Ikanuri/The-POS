import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): "varian terjangkar ke satuan dasar, namun di
/// varian, berikan pilih satuan (misal ret, dos, dll) serta juga terkonversi
/// ke satuan dasar (jadi juga ada isi per satuan)". Dulu dialog Tambah/Edit
/// Varian tidak punya keduanya sama sekali — jenis satuan diam-diam ikut
/// satuan dasar induk dan isi per satuan selalu 1 (tidak bisa diubah).
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(201), name: 'Pcs'));
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(202), name: 'Renteng'));
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1',
            productId: 'p1',
            isBaseUnit: const Value(true),
            unitTypeId: const Value(201))
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

  // Layar Edit Produk di belakang dialog JUGA punya field "Jenis Satuan" /
  // "Isi per Satuan" (kartu satuan produk utama) — semua pencarian di dalam
  // dialog varian WAJIB discope ke `AlertDialog`, kalau tidak ambigu.
  Finder inDialog(Finder f) =>
      find.descendant(of: find.byType(AlertDialog), matching: f);

  Future<void> openAddVariant(WidgetTester tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ProdukFormScreen(productId: 'p1'));
    await tester.tap(find.text('Tambah Varian'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'dialog varian punya "Jenis Satuan" + "Isi per Satuan"; simpan dgn '
      'Renteng isi 10 -> varian dijual per Renteng, jangkar tetap satuan '
      'dasar induk', (tester) async {
    await openAddVariant(tester);

    expect(inDialog(find.text('Jenis Satuan')), findsOneWidget);
    expect(inDialog(find.text('Isi per Satuan')), findsOneWidget);

    await tester.enterText(
        inDialog(find.widgetWithText(TextField, 'Nama Varian *')), 'Coklat');
    await tester.tap(inDialog(find.text('Jenis Satuan')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renteng').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        inDialog(find.widgetWithText(TextField, 'Isi per Satuan')), '10');
    await tester.tap(inDialog(find.text('Tambah')));
    await tester.pumpAndSettle();

    final variant = (await db.getVariants('p1')).single;
    final units = await db.getProductUnits(variant.id);
    expect(units, hasLength(2),
        reason: 'satu satuan dasar (jangkar) + satu satuan jual');
    final base = units.firstWhere((u) => u.isBaseUnit);
    final sale = AppDatabase.variantSaleUnit(units)!;
    expect(base.unitTypeId, 201, reason: 'jangkar ikut satuan dasar induk');
    expect(sale.unitTypeId, 202);
    expect(sale.ratioToBase, 10.0);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'isi per satuan dibiarkan 1 (default) -> varian tetap satu satuan, '
      'persis perilaku sebelum fitur ini', (tester) async {
    await openAddVariant(tester);

    await tester.enterText(
        inDialog(find.widgetWithText(TextField, 'Nama Varian *')), 'Coklat');
    await tester.tap(inDialog(find.text('Tambah')));
    await tester.pumpAndSettle();

    final variant = (await db.getVariants('p1')).single;
    expect(await db.getProductUnits(variant.id), hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'Edit Varian pra-isi jenis satuan & isi per satuan yang tersimpan '
      '(bukan reset ke satuan dasar/1)', (tester) async {
    await db.createVariant(
      parentProductId: 'p1',
      name: 'Coklat',
      price: 9000,
      costPrice: 7000,
      unitTypeId: 202,
      baseUnitTypeId: 201,
      contentPerUnit: 10,
    );

    await pumpWithFakeApp(tester,
        db: db, child: const ProdukFormScreen(productId: 'p1'));
    await tester.tap(find.text('Coklat'));
    await tester.pumpAndSettle();

    expect(inDialog(find.text('Renteng')), findsOneWidget,
        reason: 'dropdown harus menunjuk satuan JUAL yang tersimpan');
    expect(
        tester
            .widget<TextField>(
                inDialog(find.widgetWithText(TextField, 'Isi per Satuan')))
            .controller!
            .text,
        '10');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
