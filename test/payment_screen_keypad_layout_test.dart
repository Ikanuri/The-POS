import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// Item 26b+26c — tata letak kalkulator bayar (`_CashKeypadSheet`):
/// "Uang Pas" pindah sebaris dengan "Bayar" (bukan lagi di Wrap chip
/// pecahan uang), dan tombol "00" pindah sebaris dengan "0" (bukan lagi
/// sebaris dengan 7/8/9).
void main() {
  Future<AppDatabase> pumpPaymentWithCartOpen(WidgetTester tester) async {
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
    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'p1',
          productUnitId: 'u1',
          productName: 'Gula Pasir',
          unitName: 'Pcs',
          qty: 1,
          price: 15000,
          originalPrice: 15000,
          costPrice: 10000,
        ));

    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PaymentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Bayar Rp').first);
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets(
      '"Uang Pas" sebaris (Y sama) dengan tombol "Bayar", bukan lagi di '
      'Wrap chip pecahan uang', (tester) async {
    final db = await pumpPaymentWithCartOpen(tester);
    addTearDown(() async => db.close());

    expect(find.text('Uang Pas'), findsOneWidget);
    expect(find.text('Bayar'), findsOneWidget);

    final uangPasY = tester.getCenter(find.text('Uang Pas')).dy;
    final bayarY = tester.getCenter(find.text('Bayar')).dy;
    expect((uangPasY - bayarY).abs(), lessThan(2),
        reason: '"Uang Pas" dan "Bayar" harus sebaris (tombol setinggi '
            'sama di baris paling bawah)');

    // "Uang Pas" harus di KIRI "Bayar" (sekunder di kiri, primer di kanan).
    final uangPasX = tester.getCenter(find.text('Uang Pas')).dx;
    final bayarX = tester.getCenter(find.text('Bayar')).dx;
    expect(uangPasX, lessThan(bayarX));
  });

  testWidgets(
      'Item 49a — tombol "0"/"00"/"000" sebaris (Y sama) di baris paling '
      'bawah, BUKAN "000" sebaris dengan "7"', (tester) async {
    final db = await pumpPaymentWithCartOpen(tester);
    addTearDown(() async => db.close());

    final zeroY = tester.getCenter(find.text('0')).dy;
    final zeroZeroY = tester.getCenter(find.text('00')).dy;
    final threeZeroY = tester.getCenter(find.text('000')).dy;
    final sevenY = tester.getCenter(find.text('7')).dy;

    expect((zeroY - zeroZeroY).abs(), lessThan(2),
        reason: '"00" harus sebaris dengan "0"');
    expect((zeroY - threeZeroY).abs(), lessThan(2),
        reason: '"000" harus sebaris dengan "0" dan "00" (baris paling '
            'bawah), bukan lagi sebaris dengan "7 8 9"');
    expect((sevenY - zeroZeroY).abs(), greaterThan(10),
        reason: '"00"/"000" TIDAK sebaris dengan "7" (baris digit atas)');

    // "0" di KIRI "00" di KIRI "000" (urutan kalkulator).
    final zeroX = tester.getCenter(find.text('0')).dx;
    final zeroZeroX = tester.getCenter(find.text('00')).dx;
    final threeZeroX = tester.getCenter(find.text('000')).dx;
    expect(zeroX, lessThan(zeroZeroX));
    expect(zeroZeroX, lessThan(threeZeroX));
  });
}
