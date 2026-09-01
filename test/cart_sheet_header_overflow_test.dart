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

/// Susulan (permintaan user): tombol baru "Bagikan Pratinjau" menambah
/// jumlah IconButton di header keranjang jadi 6 (Tahan/Tempel/Bagikan
/// Pratinjau/Pengaturan/Transfer QR/Kosongkan) — CLAUDE.md sudah pernah
/// mencatat baris tombol padat begini rawan overflow di layar HP sungguhan
/// (360dp). Pastikan TIDAK overflow di lebar sesempit itu.
void main() {
  testWidgets(
      'header keranjang (6 IconButton, termasuk Bagikan Pratinjau) tidak '
      'overflow di layar sempit 360dp', (tester) async {
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
    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'p1',
          productUnitId: 'u1',
          productName: 'Gula Pasir',
          unitName: 'Pcs',
          qty: 2,
          price: 15000,
          originalPrice: 15000,
          costPrice: 10000,
        ));

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
                  builder: (_) => const CartSheet(),
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

    expect(tester.takeException(), isNull,
        reason: 'header keranjang harus render tanpa overflow di 360dp');
    expect(find.byTooltip('Bagikan Pratinjau'), findsOneWidget);
    expect(find.byTooltip('Tahan Pesanan'), findsOneWidget);
    expect(find.byTooltip('Tempel Pesanan'), findsOneWidget);
    expect(find.byTooltip('Pengaturan Keranjang'), findsOneWidget);
    expect(find.byTooltip('Transfer via QR'), findsOneWidget);
    expect(find.byTooltip('Kosongkan'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
