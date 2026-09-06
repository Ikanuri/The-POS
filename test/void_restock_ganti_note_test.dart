import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// "Batalkan & Susun Ulang" (fitur baru) — nota BARU hasil checkout dari
/// keranjang yg diisi ulang dari nota LAMA yg divoid HARUS menautkan diri ke
/// nota lama lewat `internalNote: 'GANTI:<id>'` (pola sama `RETUR:<id>` di
/// `addReturnTransaction`). Ditandai lewat `CartMeta.replacesTxId` — dibaca
/// SEKALI oleh `payment_screen.dart` saat checkout.
void main() {
  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Gula Pasir',
    unitName: 'Pcs',
    qty: 1,
    price: 10000,
    originalPrice: 10000,
    costPrice: 7000,
  );

  const fakeDevice = DeviceIdentity(
    storeUuid: 'test-store-uuid',
    storeKey: 'test-store-key',
    storeName: 'Toko Uji',
    deviceName: 'Kasir Uji',
    deviceCode: 'K1',
    deviceRole: 'owner',
  );

  testWidgets(
      'cartMeta.replacesTxId TERISI -> nota baru dpt internalNote GANTI:<id>',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
    ]);
    addTearDown(container.dispose);

    container.read(cartProvider(kMainCartId).notifier).addItem(item);
    container
        .read(cartMetaProvider(kMainCartId).notifier)
        .setReplacesTxId('tx-lama-123');

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
    expect(tx.internalNote, 'GANTI:tx-lama-123',
        reason: 'nota baru harus menautkan diri ke nota lama yg divoid, '
            'pola sama RETUR:<id>');
  });

  testWidgets(
      'cartMeta.replacesTxId KOSONG (checkout normal biasa) -> internalNote '
      'TETAP null (perilaku lama tidak boleh berubah)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
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

    await tester.tap(find.textContaining('Bayar Rp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uang Pas'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Bayar'));
    await tester.pumpAndSettle();

    final tx = await db.select(db.transactions).getSingle();
    expect(tx.internalNote, isNull);
  });
}
