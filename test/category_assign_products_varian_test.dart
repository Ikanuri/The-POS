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

/// Bug dilaporkan user (Kategori PRODUK, bukan Kategori Harga — layar
/// `CategoryAssignProductsScreen`, dibuka dari "Kelola Kategori" -> tap
/// kategori): sama seperti bug di Kategori Harga, `db.searchProducts` yg
/// dipakai di sini juga tidak filter varian (produk anak) — varian ikut
/// lolos sbg baris `CheckboxListTile` TERPISAH.
///
/// Fix: varian di-nested-kan sbg dropdown inline di bawah baris induknya
/// (sama pola dgn Kategori Harga & halaman kasir), DENGAN tambahan logic
/// cascade: centang produk INDUK -> semua variannya ikut tercentang
/// otomatis (permintaan user eksplisit).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  Future<void> seedParentWithTwoVariants() async {
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(1), name: const Value('Pakaian')));

    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'parent', name: 'Kaos Polos'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'parent_u', productId: 'parent', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'parent_u': [
          PriceTiersCompanion.insert(
              id: 'parent_t', productUnitId: 'parent_u', price: 50000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    for (final v in [
      ('variant1', 'Kaos Polos - Merah'),
      ('variant2', 'Kaos Polos - Biru'),
    ]) {
      await db.into(db.products).insert(ProductsCompanion.insert(
          id: v.$1, name: v.$2, parentProductId: const Value('parent')));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: '${v.$1}_u', productId: v.$1, isBaseUnit: const Value(true)));
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: '${v.$1}_t', productUnitId: '${v.$1}_u', price: 55000));
    }
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Kasir',
      deviceCode: 'K1',
      deviceRole: 'owner',
    );

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      licenseProvider.overrideWith(
          (ref) => LicenseNotifier()..state = const LicenseState(exp: 'selamanya')),
    ]);
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    router.go('/produk/kategori');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pakaian'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'varian TIDAK muncul sbg baris list terpisah sebelum dropdown dibuka',
      (tester) async {
    await seedParentWithTwoVariants();
    await pumpScreen(tester);

    expect(find.text('Kaos Polos'), findsOneWidget);
    expect(find.text('Kaos Polos - Merah'), findsNothing);
    expect(find.text('Kaos Polos - Biru'), findsNothing);

    await drain(tester);
  });

  testWidgets(
      'ketuk panah -> varian tampil nested, centang varian sendiri TIDAK '
      'ikut mencentang induk', (tester) async {
    await seedParentWithTwoVariants();
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.text('Kaos Polos - Merah'), findsOneWidget);
    expect(find.text('Kaos Polos - Biru'), findsOneWidget);

    await tester.tap(find.text('Kaos Polos - Merah'));
    await tester.pumpAndSettle();

    final variant1 = await (db.select(db.products)
          ..where((t) => t.id.equals('variant1')))
        .getSingle();
    expect(variant1.productGroupId, 1);

    final parent = await (db.select(db.products)
          ..where((t) => t.id.equals('parent')))
        .getSingle();
    expect(parent.productGroupId, isNull,
        reason: 'centang varian sendiri tidak boleh ikut mencentang induk');

    final variant2 = await (db.select(db.products)
          ..where((t) => t.id.equals('variant2')))
        .getSingle();
    expect(variant2.productGroupId, isNull,
        reason: 'varian lain yang tidak disentuh tidak ikut berubah');

    await drain(tester);
  });

  testWidgets(
      'centang produk INDUK -> SEMUA varian ikut tercentang otomatis '
      '(cascade)', (tester) async {
    await seedParentWithTwoVariants();
    await pumpScreen(tester);

    // Centang badan baris induk (bukan panah expand).
    await tester.tap(find.text('Kaos Polos'));
    await tester.pumpAndSettle();

    final parent = await (db.select(db.products)
          ..where((t) => t.id.equals('parent')))
        .getSingle();
    expect(parent.productGroupId, 1);

    final variant1 = await (db.select(db.products)
          ..where((t) => t.id.equals('variant1')))
        .getSingle();
    final variant2 = await (db.select(db.products)
          ..where((t) => t.id.equals('variant2')))
        .getSingle();
    expect(variant1.productGroupId, 1,
        reason: 'centang induk harus ikut mencentang SEMUA variannya');
    expect(variant2.productGroupId, 1,
        reason: 'centang induk harus ikut mencentang SEMUA variannya');

    // Buka dropdown -> checkbox varian di UI juga sudah tercentang (bukan
    // cuma di DB), tanpa perlu reload manual.
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    final checkboxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(checkboxes.every((c) => c.value == true), isTrue,
        reason: 'semua checkbox (induk + 2 varian) harus tercentang di UI '
            'setelah cascade, tanpa reload manual');

    await drain(tester);
  });

  testWidgets(
      'uncentang produk INDUK TIDAK ikut mengeluarkan varian dari kategori '
      '(satu arah saja)', (tester) async {
    await seedParentWithTwoVariants();
    await db.setProductGroupMembership('parent', 1, true);
    await db.setProductGroupMembership('variant1', 1, true);
    await db.setProductGroupMembership('variant2', 1, true);

    await pumpScreen(tester);

    await tester.tap(find.text('Kaos Polos'));
    await tester.pumpAndSettle();

    final parent = await (db.select(db.products)
          ..where((t) => t.id.equals('parent')))
        .getSingle();
    expect(parent.productGroupId, isNull);

    final variant1 = await (db.select(db.products)
          ..where((t) => t.id.equals('variant1')))
        .getSingle();
    final variant2 = await (db.select(db.products)
          ..where((t) => t.id.equals('variant2')))
        .getSingle();
    expect(variant1.productGroupId, 1,
        reason: 'uncentang induk sengaja TIDAK cascade -- varian bisa '
            'sengaja dipertahankan independen');
    expect(variant2.productGroupId, 1);

    await drain(tester);
  });

  testWidgets('produk tanpa varian TIDAK dapat tombol expand', (tester) async {
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(1), name: const Value('Pakaian')));
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'solo', name: 'Topi'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'solo_u', productId: 'solo', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'solo_u': [
          PriceTiersCompanion.insert(
              id: 'solo_t', productUnitId: 'solo_u', price: 20000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    await pumpScreen(tester);

    expect(find.text('Topi'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing);

    await drain(tester);
  });
}
