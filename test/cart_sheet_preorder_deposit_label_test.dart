import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Item 52 redesain pre-order — label "Titip [qty]" (jaminan dititip) di
/// keranjang, DISATUKAN ke text run yang sama dgn nama produk (persis pola
/// badge "Habis" di katalog kasir), bukan Text terpisah berjarak.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'item dgn depositQty>0 menampilkan "Titip N" menyatu dgn nama; item '
      'tanpa depositQty TIDAK menampilkan label itu', (tester) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Dev',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);

    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'p1',
          productUnitId: 'u1',
          productName: 'Galon Aqua',
          unitName: 'Tabung',
          qty: 2,
          price: 0,
          originalPrice: 25000,
          costPrice: 18000,
          isPreorder: true,
          depositQty: 2,
        ));
    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'p2',
          productUnitId: 'u2',
          productName: 'Gula Pasir',
          unitName: 'Kg',
          qty: 1,
          price: 15000,
          originalPrice: 15000,
          costPrice: 12000,
        ));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CartSheet())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Titip 2', findRichText: true), findsOneWidget,
        reason: 'label "Titip 2" harus menyatu dgn nama Galon Aqua');
    expect(find.textContaining('Titip', findRichText: true), findsOneWidget,
        reason: 'item TANPA depositQty (Gula Pasir) tidak boleh dapat label');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
