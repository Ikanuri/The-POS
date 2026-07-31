import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/item_entry_sheet.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): format qty varian disamakan dgn Titip/
/// Ketinggalan — bisa ketik langsung (utk qty desimal), bukan cuma stepper
/// +/-1 polos spt sebelumnya.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<Product> seedProductWithVariant() async {
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Kopi Sachet'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 2000));

    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v1', name: 'Kopi Sachet Vanilla', parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'vu1', productId: 'v1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 'vt1', productUnitId: 'vu1', price: 2500));

    return (await db.searchProducts('')).firstWhere((p) => p.id == 'p1');
  }

  testWidgets(
      'qty varian bisa diketik langsung (desimal), bukan cuma stepper +/-1',
      (tester) async {
    final product = await seedProductWithVariant();
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

    expect(find.text('Kopi Sachet Vanilla'), findsOneWidget);

    // Ketik langsung qty varian (2.5) — mustahil dicapai stepper +/-1 murni.
    final variantRow = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_VariantRow');
    await tester.enterText(
        find.descendant(of: variantRow, matching: find.byType(TextField)),
        '2.5');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tambah ke Keranjang'));
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider(kMainCartId));
    final variantItem = cart.firstWhere((c) => c.productId == 'v1');
    expect(variantItem.qty, 2.5,
        reason: 'qty desimal (2.5) tersimpan persis, bukan dibulatkan');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('stepper +/-1 varian tetap berfungsi (kenyamanan qty bulat)',
      (tester) async {
    final product = await seedProductWithVariant();
    await pumpWithFakeApp(tester,
        db: db, child: ItemEntrySheet(product: product));

    final variantRow = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_VariantRow');
    final plusButton = find.descendant(
        of: variantRow, matching: find.byIcon(Icons.add_circle_outline));

    await tester.tap(plusButton);
    await tester.pumpAndSettle();
    await tester.tap(plusButton);
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: variantRow, matching: find.widgetWithText(TextField, '2')),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
