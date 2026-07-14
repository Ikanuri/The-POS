import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

import 'helpers/pump_app.dart';

/// Fitur: checklist verifikasi barang di keranjang (kiri nama item) + stepper
/// disamakan gaya `AddControl` produk. Checklist harus cascade parent/varian
/// (sama seperti Struk) dan diteruskan sebagai nilai awal `checkedItemIds`
/// transaksi baru saat checkout.
void main() {
  const parent = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Kopi Sachet',
    unitName: 'Renceng',
    qty: 1,
    price: 15000,
    originalPrice: 15000,
    costPrice: 10000,
  );
  const child = CartItem(
    productId: 'p1-dus',
    productUnitId: 'u1-dus',
    productName: 'Kopi Sachet (Dus)',
    unitName: 'Dus',
    qty: 1,
    price: 150000,
    originalPrice: 150000,
    costPrice: 100000,
    isVariant: true,
    parentProductId: 'p1',
    parentProductUnitId: 'u1',
  );

  group('CartItem — serialisasi field checked', () {
    test('toJson/fromJson roundtrip mempertahankan checked', () {
      final item = parent.copyWith(checked: true);
      final decoded = CartItem.fromJson(item.toJson());
      expect(decoded.checked, isTrue);
    });

    test('default checked = false (data lama tanpa field ini)', () {
      final oldJson = parent.toJson()..remove('checked');
      final decoded = CartItem.fromJson(oldJson);
      expect(decoded.checked, isFalse);
    });
  });

  group('CartNotifier.setChecked — cascade parent/varian', () {
    late ProviderContainer container;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('centang induk → semua varian anak ikut tercentang', () {
      final notifier = container.read(cartProvider(kMainCartId).notifier);
      notifier.addItem(parent);
      notifier.addItem(child);

      notifier.setChecked('u1', true);

      final cart = container.read(cartProvider(kMainCartId));
      expect(cart.firstWhere((c) => c.productUnitId == 'u1').checked, isTrue);
      expect(
          cart.firstWhere((c) => c.productUnitId == 'u1-dus').checked, isTrue);
    });

    test('uncheck salah satu varian anak → induk ikut ke-uncheck', () {
      final notifier = container.read(cartProvider(kMainCartId).notifier);
      notifier.addItem(parent);
      notifier.addItem(child);
      notifier.setChecked('u1', true); // centang semua dulu

      notifier.setChecked('u1-dus', false);

      final cart = container.read(cartProvider(kMainCartId));
      expect(cart.firstWhere((c) => c.productUnitId == 'u1').checked, isFalse,
          reason: 'induk harus ikut uncheck krn TIDAK semua anak tercentang');
    });

    test('centang SEMUA varian anak satu-satu → induk otomatis tercentang',
        () {
      final notifier = container.read(cartProvider(kMainCartId).notifier);
      notifier.addItem(parent);
      notifier.addItem(child);

      notifier.setChecked('u1-dus', true);

      final cart = container.read(cartProvider(kMainCartId));
      expect(cart.firstWhere((c) => c.productUnitId == 'u1').checked, isTrue);
    });
  });

  group('CartSheet — UI checklist & stepper', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() async => db.close());

    testWidgets('checkbox tampil (leading) & tap toggle checked, stepper '
        'pakai AddControl (bukan field qty lama)', (tester) async {
      final prefs = {
        'cart_v1_main': jsonEncode([parent.toJson()]),
      };

      await pumpWithFakeApp(tester,
          db: db, initialPrefs: prefs, child: const CartSheet());

      // Checklist verifikasi.
      final checkbox = find.byType(Checkbox);
      expect(checkbox, findsOneWidget);
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);

      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

      // Stepper baru — widget shared AddControl, bukan lagi IconButton ±
      // atau field qty tap-to-edit.
      expect(find.byType(AddControl), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      expect(find.byType(TextField), findsNothing,
          reason: 'field qty inline lama sudah dihapus, edit lewat tap item');
    });

    testWidgets('tap AddControl "+" menambah qty efektif item', (tester) async {
      final prefs = {
        'cart_v1_main': jsonEncode([parent.toJson()]),
      };
      await pumpWithFakeApp(tester,
          db: db, initialPrefs: prefs, child: const CartSheet());

      expect(find.text(formatRupiah(15000)), findsWidgets); // qty 1

      await tester.tap(find.byType(AddControl));
      await tester.pumpAndSettle();

      expect(find.text(formatRupiah(30000)), findsWidgets); // qty 2
    });
  });

  group('Checkout — checklist keranjang diteruskan ke checkedItemIds transaksi',
      () {
    testWidgets(
        'item checked=true di keranjang → transaction_items barunya masuk '
        'checkedItemIds; item checked=false TIDAK ikut', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async => db.close());

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider.overrideWith((ref) => DeviceNotifier()
          ..state = const DeviceIdentity(
            storeUuid: 'test-store-uuid',
            storeKey: 'test-store-key',
            storeName: 'Toko Uji',
            deviceName: 'Kasir Uji',
            deviceCode: 'K1',
            deviceRole: 'owner',
          )),
      ]);
      addTearDown(container.dispose);

      const itemChecked = CartItem(
        productId: 'pA',
        productUnitId: 'uA',
        productName: 'Barang Dicentang',
        unitName: 'Pcs',
        qty: 1,
        price: 10000,
        originalPrice: 10000,
        costPrice: 7000,
        checked: true,
      );
      const itemUnchecked = CartItem(
        productId: 'pB',
        productUnitId: 'uB',
        productName: 'Barang Belum Dicentang',
        unitName: 'Pcs',
        qty: 1,
        price: 5000,
        originalPrice: 5000,
        costPrice: 3000,
      );
      container.read(cartProvider(kMainCartId).notifier).addItem(itemChecked);
      container
          .read(cartProvider(kMainCartId).notifier)
          .addItem(itemUnchecked);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PaymentScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Bayar Rp'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uang Pas'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Bayar'));
      await tester.pumpAndSettle();

      final tx = await db.select(db.transactions).getSingle();
      expect(tx.checkedItemIds, isNotNull,
          reason: 'ada 1 item checked di cart, harus terisi');
      final checkedIds =
          (jsonDecode(tx.checkedItemIds!) as List).cast<String>();
      expect(checkedIds, hasLength(1));

      final items = await db.select(db.transactionItems).get();
      final tiChecked =
          items.firstWhere((i) => i.productUnitId == 'uA');
      final tiUnchecked =
          items.firstWhere((i) => i.productUnitId == 'uB');
      expect(checkedIds, contains(tiChecked.id));
      expect(checkedIds, isNot(contains(tiUnchecked.id)));
    });
  });
}
