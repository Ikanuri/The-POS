import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// Test Tier 2 (widget) — modal bayar sekarang punya DUA tombol terpisah
/// ("Bayar {total}" hijau, "Bayar Nanti" merah) menggantikan chip "Bayar
/// Nanti" yang dulu tercampur di baris Metode Pembayaran.
void main() {
  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Gula Pasir',
    unitName: 'Pcs',
    qty: 2,
    price: 15000,
    originalPrice: 15000,
    costPrice: 10000,
  );

  testWidgets(
      'ada 2 tombol terpisah: Bayar {total} (hijau) dan Bayar Nanti (merah); '
      'chip "Bayar Nanti" TIDAK lagi ada di baris Metode Pembayaran',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'Kasir Uji',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(kMainCartId).notifier).addItem(item);

    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PaymentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Tombol utama menampilkan "Bayar Rp 30.000" (2 x 15.000).
    expect(find.textContaining('Bayar Rp'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Bayar Nanti'), findsOneWidget);

    // Chip metode pembayaran TIDAK lagi berlabel "Bayar Nanti" — hanya
    // tombol dedicated di bar bawah yang berlabel itu (tepat satu).
    expect(find.text('Bayar Nanti'), findsOneWidget);

    final greenBtn = tester.widget<FilledButton>(
      find.ancestor(
        of: find.textContaining('Bayar Rp'),
        matching: find.byType(FilledButton),
      ),
    );
    final greenStyle = greenBtn.style!.backgroundColor!.resolve({});
    expect(greenStyle, const Color(0xFF22C55E));

    final redBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Bayar Nanti'),
    );
    final redStyle = redBtn.style!.backgroundColor!.resolve({});
    expect(redStyle, isNot(const Color(0xFF22C55E)));

    await db.close();
  });
}
