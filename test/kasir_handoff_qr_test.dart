import 'package:drift/drift.dart' show Value;
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
import 'package:qr_flutter/qr_flutter.dart';

/// Item 24d — gerbang tombol "Bayar" di `CartSheet`: pegawai (deviceRole
/// 'kasir') TANPA izin `terima_pembayaran` melihat "Kirim ke Owner/Asisten"
/// (tampilkan QR) alih-alih "Bayar" langsung. Owner/Asisten TIDAK PERNAH
/// digerbang.
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

  testWidgets(
      'pegawai TANPA izin terima_pembayaran: tombol jadi "Kirim ke '
      'Owner/Asisten", tap menampilkan QR', (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir', terimaPembayaran: false);
    addTearDown(() async => db.close());

    expect(find.text('Kirim ke Owner/Asisten'), findsOneWidget);
    expect(find.text('Bayar'), findsNothing);

    await tester.tap(find.text('Kirim ke Owner/Asisten'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Sudah Dikirim, Kosongkan Keranjang'), findsOneWidget);
  });

  testWidgets(
      'pegawai DENGAN izin terima_pembayaran ON: tombol tetap "Bayar" '
      'normal (tidak digerbang)', (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir', terimaPembayaran: true);
    addTearDown(() async => db.close());

    expect(find.text('Bayar'), findsOneWidget);
    expect(find.text('Kirim ke Owner/Asisten'), findsNothing);
  });

  testWidgets('owner TIDAK PERNAH digerbang, selalu lihat "Bayar" langsung',
      (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'owner', terimaPembayaran: false);
    addTearDown(() async => db.close());

    expect(find.text('Bayar'), findsOneWidget);
    expect(find.text('Kirim ke Owner/Asisten'), findsNothing);
  });

  testWidgets('asisten TIDAK PERNAH digerbang, selalu lihat "Bayar" langsung',
      (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'asisten', terimaPembayaran: false);
    addTearDown(() async => db.close());

    expect(find.text('Bayar'), findsOneWidget);
    expect(find.text('Kirim ke Owner/Asisten'), findsNothing);
  });

  testWidgets(
      'tap "Sudah Dikirim, Kosongkan Keranjang" mengosongkan keranjang '
      'lokal pegawai (TIDAK menulis held_orders di device sendiri)',
      (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir', terimaPembayaran: false);
    addTearDown(() async => db.close());

    await tester.tap(find.text('Kirim ke Owner/Asisten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sudah Dikirim, Kosongkan Keranjang'));
    await tester.pumpAndSettle();

    // Query one-shot (BUKAN watchHeldOrders().first) — subscribe ke Stream
    // drift baru di tengah widget test bisa macet selamanya di synthetic
    // clock testWidgets (gotcha yang sama dgn StreamProvider, lihat
    // CLAUDE.md §Gotcha), walau cuma dibaca sekali.
    final rows = await db.select(db.heldOrders).get();
    expect(rows, isEmpty,
        reason: 'antrian held_orders SEHARUSNYA ditulis di device OWNER '
            'saat scan, bukan di device pegawai sendiri');

    // Sheet QR tertutup, CartSheet di baliknya sudah kosong (TIDAK ikut
    // ditutup otomatis — cuma sheet QR-nya sendiri).
    expect(find.text('Sudah Dikirim, Kosongkan Keranjang'), findsNothing);
    expect(find.text('Keranjang kosong'), findsOneWidget);
  });

  testWidgets(
      'mode Katalog (kCatalogCartId) TIDAK PERNAH digerbang walau pegawai '
      'tanpa izin — bukan transaksi sungguhan', (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir',
        terimaPembayaran: false,
        cartId: kCatalogCartId);
    addTearDown(() async => db.close());

    expect(find.text('Bayar'), findsOneWidget);
    expect(find.text('Kirim ke Owner/Asisten'), findsNothing);
  });
}
