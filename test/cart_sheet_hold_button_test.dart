import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Susulan (permintaan user, 14 Agt 2026): tombol "Tahan Pesanan" langsung
/// dari header keranjang (di kiri "Tempel Pesanan") — sebelumnya cuma bisa
/// lewat tab folder pelanggan/pegawai di `kasir_screen.dart` yang
/// tersembunyi begitu sheet keranjang dibuka.
void main() {
  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Gula Pasir',
    unitName: 'Pcs',
    qty: 2,
    price: 15000,
    originalPrice: 15000,
    costPrice: 10000,
  );

  Future<(AppDatabase, ProviderContainer)> pumpCartSheetOpen(
    WidgetTester tester, {
    String cartId = kMainCartId,
    bool addItem = true,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'HP Kasir 1',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    if (addItem) container.read(cartProvider(cartId).notifier).addItem(item);

    await tester.binding.setSurfaceSize(const Size(420, 900));
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
                  builder: (_) => CartSheet(cartId: cartId),
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
    return (db, container);
  }

  testWidgets(
      'kMainCartId: tombol "Tahan Pesanan" tampil, disabled saat keranjang '
      'kosong', (tester) async {
    final (db, _) = await pumpCartSheetOpen(tester, addItem: false);
    addTearDown(() async => db.close());

    final button = tester.widget<IconButton>(find.widgetWithIcon(
        IconButton, Icons.pause_circle_outline));
    expect(button.onPressed, isNull,
        reason: 'keranjang kosong -> tombol Tahan harus disabled');
  });

  testWidgets(
      'mode Katalog: tombol "Tahan Pesanan" TIDAK ditampilkan sama sekali',
      (tester) async {
    final (db, _) =
        await pumpCartSheetOpen(tester, cartId: kCatalogCartId);
    addTearDown(() async => db.close());

    expect(find.widgetWithIcon(IconButton, Icons.pause_circle_outline),
        findsNothing);
  });

  testWidgets(
      'mode Tambah Belanjaan (cartId = txId): tombol "Tahan Pesanan" TIDAK '
      'ditampilkan (ikut transaksi asli, tidak bisa ditahan terpisah)',
      (tester) async {
    final (db, _) = await pumpCartSheetOpen(tester, cartId: 'tx-existing-1');
    addTearDown(() async => db.close());

    expect(find.widgetWithIcon(IconButton, Icons.pause_circle_outline),
        findsNothing);
  });

  testWidgets(
      'pelanggan SUDAH dipilih: tap Tahan langsung tahan TANPA dialog — '
      'label = nama pelanggan, keranjang+meta clear, sheet tertutup',
      (tester) async {
    final (db, container) = await pumpCartSheetOpen(tester);
    addTearDown(() async => db.close());
    container
        .read(cartMetaProvider(kMainCartId).notifier)
        .setCustomer('c1', 'Bu Sari');

    await tester.tap(
        find.widgetWithIcon(IconButton, Icons.pause_circle_outline));
    await tester.pumpAndSettle();

    expect(find.text('Tahan Pesanan'), findsNothing,
        reason: 'tanpa pelanggan seharusnya muncul dialog — dgn pelanggan '
            'TIDAK ada dialog sama sekali');
    expect(container.read(cartProvider(kMainCartId)), isEmpty);
    expect(container.read(cartMetaProvider(kMainCartId)).hasCustomer, isFalse);

    final held = await db.select(db.heldOrders).get();
    expect(held, hasLength(1));
    expect(held.single.label, 'Bu Sari');

    // Sheet keranjang ditutup otomatis setelah tahan.
    expect(find.byType(CartSheet), findsNothing);
  });

  testWidgets(
      'TANPA pelanggan: tap Tahan membuka dialog label; Batal -> keranjang '
      'UTUH tidak jadi ditahan', (tester) async {
    final (db, container) = await pumpCartSheetOpen(tester);
    addTearDown(() async => db.close());

    await tester.tap(
        find.widgetWithIcon(IconButton, Icons.pause_circle_outline));
    await tester.pumpAndSettle();

    expect(find.text('Tahan Pesanan'), findsOneWidget);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    expect(container.read(cartProvider(kMainCartId)), isNotEmpty);
    final held = await db.select(db.heldOrders).get();
    expect(held, isEmpty);
  });

  testWidgets(
      'TANPA pelanggan: isi label manual di dialog -> tersimpan sbg label '
      'held_order', (tester) async {
    final (db, container) = await pumpCartSheetOpen(tester);
    addTearDown(() async => db.close());

    await tester.tap(
        find.widgetWithIcon(IconButton, Icons.pause_circle_outline));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Meja 3');
    await tester.tap(find.text('Tahan'));
    await tester.pumpAndSettle();

    expect(container.read(cartProvider(kMainCartId)), isEmpty);
    final held = await db.select(db.heldOrders).get();
    expect(held, hasLength(1));
    expect(held.single.label, 'Meja 3');
  });
}
