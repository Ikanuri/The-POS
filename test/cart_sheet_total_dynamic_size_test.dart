import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Susulan (permintaan user) — nominal Total di footer keranjang sekarang
/// dibungkus `FittedBox` (mengecil otomatis), bukan lagi ukuran font tetap.
/// Sejak ikon Pra-Bayar menempati ruang di sebelah tombol Bayar, lebar
/// tersisa utk Total lebih sempit -- harga besar sebelumnya bisa terpotong
/// jadi 2 baris tanpa ini.
void main() {
  const bigItem = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Barang Mahal',
    unitName: 'Pcs',
    qty: 1,
    price: 123456789,
    originalPrice: 123456789,
    costPrice: 100000000,
  );

  Future<AppDatabase> pumpCartSheetOpen(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'HP Kasir',
          deviceCode: 'K2',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(kMainCartId).notifier).addItem(bigItem);

    // Layar sempit sungguhan (gotcha CLAUDE.md) -- di sinilah Total dgn
    // font tetap dulu berisiko terpotong 2 baris begitu ikon Pra-Bayar ikut
    // ambil ruang di baris yang sama.
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
    addTearDown(() async => db.close());
    return db;
  }

  testWidgets(
      'Total dgn nominal besar di layar sempit -- TIDAK overflow/exception, '
      'dibungkus FittedBox+maxLines:1 (tidak lagi font tetap)',
      (tester) async {
    await pumpCartSheetOpen(tester);

    expect(tester.takeException(), isNull,
        reason: 'nominal Total besar tidak boleh memicu overflow exception '
            'di layar sempit');

    // Item satu-satunya di keranjang -> subtotal & Total sama-sama
    // menampilkan nominal yang sama persis, jadi ada >1 Text yang cocok.
    // Yang relevan diuji adalah baris Total (dibungkus FittedBox) -- cari
    // via ancestor FittedBox, bukan asumsikan hanya 1 match.
    final wrappedInFittedBox = find.ancestor(
        of: find.text(formatRupiah(123456789)),
        matching: find.byType(FittedBox));
    expect(wrappedInFittedBox, findsOneWidget,
        reason: 'Total harus dibungkus FittedBox supaya mengecil otomatis, '
            'bukan wrap ke 2 baris');

    final totalText = tester.widget<Text>(find.descendant(
        of: wrappedInFittedBox, matching: find.text(formatRupiah(123456789))));
    expect(totalText.maxLines, 1);
  });
}
