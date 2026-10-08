import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/theme_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/widgets/marquee_text.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Opsi layout baris keranjang (Pengaturan Keranjang): (1) subtotal di
/// samping "satuan · harga", (2) chip Kategori Harga di samping nama.
/// Dibuktikan di HP sempit (360dp) pada SEMUA posisi checkbox: tidak
/// overflow & tidak menimpa stepper/checkbox.
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  late AppDatabase db;
  late ProviderContainer container;
  late String unitId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Produk p1'));
    unitId = 'p1_u';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId, productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'p1_tier',
          productUnitId: unitId,
          minQty: const Value(1),
          price: 115000,
          costPrice: const Value(90000),
        ));
    for (final n in ['Grosir', 'Reseller', 'Member', 'Agen']) {
      final cat = await db.addPriceCategory(n);
      await db.into(db.altPrices).insert(AltPricesCompanion.insert(
          id: 'alt_$n',
          productUnitId: unitId,
          label: n,
          price: 100000,
          priceCategoryId: Value(cat)));
    }
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko Uji',
          deviceName: 'Kasir Uji',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    container.read(cartProvider(kMainCartId).notifier).addItem(CartItem(
          productId: 'p1',
          productUnitId: unitId,
          productName: 'Sedap Goreng Ayam Bawang Jumbo Edisi Spesial',
          unitName: 'Dus',
          qty: 2,
          price: 115000,
          originalPrice: 115000,
          costPrice: 90000,
        ));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pumpCartSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => const CartSheet(cartId: kMainCartId),
                ),
                child: const Text('buka keranjang'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka keranjang'));
    await tester.pumpAndSettle();
  }

  /// Notifier memuat prefs di constructor (async) lalu menimpa `state` —
  /// tunggu muatan awal selesai (dunia nyata, bukan FakeAsync) SEBELUM set.
  Future<void> setPref<T>(
      WidgetTester tester,
      StateNotifierProvider<StateNotifier<T>, T> p,
      Future<void> Function() setter) async {
    container.read(p); // buat notifier SEKARANG (memicu muatan awal)
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await setter();
    });
  }

  Finder inList(Finder f) =>
      find.descendant(of: find.byType(ListView), matching: f);

  final subtotalText = formatRupiah(230000);

  testWidgets('default: subtotal di BAWAH harga, chip di bawah nama',
      (tester) async {
    await pumpCartSheet(tester);
    final sub = tester.getCenter(inList(find.text(subtotalText)));
    final chip = tester.getCenter(inList(find.text('Grosir')));
    final unitLine = tester.getCenter(inList(find.textContaining('Dus')));
    expect(sub.dy, greaterThan(unitLine.dy + 6));
    expect(chip.dy, greaterThan(sub.dy));
    await drain(tester);
  });

  testWidgets(
      'subtotal di samping harga: satu baris, rata kanan, tidak '
      'menimpa stepper', (tester) async {
    await setPref(
        tester,
        cartSubtotalBesidePriceProvider,
        () =>
            container.read(cartSubtotalBesidePriceProvider.notifier).set(true));
    await pumpCartSheet(tester);
    final sub = inList(find.text(subtotalText));
    final unitLine = inList(find.textContaining('Dus'));
    expect((tester.getCenter(sub).dy - tester.getCenter(unitLine).dy).abs(),
        lessThan(6),
        reason: 'subtotal sejajar dgn baris satuan · harga');
    expect(
        tester.getRect(sub).left, greaterThan(tester.getRect(unitLine).left));
    expect(tester.getRect(sub).right,
        lessThanOrEqualTo(tester.getRect(find.byType(AddControl)).left + 1),
        reason: 'subtotal tidak masuk ke area stepper');
    expect(tester.takeException(), isNull);
    await drain(tester);
  });

  testWidgets(
      'chip di samping nama: sejajar nama, bisa digeser, tidak '
      'overflow di semua posisi checkbox', (tester) async {
    await setPref(tester, cartChipsBesideNameProvider,
        () => container.read(cartChipsBesideNameProvider.notifier).set(true));
    await setPref(
        tester,
        cartSubtotalBesidePriceProvider,
        () =>
            container.read(cartSubtotalBesidePriceProvider.notifier).set(true));
    for (final pos in CartCheckboxPosition.values) {
      await setPref(tester, cartCheckboxPositionProvider,
          () => container.read(cartCheckboxPositionProvider.notifier).set(pos));
      await pumpCartSheet(tester);
      final chip = inList(find.text('Normal'));
      expect(chip, findsOneWidget, reason: 'posisi ${pos.name}');
      final name = inList(find.byType(MarqueeText));
      expect(name, findsOneWidget, reason: 'nama berjalan, posisi ${pos.name}');
      expect((tester.getCenter(chip).dy - tester.getCenter(name).dy).abs(),
          lessThan(10),
          reason: 'chip sejajar nama, posisi ${pos.name}');
      expect(tester.getRect(chip).right,
          lessThanOrEqualTo(tester.getRect(find.byType(AddControl)).left + 1),
          reason: 'chip tidak menimpa stepper, posisi ${pos.name}');
      expect(tester.takeException(), isNull, reason: 'posisi ${pos.name}');
      await drain(tester);
    }
  });
}
