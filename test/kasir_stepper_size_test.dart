import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Susulan keluhan missclick stepper +/- (sama akar dgn stepper baris
/// keranjang di cart_sheet.dart, lihat cart_stepper_size_test.dart) —
/// stepper kartu grid/baris list/baris varian di layar Kasir JUGA
/// diperbesar (grid 32->46, list 34->48, varian 28->42) dgn delta +14 yang
/// SAMA spt stepper keranjang, supaya konsisten. mainAxisExtent grid
/// (138->152) ikut ditambah supaya kartu tidak overflow.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  const fakeDevice = DeviceIdentity(
    storeUuid: 's',
    storeKey: 'k',
    storeName: 'Toko',
    deviceName: 'Kasir',
    deviceCode: 'K1',
    deviceRole: 'owner',
  );

  Future<void> pumpKasir(WidgetTester tester,
      {Size surface = const Size(360, 800)}) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider
            .overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirScreen()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> seedSimpleProduct({
    // Nama produk sengaja panjang — skenario paling padat utk kartu grid
    // 2 baris nama + stepper besar sekaligus.
    String name = 'Minyak Goreng Kemasan Ekonomis Super Hemat 2 Liter',
  }) async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: name));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 't1', productUnitId: 'u1', price: 25000));
  }

  Future<void> seedParentWithVariant() async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000));

    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v1', name: 'Coklat', parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'vu1', productId: 'v1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'vt1', productUnitId: 'vu1', price: 5500));
  }

  testWidgets(
      'kartu grid: stepper size 46, HP sempit 360x800 dgn nama panjang '
      'TIDAK overflow', (tester) async {
    await seedSimpleProduct();
    await pumpKasir(tester);

    final control = tester.widget<AddControl>(find.byType(AddControl).first);
    expect(control.size, 46);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('baris list (mode daftar): stepper size 48, TIDAK overflow',
      (tester) async {
    await seedSimpleProduct();
    await pumpKasir(tester);

    await tester.tap(find.byIcon(Icons.view_list_rounded));
    await tester.pumpAndSettle();

    final control = tester.widget<AddControl>(find.byType(AddControl).first);
    expect(control.size, 48);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('baris varian (dropdown inline): stepper size 42, TIDAK overflow',
      (tester) async {
    await seedParentWithVariant();
    await pumpKasir(tester);

    // Varian cuma tampil di mode daftar (long-press baris utk expand).
    await tester.tap(find.byIcon(Icons.view_list_rounded));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Pop Ice'));
    await tester.pumpAndSettle();
    expect(find.text('Coklat'), findsOneWidget);

    // Stepper kedua (setelah induk) = milik baris varian.
    final control = tester.widget<AddControl>(find.byType(AddControl).at(1));
    expect(control.size, 42);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
