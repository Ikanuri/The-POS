import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/item_entry_sheet.dart';

import 'helpers/pump_app.dart';

/// Item 52 redesain pre-order — kartu "Pre-order?" di modal tap item
/// (ItemEntrySheet), menggantikan total jalur lama "+ Antri"/"Catat
/// Pre-order" yg terpisah dari keranjang.
void main() {
  late AppDatabase db;

  Future<Product> seedProduct({bool requiresDeposit = false}) async {
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p1', name: 'Galon Aqua', markedOutOfStock: const Value(true)));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1',
        productId: 'p1',
        isBaseUnit: const Value(true),
        requiresDeposit: Value(requiresDeposit)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 't1', productUnitId: 'u1', price: 25000));
    return (await db.searchProducts('')).first;
  }

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'kartu "Pre-order?" HANYA muncul saat produk ditandai habis (tidak '
      'muncul saat stok tersedia)', (tester) async {
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p2', name: 'Beras', markedOutOfStock: const Value(false)));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u2', productId: 'p2', isBaseUnit: const Value(true)));
    final product = (await db.searchProducts('')).first;

    await pumpWithFakeApp(tester,
        db: db, child: ItemEntrySheet(product: product));

    expect(find.text('Pre-order?'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'kartu "Pre-order?" muncul saat produk ditandai habis; tap "Ya" '
      'membuka "DP?"', (tester) async {
    final product = await seedProduct();
    await pumpWithFakeApp(tester,
        db: db, child: ItemEntrySheet(product: product));

    expect(find.text('Pre-order?'), findsOneWidget);
    expect(find.text('DP? (bayar lunas sekarang)'), findsNothing,
        reason: 'DP? belum muncul selama Pre-order? masih default Tidak');

    await tester.tap(find.text('Ya').first);
    await tester.pumpAndSettle();

    expect(find.text('DP? (bayar lunas sekarang)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'field "Jumlah jaminan dititip" HANYA muncul kalau satuan requiresDeposit',
      (tester) async {
    final product = await seedProduct(requiresDeposit: false);
    await pumpWithFakeApp(tester,
        db: db, child: ItemEntrySheet(product: product));

    await tester.tap(find.text('Ya').first);
    await tester.pumpAndSettle();

    expect(find.text('Jumlah jaminan dititip'), findsNothing,
        reason: 'satuan produk ini requiresDeposit=false');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'field "Jumlah jaminan dititip" muncul & default = qty pesanan saat '
      'requiresDeposit=true', (tester) async {
    final product = await seedProduct(requiresDeposit: true);
    await pumpWithFakeApp(tester,
        db: db, child: ItemEntrySheet(product: product));

    await tester.tap(find.text('Ya').first);
    await tester.pumpAndSettle();

    expect(find.text('Jumlah jaminan dititip'), findsOneWidget);
    // Qty pesanan default 1 -> field jaminan ikut default 1.
    final depositField = tester.widget<TextField>(find
        .descendant(
            of: find.ancestor(
                of: find.text('Jumlah jaminan dititip'),
                matching: find.byType(Row)),
            matching: find.byType(TextField))
        .first);
    expect(depositField.controller!.text, '1');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'DP Tidak (default) -> harga di keranjang 0; DP Ya -> harga penuh',
      (tester) async {
    final product = await seedProduct();
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child:
            MaterialApp(home: Scaffold(body: ItemEntrySheet(product: product))),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ya').first);
    await tester.pumpAndSettle();
    // DP default Tidak -> submit.
    await tester.tap(find.text('Tambah ke Keranjang'));
    await tester.pumpAndSettle();

    final cart1 = container.read(cartProvider(kMainCartId));
    final item1 = cart1.firstWhere((c) => c.productId == 'p1');
    expect(item1.isPreorder, isTrue);
    expect(item1.preorderPaid, isFalse);
    expect(item1.price, 0,
        reason: 'DP Tidak -> harga keranjang WAJIB 0, belum bayar');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('DP Ya -> harga keranjang penuh (bukan 0) & preorderPaid=true',
      (tester) async {
    final product = await seedProduct();
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child:
            MaterialApp(home: Scaffold(body: ItemEntrySheet(product: product))),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ya').first);
    await tester.pumpAndSettle();
    // DP -> Ya (tombol 'Ya' kedua, milik toggle DP).
    await tester.tap(find.text('Ya').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tambah ke Keranjang'));
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider(kMainCartId));
    final item = cart.firstWhere((c) => c.productId == 'p1');
    expect(item.isPreorder, isTrue);
    expect(item.preorderPaid, isTrue);
    expect(item.price, isNot(0),
        reason: 'DP Ya -> harga penuh terisi, dibayar lunas sekarang');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'buka lagi item yg SUDAH pre-order di cart -> toggle Pre-order?/DP? '
      'prefill "Ya" (bukan reset ke Tidak)', (tester) async {
    final product = await seedProduct();
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
    // Cart SUDAH berisi item ini sbg pre-order dgn DP sudah dibayar —
    // persis kondisi "sudah diset pre-order, lalu tap lagi item" yg
    // dilaporkan user.
    container.read(cartProvider(kMainCartId).notifier).setItem(const CartItem(
          productId: 'p1',
          productUnitId: 'u1',
          productName: 'Galon Aqua',
          unitName: 'Satuan',
          qty: 1,
          price: 25000,
          originalPrice: 25000,
          costPrice: 0,
          isPreorder: true,
          preorderPaid: true,
        ));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child:
            MaterialApp(home: Scaffold(body: ItemEntrySheet(product: product))),
      ),
    );
    await tester.pumpAndSettle();

    // "DP? (bayar lunas sekarang)" HANYA dirender saat _isPreorder true —
    // muncul TANPA perlu tap "Ya" dulu membuktikan toggle sudah prefill
    // benar dari cart line yang ada.
    expect(find.text('DP? (bayar lunas sekarang)'), findsOneWidget,
        reason: 'toggle Pre-order? harus prefill "Ya" dari cart, bukan '
            'default "Tidak"');

    // Tap konfirmasi TANPA menyentuh toggle apa pun (skenario "cuma mau
    // lihat/ubah hal lain") — status pre-order TIDAK boleh ikut hilang.
    await tester.tap(find.text('Tambah ke Keranjang'));
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider(kMainCartId));
    final item = cart.firstWhere((c) => c.productId == 'p1');
    expect(item.isPreorder, isTrue,
        reason: 'Simpan tanpa ubah toggle TIDAK boleh menghapus status '
            'pre-order yang sudah ada');
    expect(item.preorderPaid, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
