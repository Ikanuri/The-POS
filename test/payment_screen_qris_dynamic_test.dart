import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart' show formatRupiah;
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// Item 62 susulan — QR QRIS di layar checkout sekarang mencoba menyisipkan
/// nominal (fitur EKSPERIMENTAL, lihat qris_dynamic.dart), berlabel jelas
/// "Eksperimental" di UI. `qrValue` di sini payload GoPay statis ASLI
/// (dikirim user dari HP-nya) — sama seperti fixture `qris_dynamic_test.dart`.
void main() {
  const staticPayload =
      '00020101021126610014COM.GO-JEK.WWW01189360091434648855360'
      '210G4648855360303UMI51440014ID.CO.QRIS.WWW0215ID102657224253903'
      '03UMI5204549953033605802ID5920Toko Berkah, BNY NYR6011PROBOLIN'
      'GGO61056727562070703A0163043165';

  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Gula Pasir',
    unitName: 'Pcs',
    qty: 1,
    price: 17000,
    originalPrice: 17000,
    costPrice: 12000,
  );

  Future<AppDatabase> makeDbWithQris() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.paymentMethods).insert(
          PaymentMethodsCompanion.insert(
            id: 'pm-qris',
            type: 'qris',
            name: 'QRIS',
            qrValue: const Value(staticPayload),
            sortOrder: const Value(1),
          ),
        );
    return db;
  }

  testWidgets(
      'pilih QRIS → QR nominal terkunci (badge Eksperimental) tampil, '
      'payload valid & bawa nominal Rp 17.000', (tester) async {
    final db = await makeDbWithQris();
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
    container.read(cartProvider(kMainCartId).notifier).addItem(item);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PaymentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'QRIS'));
    await tester.pumpAndSettle();

    expect(find.text('Eksperimental'), findsOneWidget);
    expect(find.textContaining('Nominal disisipkan otomatis'), findsOneWidget);
    // Nominal yg dipatri ke QR = total keranjang (1x Gula Pasir Rp 17.000),
    // sama seperti yg dites presisi bytenya di qris_dynamic_test.dart.
    expect(find.text(formatRupiah(17000)), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'qrValue BUKAN payload QRIS valid (rusak) → fallback diam-diam ke QR '
      'apa adanya, TANPA badge Eksperimental, checkout tidak error',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.paymentMethods).insert(
          PaymentMethodsCompanion.insert(
            id: 'pm-qris',
            type: 'qris',
            name: 'QRIS',
            qrValue: const Value('bukan-payload-qris-sama-sekali'),
            sortOrder: const Value(1),
          ),
        );
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
    container.read(cartProvider(kMainCartId).notifier).addItem(item);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PaymentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'QRIS'));
    await tester.pumpAndSettle();

    expect(find.text('Eksperimental'), findsNothing);
    expect(find.textContaining('Nominal disisipkan otomatis'), findsNothing);
    // Checkout tidak error/crash walau payload tidak bisa diparse.
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
