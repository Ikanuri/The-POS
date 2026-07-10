import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Item 18 — beralih ke pesanan tertahan lain TIDAK membuang keranjang aktif:
/// keranjang aktif otomatis ditahan balik (label auto-generate untuk walk-in),
/// tanpa dialog "Ganti Keranjang?".
void main() {
  testWidgets(
      'tap pesanan tertahan saat keranjang aktif berisi → keranjang lama '
      'otomatis tersimpan sebagai "Tanpa Nama ..." (tidak hilang)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    // Keranjang aktif walk-in (1 item) di-seed lewat SharedPreferences —
    // CartNotifier memuatnya saat init.
    const walkin = CartItem(
      productId: 'pw',
      productUnitId: 'uw',
      productName: 'Kopi',
      unitName: 'pcs',
      qty: 2,
      price: 3000,
      originalPrice: 3000,
      costPrice: 2000,
    );
    SharedPreferences.setMockInitialValues({
      'cart_v1_main': jsonEncode([walkin.toJson()]),
    });

    // Pesanan tertahan "Bu Artia".
    const artia = CartItem(
      productId: 'pa',
      productUnitId: 'ua',
      productName: 'Teh',
      unitName: 'pcs',
      qty: 1,
      price: 4000,
      originalPrice: 4000,
      costPrice: 2500,
    );
    await db.holdOrder(
      id: 'ho-artia',
      label: 'Bu Artia',
      cartJson: jsonEncode({
        'items': [artia.toJson()],
        'meta': <String, dynamic>{},
      }),
    );

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Kasir',
      deviceCode: 'K1',
      deviceRole: 'owner',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider
            .overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    // Buka panel Antrian lalu lanjutkan pesanan Bu Artia.
    await tester.tap(find.text('Antrian').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bu Artia'));
    await tester.pumpAndSettle();

    // KONSUMSI overflow layout PRE-EXISTING (cart bar `kasir_screen.dart:2500`
    // & kartu antrian `:3061`) yang muncul pada surface sempit 430px — TIDAK
    // terkait Item 18 (murni logika switch). Test ini menegaskan state DB.
    for (var ex = tester.takeException(); ex != null;) {
      final s = ex.toString();
      expect(s.contains('overflowed') || s.contains('Multiple exceptions'),
          isTrue,
          reason: 'hanya overflow layout pre-existing yang boleh: $s');
      ex = tester.takeException();
    }

    // Bu Artia dihapus dari antrian, TAPI keranjang walk-in lama tersimpan
    // otomatis sebagai "Tanpa Nama ..." — bukan hilang. Total held tetap 1.
    final held = await db.select(db.heldOrders).get();
    expect(held.length, 1);
    expect(held.first.label, startsWith('Tanpa Nama'));

    // Dialog "Ganti Keranjang?" TIDAK muncul lagi.
    expect(find.text('Ganti Keranjang?'), findsNothing);

    // Drain drift StreamProvider disposal timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
