import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Nama (+ alamat) pelanggan di bawah judul "Keranjang #n": pelanggan tetap
/// terracotta + alamat; ad-hoc warna teks biasa (hitam) tanpa alamat.
void main() {
  Future<void> open(WidgetTester tester, AppDatabase db,
      {required String? customerId, required String name}) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 'u',
          storeKey: 'k',
          storeName: 'Toko Uji',
          deviceName: 'Kasir Uji',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'p1',
          productUnitId: 'u1',
          productName: 'Gula',
          unitName: 'Pcs',
          qty: 1,
          price: 15000,
          originalPrice: 15000,
          costPrice: 10000,
        ));
    container
        .read(cartMetaProvider(kMainCartId).notifier)
        .setCustomer(customerId, name);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => const CartSheet()),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('pelanggan tetap: nama terracotta + alamat lebih tipis',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await db.into(db.customers).insert(CustomersCompanion.insert(
        id: 'C1', name: 'Bu Sari', address: const Value('Jl. Melati 5')));
    await open(tester, db, customerId: 'C1', name: 'Bu Sari');
    final name =
        tester.widget<Text>(find.byKey(const ValueKey('cart-customer-name')));
    final addr = tester
        .widget<Text>(find.byKey(const ValueKey('cart-customer-address')));
    expect(name.data, 'Bu Sari');
    expect(name.style!.color, AppTheme.accent);
    expect(addr.data, 'Jl. Melati 5');
    expect(
        addr.style!.fontWeight!.value, lessThan(name.style!.fontWeight!.value));
    expect(addr.style!.fontSize!, lessThan(name.style!.fontSize!));
    expect(tester.takeException(), isNull);
    await drain(tester);
  });

  testWidgets('ad-hoc: nama warna biasa (bukan terracotta), tanpa alamat',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await open(tester, db, customerId: null, name: 'Pak Budi');
    final name =
        tester.widget<Text>(find.byKey(const ValueKey('cart-customer-name')));
    expect(name.data, 'Pak Budi');
    expect(name.style!.color, isNot(AppTheme.accent));
    expect(find.byKey(const ValueKey('cart-customer-address')), findsNothing);
    await drain(tester);
  });
}
