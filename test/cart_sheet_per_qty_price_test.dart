import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

import 'helpers/pump_app.dart';

/// Poin 3 — keranjang kasir tampilkan harga per-qty (per 1 satuan) di
/// bawah nama item, berguna saat qty > 1 dan harga per-satuan tidak
/// langsung jelas dari subtotal saja.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'item keranjang qty > 1 tampilkan satuan · harga per-qty di bawah nama',
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

    expect(find.text('Beras 5kg'), findsOneWidget);
    // Harga per-qty (65.000/Karung) HARUS tampil terpisah dari subtotal
    // (3 x 65.000 = 195.000) — supaya jelas berapa harga per 1 Karung-nya.
    expect(find.text('Karung · ${formatRupiah(65000)}'), findsOneWidget);
    // Muncul di baris item DAN footer total keranjang (kebetulan sama,
    // cuma 1 item) — cukup pastikan setidaknya baris subtotal item ada.
    expect(find.text(formatRupiah(195000)), findsWidgets);
  });
}
