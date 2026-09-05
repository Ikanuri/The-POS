import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_price_category_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/item_entry_sheet.dart';

/// Fase C "Kategori Harga" — `ItemEntrySheet` HARUS ikut baca
/// `cartPriceCategoryProvider` saat resolve harga awal, supaya kasir tidak
/// perlu sadar & toggle manual lagi begitu kategori sedang aktif.
void main() {
  late AppDatabase db;
  late Product product;
  late String catId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Beras'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'pt1',
          productUnitId: 'u1',
          price: 10000,
          costPrice: const Value(7000),
        ));
    catId = await db.addPriceCategory('Grosir');
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
          id: 'ap1',
          productUnitId: 'u1',
          label: 'Grosir',
          price: 8500,
          priceCategoryId: Value(catId),
        ));
    product = (await db.searchProducts('')).first;
  });

  tearDown(() async => db.close());

  TextField priceField(WidgetTester tester) => tester.widget<TextField>(
        find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.prefixText == 'Rp '),
      );

  Future<ProviderContainer> pumpSheet(WidgetTester tester,
      {String? activeCategoryId}) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Dev',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    if (activeCategoryId != null) {
      container
          .read(cartPriceCategoryProvider(kMainCartId).notifier)
          .setCategory(activeCategoryId);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child:
            MaterialApp(home: Scaffold(body: ItemEntrySheet(product: product))),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
      'kategori TIDAK aktif -> harga awal field = harga dasar normal',
      (tester) async {
    await pumpSheet(tester);
    expect(priceField(tester).controller!.text, '10.000');
  });

  testWidgets(
      'kategori AKTIF & produk terdaftar -> harga awal field SUDAH harga '
      'kategori (bukan harga dasar)', (tester) async {
    await pumpSheet(tester, activeCategoryId: catId);
    expect(priceField(tester).controller!.text, '8.500');
  });

  testWidgets(
      'kategori aktif, kasir TIDAK edit harga -> submit menyimpan '
      'priceFromCategoryId', (tester) async {
    final container = await pumpSheet(tester, activeCategoryId: catId);
    await tester.tap(find.text('Tambah ke Keranjang'));
    await tester.pumpAndSettle();

    final item =
        container.read(cartProvider(kMainCartId)).firstWhere((c) => true);
    expect(item.price, 8500);
    expect(item.priceFromCategoryId, catId);
    expect(item.priceOverridden, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'kategori aktif, kasir EDIT manual harga sebelum submit -> '
      'priceFromCategoryId dilewati (null) & priceOverridden true',
      (tester) async {
    final container = await pumpSheet(tester, activeCategoryId: catId);
    await tester.enterText(find.byWidget(priceField(tester)), '9999');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah ke Keranjang'));
    await tester.pumpAndSettle();

    final item =
        container.read(cartProvider(kMainCartId)).firstWhere((c) => true);
    expect(item.price, 9999);
    expect(item.priceFromCategoryId, isNull);
    expect(item.priceOverridden, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
