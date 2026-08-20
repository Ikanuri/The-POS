import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

import 'helpers/pump_app.dart';

/// Keluhan user: stepper +/- baris keranjang masih sering missclick.
/// Diskusi lebih dalam ditunda (dicatat di docs/HANDOFF.md) — untuk
/// sekarang, pijakan jempolnya diperbesar (30 -> 44px, ~+45%). Test ini
/// membuktikan: (1) ukuran benar-benar berubah, (2) TIDAK overflow di HP
/// sempit dgn nama produk 2-baris di sebelahnya (skenario paling padat).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final cartJson = jsonEncode([
    const CartItem(
      productId: 'P1',
      productUnitId: 'U1',
      // Nama panjang sengaja dipilih supaya baris ini benar2 mepet lebar
      // layar (skenario yg paling rawan overflow saat stepper membesar).
      productName: 'Beras Premium Kualitas Super 5kg Karung Jumbo',
      unitName: 'Karung',
      qty: 3,
      price: 65000,
      originalPrice: 65000,
      costPrice: 55000,
    ).toJson(),
  ]);

  testWidgets(
      'stepper baris keranjang 44px (bukan 30 lama), TIDAK overflow di HP '
      'sempit walau nama produk panjang', (tester) async {
    await pumpWithFakeApp(
      tester,
      db: db,
      initialPrefs: {'cart_v1_main': cartJson},
      surfaceSize: const Size(360, 800),
      child: const CartSheet(),
    );

    final addControl = tester.widget<AddControl>(find.byType(AddControl));
    expect(addControl.size, 44);
    expect(tester.takeException(), isNull,
        reason: 'stepper yang diperbesar tidak boleh bikin RenderFlex '
            'overflow saat berdampingan dgn nama produk panjang di HP sempit');

    // Lingkaran "+" (circleSize = size + 4) & tombol "-" (size - 2) harus
    // benar-benar di dalam batas layar, bukan cuma "ter-render" tapi
    // terdorong keluar.
    final screenW =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(tester.getRect(find.byType(AddControl)).right,
        lessThanOrEqualTo(screenW));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
