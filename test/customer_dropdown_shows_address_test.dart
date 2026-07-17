import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// Permintaan user: alamat pelanggan ditampilkan di bawah nama di
/// dropdown/list saran pelanggan — mencegah salah pilih kalau ada 2
/// pelanggan dengan nama yang sama.
void main() {
  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Gula Pasir',
    unitName: 'Pcs',
    qty: 1,
    price: 15000,
    originalPrice: 15000,
    costPrice: 10000,
  );

  testWidgets(
      'dropdown saran pelanggan di modal checkout menampilkan alamat di '
      'bawah nama — mencegah salah pilih nama kembar', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'c1',
          name: 'Budi',
          address: const Value('Jl. Mawar No. 1'),
        ));
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'c2',
          name: 'Budi',
          address: const Value('Jl. Melati No. 9'),
        ));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Kasir',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(kMainCartId).notifier).addItem(item);

    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PaymentScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Budi');
    await tester.pumpAndSettle();

    expect(find.text('Jl. Mawar No. 1'), findsOneWidget);
    expect(find.text('Jl. Melati No. 9'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
