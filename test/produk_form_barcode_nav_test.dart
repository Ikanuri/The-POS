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

/// Sebelum ini, `BarcodeScreen` (fitur "Generate Barcode" + "Cetak Label")
/// SUDAH terdaftar sbg route (`/produk/:id/barcode`) dan sudah dites
/// sendiri, TAPI TIDAK ADA satu pun tombol di UI yang menavigasi ke situ —
/// route-nya "yatim", tidak bisa dijangkau pengguna sama sekali. Test ini
/// membuktikan tombol ikon baru di AppBar `ProdukFormScreen` benar-benar
/// menavigasi ke `BarcodeScreen` lewat router SUNGGUHAN (bukan cuma
/// `pumpWithFakeApp` tanpa router — itu tidak akan menangkap kelas bug
/// "route yatim" ini sama sekali).
void main() {
  testWidgets(
      'tombol ikon "Barcode & Cetak Label" di AppBar Edit Produk → navigasi '
      'ke BarcodeScreen (bukan route yatim)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Mie Sedap'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(
              id: 't1', productUnitId: 'u1', price: 2500),
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
    router.go('/produk/p1');

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

    expect(find.text('Edit Produk'), findsOneWidget);
    expect(find.byTooltip('Barcode & Cetak Label'), findsOneWidget);

    await tester.tap(find.byTooltip('Barcode & Cetak Label'));
    await tester.pumpAndSettle();

    // BarcodeScreen sungguhan terbuka — appbar-nya nampilkan nama produk,
    // dan (krn u1 belum punya barcode) tombol Generate Barcode tampil.
    expect(find.text('Generate Barcode'), findsOneWidget);

    // Drain drift StreamProvider (mis. watchLowStockCount() dipakai layar
    // shell/produk) — tanpa ini test bisa HANG "Timer is still pending"
    // saat disposal walau test-nya cuma baca (gotcha CLAUDE.md).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
