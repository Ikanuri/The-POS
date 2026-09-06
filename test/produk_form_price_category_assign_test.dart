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
import 'package:the_pos/core/utils/price_category_calc.dart';

/// Susulan (permintaan user): jalur "assign ke Kategori Harga" langsung dari
/// Edit Produk, section "Harga Lain (opsional)" — ikon `Icons.sell_outlined`
/// di tiap baris membuka picker kategori + editor margin
/// (`kategori_harga_screen.dart`'s `_MarginEditorSheet` diekstrak jadi
/// `PriceCategoryMarginSheet` biar bisa dipakai ulang dari sini TANPA
/// menulis DB sendiri — hasil ditahan di state lokal sampai tombol "Simpan
/// Produk" ditekan, pola sama seperti Harga Lain manual).
///
/// Dites lewat router SUNGGUHAN (bukan `pumpWithFakeApp`) — "Simpan Produk"
/// menutup layar via `context.pop()` (go_router), yang butuh `GoRouter`
/// nyata di context (pola sama dgn `produk_form_non_stock_toggle_test.dart`).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String> seedProduct() => db.saveProduct(
        product: ProductsCompanion.insert(id: 'p1', name: 'Beras'),
        units: [
          ProductUnitsCompanion.insert(
              id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
        ],
        tiersByUnitTempId: {
          'u1': [
            PriceTiersCompanion.insert(
                id: 't1',
                productUnitId: 'u1',
                price: 10000,
                costPrice: const Value(7000)),
          ],
        },
        barcodesByUnitTempId: const {},
        altPricesByUnitTempId: {
          'u1': [
            AltPricesCompanion.insert(
                id: 'ap1',
                productUnitId: 'u1',
                label: 'Manual',
                price: 9000,
                sortOrder: const Value(0)),
          ],
        },
      );

  Future<void> pumpViaRouter(WidgetTester tester) async {
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
  }

  testWidgets(
      'assign baris Harga Lain ke Kategori Harga: label+harga terkunci, '
      'tersimpan sbg category-linked di DB setelah Simpan Produk',
      (tester) async {
    await seedProduct();
    await db.addPriceCategory('Grosir');

    await pumpViaRouter(tester);

    await tester.tap(find.byIcon(Icons.sell_outlined));
    await tester.pumpAndSettle();

    // Sheet pemilih Kategori Harga — pilih "Grosir".
    expect(find.text('Pilih Kategori Harga'), findsOneWidget);
    await tester.tap(find.text('Grosir'));
    await tester.pumpAndSettle();

    // Editor margin muncul, terisi acuan Dasar/Persen default — isi margin
    // 20%.
    expect(find.textContaining('Kategori: Grosir'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Margin'), '20');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    // Baris sekarang terkunci & menampilkan nama kategori + harga hasil.
    expect(find.widgetWithText(TextFormField, 'Grosir'), findsOneWidget);

    await tester.tap(find.text('Simpan Produk'));
    await tester.pumpAndSettle();

    final alts = await db.getAltPrices('u1');
    expect(alts, hasLength(1));
    expect(alts.single.label, 'Grosir');
    expect(alts.single.priceCategoryId, isNotNull);
    expect(alts.single.marginAnchor, kMarginAnchorDasar);
    expect(alts.single.marginType, kMarginTypePercent);
    expect(alts.single.marginValue, 20);
    expect(alts.single.price, 12000); // 10000 * 1.2

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'lepas baris dari Kategori Harga: harga live-computed terakhir '
      'DIBEKUKAN jadi manual (bukan dikosongkan), bukan dihapus',
      (tester) async {
    await seedProduct();
    final catId = await db.addPriceCategory('Grosir');
    await db.setPriceCategoryMargin(
      priceCategoryId: catId,
      productUnitId: 'u1',
      categoryName: 'Grosir',
      marginAnchor: kMarginAnchorDasar,
      marginType: kMarginTypePercent,
      marginValue: 20,
      computedPrice: 12000,
    );
    // Baris manual lama ('ap1' dari seedProduct) tetap ada; kategori nambah
    // baris ke-2 -> hapus manual dulu spy hanya 1 baris category-linked yg
    // diuji (fokus test ini murni alur unassign).
    await (db.delete(db.altPrices)..where((t) => t.id.equals('ap1'))).go();

    await pumpViaRouter(tester);

    // Baris category-linked: label field menampilkan nama kategori.
    expect(find.widgetWithText(TextFormField, 'Grosir'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.sell_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Lepas dari Kategori'), findsOneWidget);
    await tester.tap(find.text('Lepas dari Kategori'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Simpan Produk'));
    await tester.pumpAndSettle();

    final alts = await db.getAltPrices('u1');
    expect(alts, hasLength(1));
    expect(alts.single.priceCategoryId, isNull,
        reason: 'sudah dilepas dari kategori');
    expect(alts.single.price, 12000,
        reason: 'harga live-computed terakhir DIBEKUKAN, bukan dikosongkan');
    expect(alts.single.label, 'Grosir',
        reason: 'label kategori terakhir tetap dipertahankan (beku)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
