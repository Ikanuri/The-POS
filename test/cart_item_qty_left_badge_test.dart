import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

import 'helpers/pump_app.dart';

/// Item 44 — baris item keranjang menampilkan badge jumlah qty di KIRI item
/// (leading, di samping checkbox), selain angka qty di stepper kanan.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets('badge "N×" tampil di kiri item (sebelum nama produk)',
      (tester) async {
    final prefs = {
      'cart_v1_main': jsonEncode([
        const CartItem(
          productId: 'P1',
          productUnitId: 'U1',
          productName: 'Beras 5kg',
          unitName: 'Karung',
          qty: 3,
          price: 65000,
          originalPrice: 65000,
          costPrice: 55000,
        ).toJson(),
      ]),
    };

    await pumpWithFakeApp(tester,
        db: db, initialPrefs: prefs, child: const CartSheet());

    // Badge "3×" muncul (unik — angka '3' di stepper kanan TIDAK ber-suffix ×).
    expect(find.text('3×'), findsOneWidget);
    // Badge berada di KIRI nama produk (leading), bukan di kanan.
    expect(tester.getCenter(find.text('3×')).dx,
        lessThan(tester.getCenter(find.text('Beras 5kg')).dx),
        reason: 'badge qty harus di kiri (leading) item, sebelum nama produk');
  });

  testWidgets('qty desimal tampil apa adanya di badge (0.25×, bukan 0×)',
      (tester) async {
    final prefs = {
      'cart_v1_main': jsonEncode([
        const CartItem(
          productId: 'P1',
          productUnitId: 'U1',
          productName: 'Daging',
          unitName: 'Kg',
          qty: 0.25,
          price: 40000,
          originalPrice: 40000,
          costPrice: 30000,
        ).toJson(),
      ]),
    };

    await pumpWithFakeApp(tester,
        db: db, initialPrefs: prefs, child: const CartSheet());

    expect(find.text('0.25×'), findsOneWidget,
        reason: 'qty desimal (produk timbang) tampil apa adanya, bukan '
            'dibulatkan ke 0');
  });
}
