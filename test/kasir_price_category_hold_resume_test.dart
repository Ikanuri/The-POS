import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_price_category_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Fase C "Kategori Harga" — kategori aktif (`cartPriceCategoryProvider`)
/// WAJIB ikut tersimpan saat keranjang di-hold (`HeldOrders.cartJson`, key
/// baru `priceCategory`) dan ikut pulih saat di-resume — pola sama persis
/// dgn fitur Pra-Bayar (`kasir_prabayar_hold_resume_test.dart`).
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  const fakeDevice = DeviceIdentity(
    storeUuid: 's',
    storeKey: 'k',
    storeName: 'Toko',
    deviceName: 'Kasir',
    deviceCode: 'K1',
    deviceRole: 'owner',
  );

  testWidgets(
      'resume pesanan tertahan yg cartJson-nya bawa key "priceCategory" -> '
      'terpulihkan ke cartPriceCategoryProvider', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final catId = await db.addPriceCategory('Grosir');

    const item = CartItem(
      productId: 'pa',
      productUnitId: 'ua',
      productName: 'Teh',
      unitName: 'pcs',
      qty: 1,
      price: 4000,
      originalPrice: 4000,
      costPrice: 2500,
      priceFromCategoryId: null,
    );
    await db.holdOrder(
      id: 'ho-artia',
      label: 'Bu Artia',
      cartJson: jsonEncode({
        'items': [item.toJson()],
        'meta': <String, dynamic>{},
        'prabayar': <Map<String, dynamic>>[],
        'priceCategory': catId,
      }),
    );

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider
          .overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Antrian').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bu Artia'));
    await tester.pumpAndSettle();

    expect(container.read(cartPriceCategoryProvider(kMainCartId)), catId);

    await drain(tester);
  });

  testWidgets(
      'hold keranjang aktif dgn kategori aktif -> tersimpan di '
      'HeldOrders.cartJson (key "priceCategory") DAN provider aktif ikut '
      'ter-clear', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final catId = await db.addPriceCategory('Grosir');

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider
          .overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
    ]);
    addTearDown(container.dispose);

    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'pw',
          productUnitId: 'uw',
          productName: 'Kopi',
          unitName: 'pcs',
          qty: 2,
          price: 3000,
          originalPrice: 3000,
          costPrice: 2000,
        ));
    container.read(cartPriceCategoryProvider(kMainCartId).notifier)
        .setCategory(catId);
    // Pelanggan sudah dipilih -> `_holdCurrent` langsung tahan tanpa dialog
    // label (pola sama `kasir_prabayar_hold_resume_test.dart`).
    container
        .read(cartMetaProvider(kMainCartId).notifier)
        .setCustomer('c1', 'Bu Sari');

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.pause_circle_outline).first);
    await tester.pumpAndSettle();

    final held = await db.select(db.heldOrders).get();
    expect(held, hasLength(1));
    final decoded = jsonDecode(held.single.cartJson) as Map<String, dynamic>;
    expect(decoded['priceCategory'], catId);

    expect(container.read(cartPriceCategoryProvider(kMainCartId)), isNull,
        reason: 'provider aktif harus ikut ter-clear setelah hold');

    await drain(tester);
  });
}
