import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Susulan (permintaan user) — fitur Pra-Bayar: ringkasan nominal yang sudah
/// terkunci di keranjang SEBELUM ditahan sebelumnya tidak tampak sama sekali
/// di kartu antrian ("Ditahan"), baru kelihatan setelah kartu di-tap &
/// keranjang dibuka. Sekarang kartu langsung menampilkan badge kecil
/// "Pra-Bayar Rp X" (lihat `_HeldCard` di `kasir_screen.dart`), dibaca dari
/// `HeldOrders.cartJson` key "prabayar" via `_parseHeldPayload` — TANPA perlu
/// tap kartu itu dulu.
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

  Future<ProviderContainer> pumpQueue(WidgetTester tester, AppDatabase db) async {
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
    return container;
  }

  testWidgets(
      'kartu antrian dgn entri Pra-Bayar tersimpan -> badge "Pra-Bayar Rp X" '
      'langsung tampil TANPA perlu tap kartu dulu', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    await db.holdOrder(
      id: 'ho-1',
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
            'lockedAt': DateTime(2026, 1, 5, 9, 15).millisecondsSinceEpoch,
          },
        ],
      }),
    );

    await pumpQueue(tester, db);

    expect(find.textContaining('Pra-Bayar'), findsOneWidget);
    expect(find.textContaining(formatRupiah(15000)), findsOneWidget);

    await drain(tester);
  });

  testWidgets(
      'kartu antrian TANPA entri Pra-Bayar -> badge tidak muncul sama sekali',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    await db.holdOrder(
      id: 'ho-2',
      label: 'Pak Budi',
      cartJson: jsonEncode({
        'items': [item.toJson()],
        'meta': <String, dynamic>{},
      }),
    );

    await pumpQueue(tester, db);

    expect(find.textContaining('Pra-Bayar'), findsNothing);

    await drain(tester);
  });
}
