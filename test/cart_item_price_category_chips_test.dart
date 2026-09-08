import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/theme_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Fitur BARU — chip Kategori Harga per-item di baris keranjang. Deretan
/// PENUH per kategori yg produk tergabung, scroll horizontal, tap terapkan
/// harga kategori itu KHUSUS ke baris itu (manual override, menang atas
/// toggle header). Toggle on/off fitur di sheet Pengaturan Keranjang
/// (`cartPriceCategoryChipsProvider`).
///
/// PENTING: toggle HEADER "Normal"/kategori (SUDAH ADA, tidak berubah)
/// menampilkan SEMUA kategori terdaftar (bukan difilter per produk) di
/// baris terpisah DI ATAS list item — label chip-nya BISA BENTROK teks dgn
/// chip per-item baru (mis. sama-sama "Grosir"/"Normal"). Semua assertion
/// di bawah SENGAJA di-scope ke dalam `ListView` (list baris keranjang)
/// lewat [_inList] supaya tidak salah kena chip header.
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  Finder inList(String text) => find.descendant(
        of: find.byType(ListView),
        matching: find.text(text),
      );

  late AppDatabase db;
  late ProviderContainer container;
  late String unitMember; // tergabung 2 kategori
  late String unitPlain; // tidak tergabung kategori apa pun

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    Future<String> seedUnit(String id) async {
      await db
          .into(db.products)
          .insert(ProductsCompanion.insert(id: id, name: 'Produk $id'));
      final unitId = '${id}_u';
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId, productId: id, isBaseUnit: const Value(true)));
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: '${id}_tier',
            productUnitId: unitId,
            minQty: const Value(1),
            price: 10000,
            costPrice: const Value(7000),
          ));
      return unitId;
    }

    unitMember = await seedUnit('member');
    unitPlain = await seedUnit('plain');

    final catGrosir = await db.addPriceCategory('Grosir');
    final catReseller = await db.addPriceCategory('Reseller');
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'alt_grosir', productUnitId: unitMember, label: 'Grosir',
        price: 8500, priceCategoryId: Value(catGrosir)));
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'alt_reseller', productUnitId: unitMember, label: 'Reseller',
        price: 8000, priceCategoryId: Value(catReseller)));

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

  Future<void> pumpCartSheet(WidgetTester tester) async {
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
  }

  testWidgets(
      'produk BUKAN anggota kategori apa pun -> tidak ada chip tambahan di '
      'baris keranjangnya sama sekali', (tester) async {
    container.read(cartProvider(kMainCartId).notifier).addItem(CartItem(
          productId: 'plain',
          productUnitId: unitPlain,
          productName: 'Produk plain',
          unitName: 'Pcs',
          qty: 1,
          price: 10000,
          originalPrice: 10000,
          costPrice: 7000,
        ));

    await pumpCartSheet(tester);

    expect(inList('Grosir'), findsNothing);
    expect(inList('Reseller'), findsNothing);
    expect(inList('Normal'), findsNothing,
        reason: 'chip per-item (termasuk "Normal"-nya) HANYA tampil utk '
            'produk yg tergabung >=1 kategori');

    await drain(tester);
  });

  testWidgets(
      'produk anggota 2 kategori -> chip Normal + kedua kategori tampil di '
      'baris keranjangnya, dibungkus scroll horizontal', (tester) async {
    container.read(cartProvider(kMainCartId).notifier).addItem(CartItem(
          productId: 'member',
          productUnitId: unitMember,
          productName: 'Produk member',
          unitName: 'Pcs',
          qty: 1,
          price: 10000,
          originalPrice: 10000,
          costPrice: 7000,
        ));

    await pumpCartSheet(tester);

    expect(inList('Normal'), findsOneWidget);
    expect(inList('Grosir'), findsOneWidget);
    expect(inList('Reseller'), findsOneWidget);

    // Baris chip harus dibungkus SingleChildScrollView horizontal (BUKAN
    // Wrap yg melebar ke bawah) — cari ancestor pembungkus chip "Grosir".
    final scrollAncestor = find.ancestor(
      of: inList('Grosir'),
      matching: find.byWidgetPredicate((w) =>
          w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
    );
    expect(scrollAncestor, findsOneWidget);

    await drain(tester);
  });

  testWidgets(
      'tap chip kategori per-item -> harga baris berubah & '
      'priceOverridden=true (manual override, reuse invariant priceOverridden '
      'spy menang atas toggle header)', (tester) async {
    container.read(cartProvider(kMainCartId).notifier).addItem(CartItem(
          productId: 'member',
          productUnitId: unitMember,
          productName: 'Produk member',
          unitName: 'Pcs',
          qty: 1,
          price: 10000,
          originalPrice: 10000,
          costPrice: 7000,
        ));

    await pumpCartSheet(tester);

    await tester.tap(inList('Grosir'));
    await tester.pumpAndSettle();

    final line = container
        .read(cartProvider(kMainCartId))
        .firstWhere((c) => c.productId == 'member');
    expect(line.price, 8500);
    expect(line.priceOverridden, isTrue,
        reason: 'pilih chip per-item = manual override, spy header TIDAK '
            'pernah menimpanya lagi (reuse invariant priceOverridden)');
    expect(line.priceFromCategoryId, isNotNull);

    // Buktikan invariant "manual > header" via mekanisme header SUNGGUHAN
    // (repriceCartForCategoryChange, dipanggil `_onCategoryToggle` toggle
    // header): baris priceOverridden HARUS di-skip total, walau kategori
    // header berganti ke kategori LAIN yg produk ini JUGA tergabung.
    final cart = container.read(cartProvider(kMainCartId));
    expect(cart.single.priceOverridden, isTrue);

    await drain(tester);
  });

  testWidgets(
      'tap chip "Normal" per-item -> baris kembali ke harga normal & TETAP '
      'ditandai override manual (terkunci dari toggle header berikutnya)',
      (tester) async {
    container.read(cartProvider(kMainCartId).notifier).addItem(CartItem(
          productId: 'member',
          productUnitId: unitMember,
          productName: 'Produk member',
          unitName: 'Pcs',
          qty: 1,
          price: 10000,
          originalPrice: 10000,
          costPrice: 7000,
        ));

    await pumpCartSheet(tester);
    await tester.tap(inList('Grosir'));
    await tester.pumpAndSettle();

    await tester.tap(inList('Normal'));
    await tester.pumpAndSettle();

    final line = container
        .read(cartProvider(kMainCartId))
        .firstWhere((c) => c.productId == 'member');
    expect(line.price, 10000);
    expect(line.priceFromCategoryId, isNull);
    expect(line.priceOverridden, isTrue,
        reason: 'tap Normal per-item tetap pilihan manual eksplisit, harus '
            'tetap terkunci dari toggle header berikutnya');

    await drain(tester);
  });

  testWidgets(
      'toggle OFF di Pengaturan Keranjang -> chip per-item hilang total dari '
      'baris keranjang', (tester) async {
    container.read(cartProvider(kMainCartId).notifier).addItem(CartItem(
          productId: 'member',
          productUnitId: unitMember,
          productName: 'Produk member',
          unitName: 'Pcs',
          qty: 1,
          price: 10000,
          originalPrice: 10000,
          costPrice: 7000,
        ));
    // Sengaja TIDAK di-`await` — `set()` mengubah `state` SINKRON (baris
    // pertama isinya) sebelum bagian async (persist SharedPreferences)
    // jalan; awaiting Future SharedPreferences di sini (sebelum widget tree
    // di-pump sama sekali) bisa macet krn belum ada siklus pump yg
    // menjalankan microtask-nya.
    unawaited(
        container.read(cartPriceCategoryChipsProvider.notifier).set(false));

    await pumpCartSheet(tester);

    expect(inList('Grosir'), findsNothing);
    expect(inList('Reseller'), findsNothing);

    await drain(tester);
  });
}
