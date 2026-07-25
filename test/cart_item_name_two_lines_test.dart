import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Permintaan user — nama produk panjang di keranjang dulu terpotong 1
/// baris (ellipsis), sekarang boleh tumbuh sampai 2 baris sebelum dipotong.
void main() {
  const longNameItem = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Minyak Goreng Kemasan Ekonomis Super Hemat Ukuran Jumbo 5 Liter',
    unitName: 'Jerigen',
    qty: 1,
    price: 85000,
    originalPrice: 85000,
    costPrice: 60000,
  );

  testWidgets('nama produk panjang di baris keranjang boleh 2 baris (bukan 1)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
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
    container.read(cartProvider(kMainCartId).notifier).addItem(longNameItem);

    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: CartSheet(cartId: kMainCartId)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nameFinder = find.text(longNameItem.productName);
    expect(nameFinder, findsOneWidget);
    final textWidget = tester.widget<Text>(nameFinder);
    expect(textWidget.maxLines, 2,
        reason: 'nama produk panjang harus boleh tumbuh ke 2 baris, bukan '
            'terpotong 1 baris seperti sebelumnya');
  });
}
