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
import 'package:the_pos/features/kasir/cart_prabayar_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Fitur "Pra-Bayar" — entri Pra-Bayar WAJIB ikut tersimpan saat keranjang
/// di-hold (`HeldOrders.cartJson`, key baru `prabayar`) dan ikut pulih saat
/// di-resume — pola sama persis dgn `meta` (lihat `kasir_switch_held_test.dart`).
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
      'resume pesanan tertahan yg cartJson-nya bawa key "prabayar" → entri '
      'terpulihkan utuh ke cartPrabayarProvider (amount/method/lockedAt)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    const item = CartItem(
      productId: 'pa',
      productUnitId: 'ua',
      productName: 'Teh',
      unitName: 'pcs',
      qty: 1,
      price: 4000,
      originalPrice: 4000,
      costPrice: 2500,
    );
    final lockedAt = DateTime(2026, 1, 5, 9, 15);
    await db.holdOrder(
      id: 'ho-artia',
      label: 'Bu Artia',
      cartJson: jsonEncode({
        'items': [item.toJson()],
        'meta': <String, dynamic>{},
        'prabayar': [
          {
            'id': 'pb-1',
            'amount': 15000,
            'method': 'tunai',
            'methodName': null,
            'lockedAt': lockedAt.millisecondsSinceEpoch,
          },
        ],
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

    final prabayar = container.read(cartPrabayarProvider(kMainCartId));
    expect(prabayar, hasLength(1));
    expect(prabayar.single.amount, 15000);
    expect(prabayar.single.method, 'tunai');
    expect(prabayar.single.lockedAt, lockedAt);

    await drain(tester);
  });

  testWidgets(
      'hold keranjang aktif yg PUNYA entri Pra-Bayar → tersimpan di '
      'HeldOrders.cartJson (key "prabayar") DAN provider aktif ikut '
      'ter-clear', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

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
    final lockedAt = DateTime(2026, 1, 5, 9, 15);
    container.read(cartPrabayarProvider(kMainCartId).notifier).add(
          PrabayarEntry(
              id: 'pb-1', amount: 12000, method: 'tunai', lockedAt: lockedAt),
        );
    // Pelanggan SUDAH dipilih → `_holdCurrent` (kasir_screen.dart) langsung
    // tahan TANPA membuka dialog label (`_askHoldLabel`) — menghindari
    // interaksi dialog/animasi yang tidak relevan dgn fitur Pra-Bayar yang
    // diuji di sini (lihat pola sama di `cart_sheet_hold_button_test.dart`).
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

    // Tombol "Tahan Pesanan" ada di cart bar bawah (ikon pause).
    await tester.tap(find.byIcon(Icons.pause_circle_outline).first);
    await tester.pumpAndSettle();

    final held = await db.select(db.heldOrders).get();
    expect(held, hasLength(1));
    final decoded = jsonDecode(held.single.cartJson) as Map<String, dynamic>;
    final prabayarRaw = decoded['prabayar'] as List;
    expect(prabayarRaw, hasLength(1));
    expect(prabayarRaw.single['amount'], 12000);
    expect(prabayarRaw.single['lockedAt'], lockedAt.millisecondsSinceEpoch);

    expect(container.read(cartPrabayarProvider(kMainCartId)), isEmpty,
        reason: 'provider aktif harus ikut ter-clear setelah hold (data '
            'pindah ke HeldOrders)');

    await drain(tester);
  });
}
