import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/utils/margin_calc.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Item 91 (keputusan user) — kalkulator "Margin" dua arah di form produk:
/// markup dari modal, tombol ikon "%", kolom mati saat HPP 0, margin negatif
/// boleh (ditandai rugi), grosir punya margin yang bisa diubah. Tidak
/// disimpan (tanpa schema).
void main() {
  group('margin_calc (markup dari modal)', () {
    test('dua arah persen & rupiah', () {
      expect(priceFromMargin(costPrice: 10000, margin: 20, isPercent: true),
          12000);
      expect(marginFromPrice(costPrice: 10000, sellPrice: 12000, isPercent: true),
          20);
      expect(priceFromMargin(costPrice: 10000, margin: 1500, isPercent: false),
          11500);
      expect(
          marginFromPrice(costPrice: 10000, sellPrice: 11500, isPercent: false),
          1500);
    });
    test('HPP 0 -> null (kolom dimatikan); negatif boleh', () {
      expect(marginFromPrice(costPrice: 0, sellPrice: 5000, isPercent: true),
          isNull);
      expect(priceFromMargin(costPrice: 0, margin: 10, isPercent: true), isNull);
      expect(marginFromPrice(costPrice: 10000, sellPrice: 9000, isPercent: true),
          -10);
    });
    test('format & parse', () {
      expect(formatMarginInput(12.5, isPercent: true), '12,5');
      expect(formatMarginInput(20, isPercent: true), '20');
      expect(formatMarginInput(33.3333, isPercent: true), '33,33');
      expect(formatMarginInput(1500, isPercent: false), '1500');
      expect(parseMarginInput('12,5'), 12.5);
      expect(parseMarginInput('-3'), -3);
      expect(parseMarginInput(''), isNull);
    });
  });

  group('form produk', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() async => db.close());

    Future<void> seed({int cost = 10000, int price = 12000}) async {
      await db.saveProduct(
        product: ProductsCompanion.insert(id: 'p1', name: 'Gula'),
        units: [
          ProductUnitsCompanion.insert(
              id: 'u0',
              productId: 'p1',
              unitTypeId: const Value(1),
              isBaseUnit: const Value(true)),
        ],
        tiersByUnitTempId: {
          'u0': [
            PriceTiersCompanion.insert(
                id: 't0',
                productUnitId: 'u0',
                price: price,
                costPrice: Value(cost)),
            PriceTiersCompanion.insert(
                id: 't1',
                productUnitId: 'u0',
                minQty: const Value(10),
                price: 11000,
                costPrice: Value(cost)),
          ],
        },
        barcodesByUnitTempId: const {},
      );
    }

    Future<void> open(WidgetTester tester) async {
      await pumpWithFakeApp(tester,
          db: db,
          child: const ProdukFormScreen(productId: 'p1'),
          surfaceSize: const Size(360, 2400));
      await tester.pumpAndSettle();
    }

    TextField marginField(WidgetTester tester) =>
        tester.widget<TextField>(find.byKey(const ValueKey('margin-field')));

    Future<void> drain(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    }

    testWidgets('ikon % membuka kolom Margin yg terisi dari harga & HPP; '
        'ketik margin -> harga jual berubah', (tester) async {
      await seed();
      await open(tester);
      expect(find.byKey(const ValueKey('margin-field')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('margin-toggle')));
      await tester.pumpAndSettle();
      expect(marginField(tester).controller!.text, '20');

      await tester.enterText(find.byKey(const ValueKey('margin-field')), '25');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '12500'), findsOneWidget,
          reason: 'harga jual = 10.000 x 1,25');
      expect(tester.takeException(), isNull);
      await drain(tester);
    });

    testWidgets('ubah harga jual -> margin ikut; mode Rp; negatif = rugi',
        (tester) async {
      await seed();
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('margin-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, '12000'), '15000');
      await tester.pumpAndSettle();
      expect(marginField(tester).controller!.text, '50');

      await tester.tap(find.byKey(const ValueKey('margin-mode-rp')));
      await tester.pumpAndSettle();
      expect(marginField(tester).controller!.text, '5000');

      await tester.enterText(
          find.widgetWithText(TextFormField, '15000'), '9000');
      await tester.pumpAndSettle();
      expect(marginField(tester).controller!.text, '-1000');
      expect(find.textContaining('Rugi'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('HPP 0 -> kolom Margin dimatikan', (tester) async {
      await seed(cost: 0);
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('margin-toggle')));
      await tester.pumpAndSettle();
      expect(marginField(tester).enabled, isFalse);
      expect(find.text('Isi Harga Pokok dulu'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('grosir: margin tampil & bisa diubah lewat dialog',
        (tester) async {
      await seed();
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('margin-toggle')));
      await tester.pumpAndSettle();
      final tierMargin = find.byKey(const ValueKey('tier-margin-0'));
      expect(find.descendant(of: tierMargin, matching: find.text('Margin 10%')),
          findsOneWidget);
      await tester.tap(tierMargin);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('tier-margin-input')), '5');
      await tester.tap(find.text('Terapkan'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '10500'), findsOneWidget);
      await drain(tester);
    });
  });
}
