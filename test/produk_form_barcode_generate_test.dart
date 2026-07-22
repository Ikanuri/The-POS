import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Item 51 (22 Juli, follow-up) — user klarifikasi: "Generate Barcode"
/// yang dimaksud BUKAN di layar Barcode/label terpisah, tapi langsung di
/// field input Barcode pada form Edit Produk (satu per satuan) — supaya
/// owner bisa isi barcode tanpa keluar dari form yang sedang dikerjakan.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Telur'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1',
            productId: 'p1',
            unitTypeId: const Value(1),
            isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(
              id: 't1', productUnitId: 'u1', price: 25000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
  });
  tearDown(() => db.close());

  testWidgets(
      'tombol Generate di field Barcode form Edit Produk → field terisi '
      'kode EAN-13 internal (prefix 29)', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ProdukFormScreen(productId: 'p1'));

    expect(find.byTooltip('Generate barcode'), findsOneWidget);

    await tester.tap(find.byTooltip('Generate barcode'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(find.ancestor(
        of: find.byTooltip('Generate barcode'),
        matching: find.byType(TextFormField)));
    final text = field.controller!.text;
    expect(text.startsWith('29'), isTrue, reason: 'barcode: $text');
    expect(text.length, 13);

    // Drain drift StreamProvider (mis. watchLowStockCount()) — tanpa ini
    // test bisa HANG "Timer is still pending" saat disposal walau test
    // cuma baca (gotcha CLAUDE.md).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
