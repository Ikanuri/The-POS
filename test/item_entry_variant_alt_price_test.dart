import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/item_entry_sheet.dart';
import 'package:the_pos/core/theme/app_theme.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): "Harga lain juga, bagaimana cara
/// menggunakannya untuk varian?" — dicek: "Harga Lain" varian sudah bisa
/// disimpan lewat dialog Tambah/Edit Varian, tapi sebelumnya TIDAK PERNAH
/// bisa dipakai saat jual (harga varian di keranjang selalu harga dasar
/// mentah, menu popup harga tidak ada sama sekali di baris varian). Fix:
/// ikon popup "Pilih harga" muncul di baris varian bila varian punya Harga
/// Lain, memilihnya mengubah harga yang benar-benar disimpan ke keranjang.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<Product> seedParentWithVariant() async {
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000));

    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v-coklat', name: 'Coklat', parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'vu-coklat', productId: 'v-coklat', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'vt-coklat', productUnitId: 'vu-coklat', price: 5500));
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'vap-coklat',
        productUnitId: 'vu-coklat',
        label: 'Toko A',
        price: 4500));

    return (await db.searchProducts('')).firstWhere((p) => p.id == 'p1');
  }

  testWidgets(
      'varian tanpa Harga Lain -> tidak ada ikon pilih harga di barisnya',
      (tester) async {
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000));
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v-melon', name: 'Melon', parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'vu-melon', productId: 'v-melon', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'vt-melon', productUnitId: 'vu-melon', price: 5500));
    final product = (await db.searchProducts('')).firstWhere((p) => p.id == 'p1');

    await pumpWithFakeApp(tester,
        db: db, child: ItemEntrySheet(product: product));

    final row = find.ancestor(
        of: find.text('Melon'),
        matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_VariantRow'));
    expect(find.descendant(of: row, matching: find.byIcon(Icons.sell_outlined)),
        findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'varian dgn Harga Lain: pilih "Toko A" lewat menu -> harga di baris '
      'berubah & tersimpan ke keranjang, BUKAN harga dasar', (tester) async {
    final product = await seedParentWithVariant();
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(body: ItemEntrySheet(product: product))),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.ancestor(
        of: find.text('Coklat'),
        matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_VariantRow'));
    expect(find.descendant(of: row, matching: find.textContaining('5.500')),
        findsOneWidget,
        reason: 'awalnya harga dasar varian 5500');

    await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.sell_outlined)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toko A (${formatRupiah(4500)})'));
    await tester.pumpAndSettle();

    expect(find.descendant(of: row, matching: find.textContaining('4.500')),
        findsOneWidget,
        reason: 'harga di baris varian harus berubah ke Harga Lain terpilih');

    // Set qty varian ke 2, lalu tambah ke keranjang.
    await tester.enterText(
        find.descendant(of: row, matching: find.byType(TextField)), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah ke Keranjang'));
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider(kMainCartId));
    final line = cart.firstWhere((c) => c.productId == 'v-coklat');
    expect(line.price, 4500,
        reason: 'harga tersimpan di keranjang harus Harga Lain, bukan harga '
            'dasar (5500) mentah');
    expect(line.qty, 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
