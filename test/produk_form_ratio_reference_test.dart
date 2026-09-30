import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/utils/unit_ratio_calc.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Usulan user (sesi 83) — "Isi per Satuan" boleh dihitung dari satuan lain
/// (rokok: biji -> pack -> slop -> bal -> dus, tanpa konversi manual ke biji).
/// Hanya bantuan input: hasil disimpan sbg `ratioToBase` (snapshot).
void main() {
  group('ratioFromReference', () {
    test('jumlah x isi satuan acuan (contoh rokok)', () {
      // pack = 20 biji; slop = 10 pack; bal = 10 slop; dus = 4 bal.
      final slop = ratioFromReference(count: 10, referenceRatioToBase: 20)!;
      final bal = ratioFromReference(count: 10, referenceRatioToBase: slop)!;
      final dus = ratioFromReference(count: 4, referenceRatioToBase: bal)!;
      expect(slop, 200);
      expect(bal, 2000);
      expect(dus, 8000);
    });
    test('desimal dibulatkan 6 digit; tak valid -> null', () {
      expect(ratioFromReference(count: 0.1, referenceRatioToBase: 3), 0.3);
      expect(ratioFromReference(count: 0, referenceRatioToBase: 3), isNull);
      expect(ratioFromReference(count: 2, referenceRatioToBase: 0), isNull);
      expect(ratioFromReference(count: -1, referenceRatioToBase: 5), isNull);
    });
    test('formatRatio buang .0', () {
      expect(formatRatio(8000.0), '8000');
      expect(formatRatio(0.5), '0.5');
    });
  });

  group('form produk', () {
    testWidgets(
        'dus = 4 bal (bal = 2000 biji) -> field Isi per Satuan terisi 8000 '
        'dan tersimpan sbg ratioToBase', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async => db.close());
      // Satuan dasar biji(=1), bal (2000), dus (isi belum benar: 5).
      final units = <ProductUnitsCompanion>[
        ProductUnitsCompanion.insert(
            id: 'u0',
            productId: 'p1',
            unitTypeId: const Value(1),
            isBaseUnit: const Value(true)),
        ProductUnitsCompanion.insert(
            id: 'u1',
            productId: 'p1',
            unitTypeId: const Value(2),
            ratioToBase: const Value(2000.0)),
        ProductUnitsCompanion.insert(
            id: 'u2',
            productId: 'p1',
            unitTypeId: const Value(3),
            ratioToBase: const Value(5.0)),
      ];
      await db.saveProduct(
        product: ProductsCompanion.insert(id: 'p1', name: 'Rokok'),
        units: units,
        tiersByUnitTempId: {
          for (var i = 0; i < 3; i++)
            'u$i': [
              PriceTiersCompanion.insert(
                  id: 't$i', productUnitId: 'u$i', price: 1000 * (i + 1))
            ],
        },
        barcodesByUnitTempId: const {},
      );

      await pumpWithFakeApp(tester,
          db: db,
          child: const ProdukFormScreen(productId: 'p1'),
          surfaceSize: const Size(360, 2400));

      // Tombol muncul di kartu satuan NON-dasar (2 kartu), tidak di dasar.
      final buttons = find.byKey(const ValueKey('ratio-from-reference'));
      expect(buttons, findsNWidgets(2));

      await tester.ensureVisible(buttons.last);
      await tester.tap(buttons.last);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('ratio-ref-count')), '4');
      await tester.tap(find.byKey(const ValueKey('ratio-ref-unit')));
      await tester.pumpAndSettle();
      // Pilih satuan "bal" (isi 2000) dari daftar acuan.
      final option = find.textContaining('2000').last;
      await tester.tap(option);
      await tester.pumpAndSettle();

      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('ratio-ref-preview')))
              .data,
          contains('8000'));
      await tester.tap(find.byKey(const ValueKey('ratio-ref-apply')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, '8000'), findsOneWidget,
          reason: 'field Isi per Satuan terisi hasil hitungan');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });
}
