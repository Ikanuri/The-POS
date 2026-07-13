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

  testWidgets('tombol "00" sebaris (Y sama) dengan "0", BUKAN dengan "7"',
      (tester) async {
    final db = await pumpPaymentWithCartOpen(tester);
    addTearDown(() async => db.close());

    final zeroY = tester.getCenter(find.text('0')).dy;
    final zeroZeroY = tester.getCenter(find.text('00')).dy;
    final sevenY = tester.getCenter(find.text('7')).dy;

    expect((zeroY - zeroZeroY).abs(), lessThan(2),
        reason: '"00" harus sebaris dengan "0"');
    expect((sevenY - zeroZeroY).abs(), greaterThan(10),
        reason: '"00" TIDAK lagi sebaris dengan "7" (baris digit atas)');

    // "000" masih ada (dipindah ke baris digit, bukan dihapus).
    expect(find.text('000'), findsOneWidget);
    final threeZeroY = tester.getCenter(find.text('000')).dy;
    expect((threeZeroY - sevenY).abs(), lessThan(2),
        reason: '"000" pindah ke baris "7 8 9" (bekas slot "00")');
  });
}
