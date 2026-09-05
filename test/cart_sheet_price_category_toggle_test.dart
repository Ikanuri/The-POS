import 'package:drift/drift.dart' show Value;
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

/// Fase C "Kategori Harga" — level UI (`CartSheet`): baris chip toggle
/// kategori aktif, gerbang izin `override_harga`, re-price baris keranjang
/// saat toggle berganti, & indikator visual "harga dari kategori" (BEDA
/// dari ikon pensil override manual).
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<String> seedProductWithCategory(
    AppDatabase db, {
    required String productId,
    required int basePrice,
    required int costPrice,
    required int categoryPrice,
    required String categoryName,
  }) async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: productId, name: 'P $productId'));
    final unitId = '${productId}_u';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId, productId: productId, isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: '${productId}_tier',
          productUnitId: unitId,
          minQty: const Value(1),
          price: basePrice,
          costPrice: Value(costPrice),
        ));
    final catId = await db.addPriceCategory(categoryName);
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
          id: '${productId}_alt',
          productUnitId: unitId,
          label: categoryName,
          price: categoryPrice,
          priceCategoryId: Value(catId),
        ));
    return unitId;
  }

  Future<(AppDatabase, ProviderContainer, String)> pumpCartSheetOpen(
    WidgetTester tester, {
    required String deviceRole,
    required String categoryProductUnitId,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    final unitId = await seedProductWithCategory(
      db,
      productId: 'p1',
      basePrice: 10000,
      costPrice: 7000,
      categoryPrice: 8500,
      categoryName: 'Grosir',
    );

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'HP Kasir 1',
          deviceCode: 'K1',
          deviceRole: deviceRole,
        )),
    ]);
    addTearDown(container.dispose);

    container.read(cartProvider(kMainCartId).notifier).addItem(CartItem(
          productId: 'p1',
          productUnitId: unitId,
          productName: 'P p1',
          unitName: 'Pcs',
          qty: 1,
          price: 10000,
          originalPrice: 10000,
          costPrice: 7000,
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
    return (db, container, unitId);
  }

  testWidgets(
      'owner: chip "Normal" + kategori terdaftar tampil, tap kategori '
      're-price baris terdaftar + tampilkan badge sell_outlined',
      (tester) async {
    final (db, container, unitId) = await pumpCartSheetOpen(tester,
        deviceRole: 'owner', categoryProductUnitId: 'p1_u');
    addTearDown(() async => db.close());

    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Grosir'), findsOneWidget);
    expect(find.byIcon(Icons.sell_outlined), findsNothing,
        reason: 'belum toggle -> belum ada badge kategori');

    await tester.tap(find.text('Grosir'));
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider(kMainCartId));
    final line = cart.firstWhere((c) => c.productUnitId == unitId);
    expect(line.price, 8500);
    expect(line.priceFromCategoryId, isNotNull);
    expect(line.priceOverridden, isFalse,
        reason: 'toggle kategori TIDAK PERNAH menandai priceOverridden');
    expect(find.byIcon(Icons.sell_outlined), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsNothing,
        reason: 'ikon pensil override manual harus TIDAK ikut muncul');

    // Matikan lagi -> kembali ke harga normal.
    await tester.tap(find.text('Normal'));
    await tester.pumpAndSettle();
    final cart2 = container.read(cartProvider(kMainCartId));
    final line2 = cart2.firstWhere((c) => c.productUnitId == unitId);
    expect(line2.price, 10000);
    expect(line2.priceFromCategoryId, isNull);
    expect(find.byIcon(Icons.sell_outlined), findsNothing);

    await drain(tester);
  });

  testWidgets(
      'baris priceOverridden TIDAK PERNAH ikut berubah walau toggle '
      'kategori aktif & produknya terdaftar', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final unitId = await seedProductWithCategory(
      db,
      productId: 'p1',
      basePrice: 10000,
      costPrice: 7000,
      categoryPrice: 8500,
      categoryName: 'Grosir',
    );

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
    container.read(cartProvider(kMainCartId).notifier).addItem(CartItem(
          productId: 'p1',
          productUnitId: unitId,
          productName: 'P p1',
          unitName: 'Pcs',
          qty: 1,
          price: 12345, // sudah diedit manual kasir sebelumnya
          originalPrice: 10000,
          costPrice: 7000,
          priceOverridden: true,
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

    await tester.tap(find.text('Grosir'));
    await tester.pumpAndSettle();

    final line =
        container.read(cartProvider(kMainCartId)).firstWhere((c) => true);
    expect(line.price, 12345, reason: 'override manual harus tetap menang');
    expect(line.priceFromCategoryId, isNull);
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.sell_outlined), findsNothing);

    await drain(tester);
  });

  testWidgets(
      'kasir TANPA izin override_harga: baris chip toggle TIDAK tampil sama '
      'sekali', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final unitId = await seedProductWithCategory(
      db,
      productId: 'p1',
      basePrice: 10000,
      costPrice: 7000,
      categoryPrice: 8500,
      categoryName: 'Grosir',
    );

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Kasir',
          deviceCode: 'K1',
          deviceRole: 'kasir',
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(kMainCartId).notifier).addItem(CartItem(
          productId: 'p1',
          productUnitId: unitId,
          productName: 'P p1',
          unitName: 'Pcs',
          qty: 1,
          price: 10000,
          originalPrice: 10000,
          costPrice: 7000,
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

    expect(find.text('Grosir'), findsNothing);
    expect(find.text('Normal'), findsNothing);

    await drain(tester);
  });

  testWidgets(
      'kasir DENGAN izin override_harga: baris chip toggle tampil',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final unitId = await seedProductWithCategory(
      db,
      productId: 'p1',
      basePrice: 10000,
      costPrice: 7000,
      categoryPrice: 8500,
      categoryName: 'Grosir',
    );
    await db.into(db.kasirPermissions).insertOnConflictUpdate(
        const KasirPermissionsCompanion(
            permissionKey: Value('override_harga'), isEnabled: Value(true)));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Kasir',
          deviceCode: 'K1',
          deviceRole: 'kasir',
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(kMainCartId).notifier).addItem(CartItem(
          productId: 'p1',
          productUnitId: unitId,
          productName: 'P p1',
          unitName: 'Pcs',
          qty: 1,
          price: 10000,
          originalPrice: 10000,
          costPrice: 7000,
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

    expect(find.text('Grosir'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);

    await drain(tester);
  });

  testWidgets(
      'owner tapi BELUM ada PriceCategories sama sekali: baris chip TIDAK '
      'tampil (tidak ada gunanya)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'P'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'p1_u', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'p1_tier',
          productUnitId: 'p1_u',
          minQty: const Value(1),
          price: 10000,
          costPrice: const Value(7000),
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
    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'p1',
          productUnitId: 'p1_u',
          productName: 'P',
          unitName: 'Pcs',
          qty: 1,
          price: 10000,
          originalPrice: 10000,
          costPrice: 7000,
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

    expect(find.text('Normal'), findsNothing);

    await drain(tester);
  });
}
