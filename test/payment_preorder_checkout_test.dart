import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// Item 52 redesain pre-order — checkout normal SEKARANG langsung menulis
/// baris `PreorderEntries` utk item yg ditandai `isPreorder` di keranjang,
/// dgn `transactionId` OTOMATIS terisi (menggantikan jalur lama "+ Antri"/
/// "Catat Pre-order" yg tanpa tautan nota). Item pre-order jg dikecualikan
/// dari pengurangan stok (barangnya belum ada fisik di toko).
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p1', name: 'Galon Aqua', markedOutOfStock: const Value(true)));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1',
        productId: 'p1',
        isBaseUnit: const Value(true),
        requiresDeposit: const Value(true)));
    // Produk kedua, normal (bukan pre-order), utk membuktikan stok item
    // BIASA tetap terpotong seperti biasa di nota yg sama.
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p2', name: 'Gula Pasir'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u2', productId: 'p2', isBaseUnit: const Value(true)));
    await db.adjustStock(productUnitId: 'u2', newQty: 10, note: 'seed');

    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko Uji',
          deviceName: 'Kasir Uji',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  testWidgets(
      'checkout: item isPreorder membuat baris PreorderEntries dgn '
      'transactionId terisi, TIDAK memotong stok; item biasa tetap potong '
      'stok', (tester) async {
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
          preorderPaid: false,
          depositQty: 2,
        ));
    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'p2',
          productUnitId: 'u2',
          productName: 'Gula Pasir',
          unitName: 'Kg',
          qty: 3,
          price: 15000,
          originalPrice: 15000,
          costPrice: 12000,
        ));

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

    final preorders = await db.select(db.preorderEntries).get();
    expect(preorders, hasLength(1),
        reason: 'hanya 1 item yg isPreorder, jadi 1 baris PreorderEntries');
    final p = preorders.single;
    expect(p.transactionId, tx.id,
        reason: 'transactionId HARUS otomatis terisi dari nota yg baru '
            'dibuat, bukan null spt jalur lama');
    expect(p.qtyOrdered, 2);
    expect(p.depositQty, 2);
    expect(p.paid, isFalse, reason: 'DP Tidak -> paid=false');
    expect(p.productId, 'p1');

    // Stok p1 (pre-order) TIDAK berkurang sama sekali (masih 0, baseline).
    final stockP1 = await db.currentStock('u1');
    expect(stockP1, 0,
        reason: 'item pre-order TIDAK BOLEH memotong stok — barangnya '
            'belum ada fisik di toko');

    // Stok p2 (item biasa) tetap terpotong normal (10 - 3 = 7).
    final stockP2 = await db.currentStock('u2');
    expect(stockP2, 7,
        reason: 'item BUKAN pre-order harus tetap memotong stok spt biasa');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('DP Ya (preorderPaid=true) -> PreorderEntries.paid=true',
      (tester) async {
    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'p1',
          productUnitId: 'u1',
          productName: 'Galon Aqua',
          unitName: 'Tabung',
          qty: 1,
          price: 25000,
          originalPrice: 25000,
          costPrice: 18000,
          isPreorder: true,
          preorderPaid: true,
          depositQty: 1,
        ));

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

    final preorders = await db.select(db.preorderEntries).get();
    expect(preorders.single.paid, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
