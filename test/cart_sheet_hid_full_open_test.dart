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

/// Keranjang yang dibuka oleh scanner HID (`scrollToBottom: true`) terbuka
/// PENUH (0,95) — item terbaru (paling bawah) langsung terlihat. Dibuka
/// biasa tetap 0,7.
void main() {
  Future<double> initialSize(WidgetTester tester,
      {required bool scrollToBottom}) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'HP Kasir',
          deviceCode: 'K2',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'p1',
          productUnitId: 'u1',
          productName: 'Barang',
          unitName: 'Pcs',
          qty: 1,
          price: 1000,
          originalPrice: 1000,
          costPrice: 500,
        ));
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
                builder: (_) => CartSheet(
                    cartId: kMainCartId, scrollToBottom: scrollToBottom),
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    return tester
        .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet))
        .initialChildSize;
  }

  testWidgets('dibuka scanner HID -> penuh 0,95', (tester) async {
    expect(await initialSize(tester, scrollToBottom: true), 0.95);
  });

  testWidgets('dibuka biasa -> 0,7 (tidak berubah)', (tester) async {
    expect(await initialSize(tester, scrollToBottom: false), 0.7);
  });
}
