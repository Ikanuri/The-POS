import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Item 56 — tombol Transfer (ikon QR+panah) di `CartSheet`: tersedia utk
/// owner/asisten/pegawai BERIZIN `terima_pembayaran` (transfer transaksi
/// bebas ke device lain), TIDAK utk pegawai TANPA izin (jalur mereka sudah
/// "Kirim ke Owner/Asisten" via tombol Bayar utama — lihat kasir_handoff_qr_
/// test.dart) maupun mode Katalog. "Kosongkan" (teks) diganti ikon tempat
/// sampah, dialog konfirmasi tetap ada.
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

  Future<AppDatabase> pumpCartSheetOpen(
    WidgetTester tester, {
    required String deviceRole,
    bool terimaPembayaran = false,
    String cartId = kMainCartId,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('terima_pembayaran')))
        .write(KasirPermissionsCompanion(isEnabled: Value(terimaPembayaran)));
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'HP Kasir 2',
          deviceCode: 'K2',
          deviceRole: deviceRole,
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(cartId).notifier).addItem(item);

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
    return db;
  }

  testWidgets('owner melihat ikon Transfer, tap membuka QR "Transfer '
      'Transaksi"', (tester) async {
    final db = await pumpCartSheetOpen(tester, deviceRole: 'owner');
    addTearDown(() async => db.close());

    expect(find.byTooltip('Transfer via QR'), findsOneWidget);

    await tester.tap(find.byTooltip('Transfer via QR'));
    await tester.pumpAndSettle();

    expect(find.text('Transfer Transaksi'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('asisten melihat ikon Transfer', (tester) async {
    final db = await pumpCartSheetOpen(tester, deviceRole: 'asisten');
    addTearDown(() async => db.close());

    expect(find.byTooltip('Transfer via QR'), findsOneWidget);
  });

  testWidgets(
      'pegawai DENGAN izin terima_pembayaran melihat ikon Transfer juga',
      (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir', terimaPembayaran: true);
    addTearDown(() async => db.close());

    expect(find.byTooltip('Transfer via QR'), findsOneWidget);
  });

  testWidgets(
      'pegawai TANPA izin terima_pembayaran TIDAK melihat ikon Transfer '
      '(jalur mereka sudah "Kirim ke Owner/Asisten" via tombol Bayar utama)',
      (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir', terimaPembayaran: false);
    addTearDown(() async => db.close());

    expect(find.byTooltip('Transfer via QR'), findsNothing);
  });

  testWidgets('mode Katalog TIDAK menampilkan ikon Transfer', (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'owner', cartId: kCatalogCartId);
    addTearDown(() async => db.close());

    expect(find.byTooltip('Transfer via QR'), findsNothing);
  });

  testWidgets(
      '"Kosongkan" berbentuk ikon tempat sampah (bukan teks), dialog '
      'konfirmasi tetap ada & mengosongkan keranjang', (tester) async {
    final db = await pumpCartSheetOpen(tester, deviceRole: 'owner');
    addTearDown(() async => db.close());

    expect(find.text('Kosongkan'), findsNothing,
        reason: 'teks lama diganti ikon');
    expect(find.byTooltip('Kosongkan'), findsOneWidget);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(CartSheet)),
        listen: false);

    await tester.tap(find.byTooltip('Kosongkan'));
    await tester.pumpAndSettle();

    expect(find.text('Kosongkan Keranjang?'), findsOneWidget,
        reason: 'dialog konfirmasi wajib tetap ada');

    await tester.tap(find.text('Kosongkan'));
    await tester.pumpAndSettle();

    // Sheet ditutup (sama spt perilaku lama) setelah dikosongkan — cek
    // state cart provider langsung, bukan cari teks di sheet yg sudah pop.
    expect(container.read(cartProvider(kMainCartId)), isEmpty);
  });
}
