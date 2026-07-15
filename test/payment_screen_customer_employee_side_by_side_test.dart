import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// Permintaan user: field Pelanggan & Pegawai di modal checkout ditaruh
/// sejajar beriringan (side-by-side), bukan ditumpuk vertikal.
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

  testWidgets('label Pelanggan & Pegawai sejajar (sama tinggi, beda kolom)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

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

    final pelangganLabel = find.text('Pelanggan');
    final pegawaiLabel = find.text('Pegawai');
    expect(pelangganLabel, findsOneWidget);
    expect(pegawaiLabel, findsOneWidget);

    final pelangganPos = tester.getTopLeft(pelangganLabel);
    final pegawaiPos = tester.getTopLeft(pegawaiLabel);

    // Sejajar (side-by-side): baris (Y) sama, kolom (X) beda — Pegawai
    // ada di sebelah kanan Pelanggan.
    expect(pelangganPos.dy, closeTo(pegawaiPos.dy, 1.0),
        reason: 'kedua label harus di baris yang sama (sejajar horizontal)');
    expect(pegawaiPos.dx, greaterThan(pelangganPos.dx),
        reason: 'Pegawai harus di sebelah kanan Pelanggan');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
