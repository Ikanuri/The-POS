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

/// Item 52 ("Laci Meja") — toggle "Butuh Jaminan Fisik saat Antri" di form
/// Edit Produk. ON utk produk model tukar-wadah (LPG, galon, dst): antri
/// Pre-order stok kosong wajib titip wadah fisik, bukan cuma nomor urut.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Tabung LPG 3kg'),
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
              id: 't1', productUnitId: 'u1', price: 22000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
  });
  tearDown(() => db.close());

  testWidgets(
      'toggle "Butuh Jaminan Fisik" default MATI, nyalakan lalu simpan -> '
      'requiresDeposit jadi true di DB (lewat router sungguhan, krn Simpan '
      'Produk menutup layar via context.pop)', (tester) async {
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

    expect(find.text('Butuh Jaminan Fisik saat Antri'), findsOneWidget);
    var toggle = tester.widget<SwitchListTile>(find.widgetWithText(
        SwitchListTile, 'Butuh Jaminan Fisik saat Antri'));
    expect(toggle.value, isFalse, reason: 'default OFF (produk biasa)');

    await tester.tap(find.widgetWithText(
        SwitchListTile, 'Butuh Jaminan Fisik saat Antri'));
    await tester.pumpAndSettle();

    toggle = tester.widget<SwitchListTile>(find.widgetWithText(
        SwitchListTile, 'Butuh Jaminan Fisik saat Antri'));
    expect(toggle.value, isTrue);

    await tester.tap(find.text('Simpan Produk'));
    await tester.pumpAndSettle();

    final unit = await (db.select(db.productUnits)
          ..where((t) => t.id.equals('u1')))
        .getSingle();
    expect(unit.requiresDeposit, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'produk yang sudah requiresDeposit=true di DB -> toggle tampil AKTIF',
      (tester) async {
    await (db.update(db.productUnits)..where((t) => t.id.equals('u1')))
        .write(const ProductUnitsCompanion(requiresDeposit: Value(true)));

    await pumpWithFakeApp(tester,
        db: db, child: const ProdukFormScreen(productId: 'p1'));

    final toggle = tester.widget<SwitchListTile>(find.widgetWithText(
        SwitchListTile, 'Butuh Jaminan Fisik saat Antri'));
    expect(toggle.value, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
