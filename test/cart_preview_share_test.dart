import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Fitur (permintaan user): "kadang pelanggan minta preview serta estimasi
/// total" — tombol "Bagikan Pratinjau" di header keranjang membuka sheet
/// berisi struk `CartPreviewPaper`, terpisah total dari `_ReceiptPaper`
/// (belum ada transaksi tercatat sama sekali di titik ini).
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

  const staticQris = '00020101021126610014COM.GO-JEK.WWW01189360091434648855360'
      '210G4648855360303UMI51440014ID.CO.QRIS.WWW0215ID102657224253903'
      '03UMI5204549953033605802ID5920Toko Berkah, BNY NYR6011PROBOLIN'
      'GGO61056727562070703A0163043165';

  Future<AppDatabase> pumpCartSheetOpen(
    WidgetTester tester, {
    String cartId = kMainCartId,
    bool seedItem = true,
    bool seedQris = false,
    String? customerName,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    if (seedQris) {
      await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
          id: 'pm-qris',
          type: 'qris',
          name: 'QRIS',
          qrValue: const Value(staticQris),
          sortOrder: const Value(1)));
    }
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
    if (seedItem) {
      container.read(cartProvider(cartId).notifier).addItem(item);
    }
    if (customerName != null) {
      container
          .read(cartMetaProvider(cartId).notifier)
          .setCustomer(null, customerName);
    }

    await tester.binding.setSurfaceSize(const Size(420, 1000));
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
      'tombol "Bagikan Pratinjau" membuka sheet berisi PRATINJAU KERANJANG '
      '& estimasi total yang benar', (tester) async {
    final db = await pumpCartSheetOpen(tester);
    addTearDown(() async => db.close());

    expect(find.byTooltip('Bagikan Pratinjau'), findsOneWidget);
    await tester.tap(find.byTooltip('Bagikan Pratinjau'));
    await tester.pumpAndSettle();

    expect(find.text('Bagikan Pratinjau'), findsWidgets);
    expect(find.text('PRATINJAU KERANJANG'), findsOneWidget);
    expect(find.text('Estimasi Total'), findsOneWidget);
    // 2 x 15.000 = 30.000 (muncul 2x: baris subtotal item & Estimasi Total)
    expect(find.text('Rp 30.000'), findsNWidgets(2));
    expect(find.text('Gagal membagikan: '), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('tombol nonaktif saat keranjang kosong', (tester) async {
    final db = await pumpCartSheetOpen(tester, seedItem: false);
    addTearDown(() async => db.close());

    final button = tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip('Bagikan Pratinjau'),
        matching: find.byType(IconButton)));
    expect(button.onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tanpa metode QRIS terkonfigurasi -> toggle QR tidak ditawarkan',
      (tester) async {
    final db = await pumpCartSheetOpen(tester, seedQris: false);
    addTearDown(() async => db.close());

    await tester.tap(find.byTooltip('Bagikan Pratinjau'));
    await tester.pumpAndSettle();

    expect(find.text('Tampilkan QR QRIS'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'dengan metode QRIS terkonfigurasi -> nyalakan toggle menampilkan '
      'QR & nominal ikut estimasi total', (tester) async {
    final db = await pumpCartSheetOpen(tester, seedQris: true);
    addTearDown(() async => db.close());

    await tester.tap(find.byTooltip('Bagikan Pratinjau'));
    await tester.pumpAndSettle();

    expect(find.text('Tampilkan QR QRIS'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);

    await tester.tap(find.text('Tampilkan QR QRIS'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('QR Dinamis'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'nama pelanggan yang dipilih ikut tampil di pratinjau (ad-hoc)',
      (tester) async {
    final db =
        await pumpCartSheetOpen(tester, customerName: 'Bu Siti');
    addTearDown(() async => db.close());

    await tester.tap(find.byTooltip('Bagikan Pratinjau'));
    await tester.pumpAndSettle();

    expect(find.text('Bu Siti'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'mode Katalog (kCatalogCartId) TIDAK menawarkan tombol Bagikan '
      'Pratinjau — bukan keranjang transaksi sungguhan', (tester) async {
    final db =
        await pumpCartSheetOpen(tester, cartId: kCatalogCartId);
    addTearDown(() async => db.close());

    expect(find.byTooltip('Bagikan Pratinjau'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
