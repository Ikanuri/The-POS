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

/// Item 54 — end-to-end: dari layar Kelola Kategori, tap kategori (BUKAN
/// long-press, yang sudah dipakai mode pilih-utk-hapus) membuka layar
/// pilih produk; centang produk LANGSUNG tersimpan hidup ke DB (live-toggle,
/// tanpa tombol "Terapkan" batch spt Item 52 lama).
void main() {
  testWidgets(
      'tap kategori -> centang produk -> langsung ter-assign ke DB '
      '(live-toggle)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(1), name: const Value('Minuman')));
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Teh Botol'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

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
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kelola Kategori'), findsOneWidget);
    expect(find.text('Minuman'), findsOneWidget);

    // Tap (BUKAN long-press) kategori -> buka layar pilih produk.
    await tester.tap(find.text('Minuman'));
    await tester.pumpAndSettle();

    expect(find.text('Produk — Minuman'), findsOneWidget);
    expect(find.text('Teh Botol'), findsOneWidget);

    // Centang produk -> live-toggle, tanpa tombol Terapkan.
    await tester.tap(find.text('Teh Botol'));
    await tester.pumpAndSettle();

    final p1 = await (db.select(db.products)..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(p1.productGroupId, 1);

    // Uncentang -> lepas lagi dari DB juga (langsung, tanpa navigasi balik).
    await tester.tap(find.text('Teh Botol'));
    await tester.pumpAndSettle();

    final p1After = await (db.select(db.products)..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(p1After.productGroupId, isNull);
  });
}
