import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_price_category_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Bug: `cartPriceCategoryProvider(kMainCartId)` (toggle header "Normal"/
/// kategori) SINGLETON per-cartId, bukan per-transaksi -> kalau tidak
/// direset, toggle yg diaktifkan di transaksi SEBELUMNYA nempel ke
/// transaksi berikutnya (baik setelah checkout sukses maupun setelah
/// kosongkan keranjang manual).
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Gula Pasir'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 't1',
          productUnitId: 'u1',
          minQty: const Value(1),
          price: 15000,
          costPrice: const Value(10000),
        ));
    await db.addPriceCategory('Grosir');

    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko Uji',
          deviceName: 'Kasir Uji',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  testWidgets(
      'checkout sukses -> toggle kategori header direset ke Normal utk '
      'transaksi berikutnya', (tester) async {
    // Aktifkan toggle kategori sebelum checkout.
    container
        .read(cartPriceCategoryProvider(kMainCartId).notifier)
        .setCategory('dummy-cat-id');
    expect(container.read(cartPriceCategoryProvider(kMainCartId)),
        'dummy-cat-id');

    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'p1',
          productUnitId: 'u1',
          productName: 'Gula Pasir',
          unitName: 'Kg',
          qty: 1,
          price: 15000,
          originalPrice: 15000,
          costPrice: 10000,
        ));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PaymentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Bayar Rp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uang Pas'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Bayar'));
    await tester.pumpAndSettle();

    expect(container.read(cartPriceCategoryProvider(kMainCartId)), isNull,
        reason: 'toggle header harus balik ke Normal setelah checkout '
            'sukses, tidak nempel ke transaksi berikutnya');

    await drain(tester);
  });

  testWidgets(
      'kosongkan keranjang manual -> toggle kategori header ikut direset',
      (tester) async {
    container
        .read(cartPriceCategoryProvider(kMainCartId).notifier)
        .setCategory('dummy-cat-id');
    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'p1',
          productUnitId: 'u1',
          productName: 'Gula Pasir',
          unitName: 'Kg',
          qty: 1,
          price: 15000,
          originalPrice: 15000,
          costPrice: 10000,
        ));

    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => const CartSheet(cartId: kMainCartId),
                ),
                child: const Text('buka keranjang'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka keranjang'));
    await tester.pumpAndSettle();

    // Tap ikon tempat sampah (Kosongkan Keranjang) lalu konfirmasi.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Kosongkan'));
    await tester.pumpAndSettle();

    expect(container.read(cartPriceCategoryProvider(kMainCartId)), isNull,
        reason: 'kosongkan keranjang manual harus ikut mereset toggle '
            'kategori header, bukan cuma isi keranjang');

    await drain(tester);
  });
}
