import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/license_provider.dart';
import 'package:the_pos/core/router/app_router.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): "bagaimana cara atur stok varian? Masih
/// belum ada UI nya" — dicek: stok varian sebelumnya cuma DITAMPILKAN
/// (label "Stok N" di baris varian), tidak bisa DIUBAH dari layar mana pun.
/// Fix: ikon "Sesuaikan stok varian" di tiap baris varian membuka dialog
/// "Sesuaikan Stok" yang sama dgn punya satuan produk utama.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedParentWithVariant() async {
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true))
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000)
        ]
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v-coklat', name: 'Coklat', parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'vu-coklat', productId: 'v-coklat', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'vt-coklat', productUnitId: 'vu-coklat', price: 5500));
    await db.adjustStock(productUnitId: 'vu-coklat', newQty: 3);
  }

  ProviderContainer buildContainer() {
    const fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Owner',
      deviceCode: 'K1',
      deviceRole: 'owner',
    );
    return ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      licenseProvider.overrideWith(
          (ref) => LicenseNotifier()..state = const LicenseState(exp: 'selamanya')),
    ]);
  }

  testWidgets(
      'ketuk ikon "Sesuaikan stok varian" -> ubah jadi 20 -> stok varian di '
      'DB berubah (BUKAN stok induk atau varian lain)', (tester) async {
    await seedParentWithVariant();
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = buildContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go('/produk/p1');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(await db.currentStock('vu-coklat'), 3);

    await tester.tap(find.byTooltip('Sesuaikan stok varian'));
    await tester.pumpAndSettle();
    expect(find.text('Sesuaikan Stok'), findsOneWidget);

    final qtyField = tester.widget<TextField>(find.ancestor(
      of: find.text('Stok baru'),
      matching: find.byType(TextField),
    ));
    qtyField.controller!.text = '20';
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(await db.currentStock('vu-coklat'), 20,
        reason: 'stok varian di DB harus berubah sesuai dialog');
    expect(await db.currentStock('u1'), 0,
        reason: 'stok produk induk tidak boleh ikut berubah');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'varian non-stok: ketuk ikon -> banner info, dialog Sesuaikan Stok '
      'TIDAK terbuka', (tester) async {
    await seedParentWithVariant();
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v-melon', name: 'Melon', parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'vu-melon',
        productId: 'v-melon',
        isBaseUnit: const Value(true),
        isNonStock: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'vt-melon', productUnitId: 'vu-melon', price: 5500));

    await pumpWithFakeApp(tester,
        db: db, child: const ProdukFormScreen(productId: 'p1'));

    final melonRow =
        find.ancestor(of: find.text('Melon'), matching: find.byType(Card));
    await tester.tap(find.descendant(
        of: melonRow, matching: find.byTooltip('Sesuaikan stok varian')));
    await tester.pumpAndSettle();

    expect(find.text('Sesuaikan Stok'), findsNothing,
        reason: 'varian non-stok tidak melacak stok, dialog tidak relevan');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
