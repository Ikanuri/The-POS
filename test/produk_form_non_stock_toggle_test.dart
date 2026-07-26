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

/// Usulan user: produk UTAMA (bukan cuma varian, lihat `_variantDialog`'s
/// "Lacak stok varian") bisa diset non-stok. Toggle "Lacak stok" baru di
/// tiap kartu satuan form Edit Produk — matikan berarti satuan itu tidak
/// perlu dihitung stok (mis. jasa).
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Servis Ganti Oli'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1',
            productId: 'p1',
            unitTypeId: const Value(1),
            isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(
              id: 't1', productUnitId: 'u1', price: 25000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
  });
  tearDown(() => db.close());

  testWidgets(
      'toggle "Lacak stok" tampil default AKTIF, matikan lalu simpan -> '
      'productUnit.isNonStock jadi true di DB (lewat router sungguhan, '
      'krn Simpan Produk menutup layar via context.pop)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Owner',
      deviceCode: 'K1',
      deviceRole: 'owner',
    );
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      licenseProvider.overrideWith((ref) =>
          LicenseNotifier()..state = const LicenseState(exp: 'selamanya')),
    ]);
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    router.go('/produk/p1');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Lacak stok'), findsOneWidget);
    var toggle = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Lacak stok'));
    expect(toggle.value, isTrue, reason: 'default ON (produk biasa)');

    await tester.tap(find.widgetWithText(SwitchListTile, 'Lacak stok'));
    await tester.pumpAndSettle();

    toggle = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Lacak stok'));
    expect(toggle.value, isFalse);

    await tester.tap(find.text('Simpan Produk'));
    await tester.pumpAndSettle();

    final unit = await (db.select(db.productUnits)
          ..where((t) => t.id.equals('u1')))
        .getSingle();
    expect(unit.isNonStock, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'produk yang sudah non-stok di DB -> toggle "Lacak stok" tampil MATI',
      (tester) async {
    await (db.update(db.productUnits)..where((t) => t.id.equals('u1')))
        .write(const ProductUnitsCompanion(isNonStock: Value(true)));

    await pumpWithFakeApp(tester,
        db: db, child: const ProdukFormScreen(productId: 'p1'));

    final toggle = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Lacak stok'));
    expect(toggle.value, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
