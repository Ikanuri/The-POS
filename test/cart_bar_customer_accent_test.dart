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
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart' show kMainCartId;

/// Susulan (permintaan user): aksen pelanggan terdaftar di cart bar
/// sebelumnya cuma kena ikon-nya (`_MetaChip.accent`) — teks nama masih
/// warna netral biasa. Sekarang teksnya IKUT terracotta juga, supaya
/// pembedanya benar-benar kelihatan (bukan cuma ikon kecil di pinggir).
void main() {
  Future<void> seedProduct(AppDatabase db) async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Gula Pasir'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 't1', productUnitId: 'u1', price: 15000));
  }

  Future<ProviderContainer> pumpKasir(WidgetTester tester, AppDatabase db,
      {String? customerId, String? customerName}) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Kasir',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
      licenseProvider.overrideWith((ref) =>
          LicenseNotifier()..state = const LicenseState(exp: 'selamanya')),
    ]);
    addTearDown(container.dispose);

    if (customerName != null) {
      container
          .read(cartMetaProvider(kMainCartId).notifier)
          .setCustomer(customerId, customerName);
    }

    final router = container.read(routerProvider);
    router.go('/kasir');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
            theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    // Cart bar (tempat `_MetaChip` pelanggan dirender) hanya muncul kalau
    // keranjang TIDAK kosong (`bottomNavigationBar: cart.isEmpty ? null :
    // ...` di kasir_screen.dart) — isi lewat alur nyata spt test cart bar
    // lain di repo ini.
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();
    await tester.pump();
    return container;
  }

  Text findMetaChipText(WidgetTester tester, String text) => tester
      .widgetList<Text>(find.descendant(
          of: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == 'MarqueeText'),
          matching: find.text(text)))
      .single;

  testWidgets(
      'pelanggan TERDAFTAR (customerId terisi) -> nama di cart bar ikut '
      'warna aksen terracotta, bukan cuma ikonnya',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await seedProduct(db);
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Bu Ani Terdaftar'));

    await pumpKasir(tester, db,
        customerId: 'c1', customerName: 'Bu Ani Terdaftar');

    final text = findMetaChipText(tester, 'Bu Ani Terdaftar');
    expect(text.style?.color, AppTheme.accent,
        reason: 'nama pelanggan terdaftar harus ikut aksen, bukan warna '
            'netral biasa');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'nama AD-HOC (customerId null) -> TIDAK ikut aksen terracotta',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await seedProduct(db);

    await pumpKasir(tester, db, customerName: 'Orang Lewat');

    final text = findMetaChipText(tester, 'Orang Lewat');
    expect(text.style?.color, isNot(AppTheme.accent),
        reason: 'nama ad-hoc (tanpa record pelanggan) tetap warna netral');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
