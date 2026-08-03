import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): "beri highlight untuk produk yang sudah
/// dicentang. Highlight soft saja satu line item yang sudah dicentang."
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final prefs = {
    'cart_v1_main': jsonEncode([
      const CartItem(
        productId: 'P1',
        productUnitId: 'U1',
        productName: 'Beras 5kg',
        unitName: 'Karung',
        qty: 1,
        price: 65000,
        originalPrice: 65000,
        costPrice: 55000,
        checked: true,
      ).toJson(),
      const CartItem(
        productId: 'P2',
        productUnitId: 'U2',
        productName: 'Gula 1kg',
        unitName: 'Pcs',
        qty: 1,
        price: 15000,
        originalPrice: 15000,
        costPrice: 12000,
        checked: false,
      ).toJson(),
    ]),
  };

  Future<void> pumpCart(WidgetTester tester) => pumpWithFakeApp(tester,
      db: db,
      initialPrefs: prefs,
      surfaceSize: const Size(360, 800),
      child: const CartSheet());

  testWidgets(
      'item yang SUDAH dicentang mendapat highlight soft, yang BELUM tidak',
      (tester) async {
    await pumpCart(tester);

    Color? bgFor(String productName) {
      final container = tester.widget<Container>(find.ancestor(
        of: find.text(productName),
        matching: find.byType(Container),
      ).first);
      return container.color;
    }

    final checkedColor = bgFor('Beras 5kg');
    final uncheckedColor = bgFor('Gula 1kg');

    expect(checkedColor, isNotNull);
    expect(checkedColor, isNot(Colors.transparent),
        reason: 'item tercentang harus ada highlight (bukan transparan)');
    expect(uncheckedColor, Colors.transparent,
        reason: 'item belum tercentang tidak boleh ikut ter-highlight');

    // "Soft" — bukan warna solid/keras, cuma tint tipis dari warna primary.
    expect(checkedColor!.opacity, lessThan(0.2),
        reason: 'highlight harus soft (opacity rendah), bukan warna keras');
  });

  testWidgets(
      'tap checkbox utk mencentang item -> highlight langsung muncul '
      '(reaktif, tidak perlu reload)', (tester) async {
    await pumpCart(tester);

    Color? bgFor(String productName) {
      final container = tester.widget<Container>(find.ancestor(
        of: find.text(productName),
        matching: find.byType(Container),
      ).first);
      return container.color;
    }

    expect(bgFor('Gula 1kg'), Colors.transparent);

    // "Gula 1kg" adalah item KEDUA (bukan varian) — checkbox-nya jg yang
    // kedua, sesuai urutan `orderCartItems` (induk non-varian apa adanya).
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();

    expect(bgFor('Gula 1kg'), isNot(Colors.transparent),
        reason: 'setelah dicentang, highlight harus langsung muncul');
  });
}
