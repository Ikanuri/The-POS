import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';
import 'package:the_pos/features/kasir/widgets/paste_order_sheet.dart';

/// Susulan (permintaan user): "Tempel Pesanan" juga bisa dipakai LANGSUNG
/// dari keranjang yang sedang terbuka — berguna kalau ada pesanan tambahan
/// (dari pelanggan via katalog HTML, atau pegawai tanpa izin
/// terima_pembayaran yang mau menambah pesanan) sebelum keranjang
/// di-checkout. `PasteOrderSheet` sendiri sudah generik per-cartId & sudah
/// merge ke keranjang yang ada (bukan bikin held_order baru) — tidak
/// disentuh, cuma disambungkan dari CartSheet.
void main() {
  Future<AppDatabase> seedProduct() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u1',
          productId: 'p1',
          isBaseUnit: const Value(true),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 't1',
          productUnitId: 'u1',
          minQty: const Value(1),
          price: 2500,
        ));
    return db;
  }

  Future<ProviderContainer> pumpCartSheetOpen(
    WidgetTester tester,
    AppDatabase db, {
    String cartId = kMainCartId,
  }) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Owner',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);

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
    return container;
  }

  testWidgets(
      'keranjang kosong TETAP menampilkan tombol "Tempel Pesanan" — beda '
      'dari tombol Transfer/Kosongkan yang butuh isi dulu', (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());

    await pumpCartSheetOpen(tester, db);

    expect(find.byTooltip('Tempel Pesanan'), findsOneWidget);
    final btn = tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip('Tempel Pesanan'), matching: find.byType(IconButton)));
    expect(btn.onPressed, isNotNull,
        reason: 'harus aktif walau keranjang masih kosong (beda dari '
            'Transfer/Kosongkan)');
  });

  testWidgets(
      'tap "Tempel Pesanan" di keranjang membuka PasteOrderSheet dgn cartId '
      'yang SAMA — item hasil tempel masuk ke keranjang yang sedang dibuka',
      (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());

    final container = await pumpCartSheetOpen(tester, db);

    await tester.tap(find.byTooltip('Tempel Pesanan'));
    await tester.pumpAndSettle();

    expect(find.byType(PasteOrderSheet), findsOneWidget);

    await tester.enterText(find.byType(TextField), '#PSN:u1=2;');
    await tester.tap(find.text('Proses Pesanan'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Masukkan'));
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider(kMainCartId));
    expect(cart.any((c) => c.productName == 'Sedap Goreng'), isTrue,
        reason: 'item dari Tempel Pesanan harus masuk ke keranjang (main), '
            'bukan bikin held_order baru');
    final rows = await db.select(db.heldOrders).get();
    expect(rows, isEmpty);
  });

  testWidgets('mode Katalog TIDAK menampilkan tombol "Tempel Pesanan" '
      '(bukan transaksi sungguhan)', (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());

    await pumpCartSheetOpen(tester, db, cartId: kCatalogCartId);

    expect(find.byTooltip('Tempel Pesanan'), findsNothing);
  });
}
