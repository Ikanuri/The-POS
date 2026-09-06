import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/services/price_service.dart';
import 'package:the_pos/core/theme/app_theme.dart' show formatRupiah;
import 'package:the_pos/features/kasir/cart_price_category_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/item_entry_sheet.dart';

/// Bug user: "override harga produk yg ada di kategori tertentu, mengapa
/// harga dasar masih tetap harga kategori tersebut ketika diswitch kembali
/// ke kategori normal?"
///
/// Reproduksi: chip/label "Harga dasar" di `ItemEntrySheet` SEBELUM fix ini
/// menampilkan & MENERAPKAN harga KATEGORI (bukan harga dasar sejati produk)
/// selama kategori aktif & produk terdaftar di kategori itu — krn field
/// `_UnitOption.basePrice`/`_VariantOption.price` dipakai utk DUA hal
/// sekaligus (harga yg SEDANG BERLAKU/pre-fill, DAN acuan "harga dasar" chip)
/// walau isinya SUDAH hasil resolve kategori. Fix: field baru `trueBasePrice`
/// (resolve KEDUA kali TANPA `activeCategoryId`) khusus utk chip ini.
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
          price: 10000, // harga dasar SEJATI
          costPrice: const Value(7000),
        ));
    catId = await db.addPriceCategory('Grosir');
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
          id: 'ap1',
          productUnitId: 'u1',
          label: 'Grosir',
          price: 8000,
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
      {String? activeCategoryId, String cartId = kMainCartId}) async {
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
          .read(cartPriceCategoryProvider(cartId).notifier)
          .setCategory(activeCategoryId);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: ItemEntrySheet(product: product, cartId: cartId))),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets(
      'kategori aktif & produk anggota -> chip "Harga dasar" menampilkan '
      'harga dasar SEJATI (10.000), BUKAN harga kategori (8.000)',
      (tester) async {
    await pumpSheet(tester, activeCategoryId: catId);
    // Field harga pre-filled dgn harga kategori (perilaku Fase C yg benar).
    expect(priceField(tester).controller!.text, '8.000');

    // Chip "Harga dasar" di dropdown pilihan harga HARUS 10.000 (dasar
    // sejati), bukan 8.000 (kategori yg kebetulan sedang aktif/pre-filled).
    expect(find.text(formatRupiah(10000)), findsWidgets);
    await drain(tester);
  });

  testWidgets(
      'tap chip "Harga dasar" saat kategori aktif -> field ganti ke harga '
      'dasar sejati (10.000) & ditandai override (bukan tetap 8.000)',
      (tester) async {
    await pumpSheet(tester, activeCategoryId: catId);
    expect(priceField(tester).controller!.text, '8.000');

    await tester.tap(find.text(formatRupiah(10000)));
    await tester.pumpAndSettle();

    expect(priceField(tester).controller!.text, '10.000');
    expect(find.byIcon(Icons.edit), findsOneWidget); // penanda override

    await tester.tap(find.text('Tambah ke Keranjang'));
    await tester.pumpAndSettle();
    await drain(tester);
  });

  testWidgets(
      'SKENARIO PENUH LAPORAN USER: override manual saat kategori aktif -> '
      'toggle kategori balik ke Normal -> harga TETAP nilai override, '
      'BUKAN balik ke harga kategori lama', (tester) async {
    final container = await pumpSheet(tester, activeCategoryId: catId);
    await tester.enterText(find.byWidget(priceField(tester)), '7000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah ke Keranjang'));
    await tester.pumpAndSettle();

    var item = container.read(cartProvider(kMainCartId)).first;
    expect(item.price, 7000);
    expect(item.priceOverridden, isTrue);
    expect(item.priceFromCategoryId, isNull);

    // Simulasikan toggle kategori kembali ke Normal (persis alur
    // `cart_sheet.dart`: reprice SEBELUM state kategori diubah).
    final priceService = PriceService(db);
    final repriced = await repriceCartForCategoryChange(
      priceService: priceService,
      cart: container.read(cartProvider(kMainCartId)),
      newCategoryId: null,
    );
    container.read(cartProvider(kMainCartId).notifier).replaceAll(repriced);
    container.read(cartPriceCategoryProvider(kMainCartId).notifier).clear();

    item = container.read(cartProvider(kMainCartId)).first;
    expect(item.price, 7000, reason: 'harga override kasir harus tetap');
    expect(item.priceOverridden, isTrue);

    await drain(tester);
  });

  testWidgets(
      'REGRESI: kategori TIDAK aktif -> chip "Harga dasar" & perilaku '
      'override SAMA PERSIS spt sebelum Fase C (base = 10.000)',
      (tester) async {
    await pumpSheet(tester);
    expect(priceField(tester).controller!.text, '10.000');
    expect(find.text(formatRupiah(10000)), findsWidgets);
    await drain(tester);
  });

  testWidgets(
      'REGRESI: kategori aktif TAPI produk BUKAN anggota kategori itu -> '
      'basePrice & chip "Harga dasar" tetap harga NORMAL (10.000)',
      (tester) async {
    // Produk kedua yang TIDAK didaftarkan ke kategori manapun.
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p2', name: 'Gula'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u2', productId: 'p2', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'pt2',
          productUnitId: 'u2',
          price: 12000,
          costPrice: const Value(9000),
        ));
    final gula = (await db.searchProducts('Gula')).first;

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
    container
        .read(cartPriceCategoryProvider(kMainCartId).notifier)
        .setCategory(catId);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: ItemEntrySheet(product: gula))),
      ),
    );
    await tester.pumpAndSettle();

    expect(priceField(tester).controller!.text, '12.000');
    expect(find.text(formatRupiah(12000)), findsWidgets);
    await drain(tester);
  });
}
