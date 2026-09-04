import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/widgets/item_entry_sheet.dart';

import 'helpers/pump_app.dart';

/// Fitur susulan (permintaan user): konverter kecil "beli dengan nominal Rp"
/// di field Jumlah — kasir ketik uang pelanggan (mis. Rp 5.000), qty otomatis
/// dihitung dari harga satuan aktif (mis. gula Rp 17.000/kg -> ~0,294 kg),
/// menghindari meraba-raba qty manual utk produk timbang/satuan desimal.
void main() {
  late AppDatabase db;
  late Product product;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Gula'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 'pt1', productUnitId: 'u1', price: 17000));
    product = (await db.searchProducts('')).first;
  });

  tearDown(() async => db.close());

  TextField qtyField(WidgetTester tester) => tester.widget<TextField>(
        find.byWidgetPredicate((w) =>
            w is TextField &&
            w.keyboardType == const TextInputType.numberWithOptions(decimal: true) &&
            w.textAlign == TextAlign.center &&
            w.controller!.text.isNotEmpty).first,
      );

  testWidgets(
      'ketuk ikon konverter, isi nominal Rp 5.000, tap Pakai -> qty '
      'terisi hasil bagi nominal/harga (dibulatkan 3 desimal)',
      (tester) async {
    await pumpWithFakeApp(tester, db: db, child: ItemEntrySheet(product: product));

    expect(find.byIcon(Icons.calculate_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.calculate_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Beli dengan nominal'), findsOneWidget);
    expect(find.textContaining('Harga:'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Uang pelanggan'), '5000');
    await tester.pumpAndSettle();

    // 5000 / 17000 = 0.2941176... -> dibulatkan 3 desimal = 0.294.
    // (satuan default id=1 di harness test = "Kg")
    expect(find.text('≈ 0.294 Kg'), findsOneWidget);

    await tester.tap(find.text('Pakai'));
    await tester.pumpAndSettle();

    expect(qtyField(tester).controller!.text, '0.294');
  });

  testWidgets('tombol Pakai disabled selama nominal masih kosong/0',
      (tester) async {
    await pumpWithFakeApp(tester, db: db, child: ItemEntrySheet(product: product));

    await tester.tap(find.byIcon(Icons.calculate_outlined));
    await tester.pumpAndSettle();

    final pakaiBtn =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Pakai'));
    expect(pakaiBtn.onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Uang pelanggan'), '5000');
    await tester.pumpAndSettle();

    final pakaiBtnAfter =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Pakai'));
    expect(pakaiBtnAfter.onPressed, isNotNull);
  });

  testWidgets(
      'ikon konverter TIDAK muncul selama harga terkunci (pre-order tanpa DP)',
      (tester) async {
    await db.setMarkedOutOfStock('p1', true);
    final produkHabis = (await db.searchProducts('')).first;

    await pumpWithFakeApp(tester, db: db,
        child: ItemEntrySheet(product: produkHabis));

    // Aktifkan Pre-order tanpa DP -> harga terkunci ke 0.
    await tester.tap(find.text('Ya').first);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.calculate_outlined), findsNothing);
  });
}
