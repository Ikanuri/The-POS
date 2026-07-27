import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/license_provider.dart';
import 'package:the_pos/core/router/app_router.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart' show kMainCartId;

/// Redesain cart bar (permintaan user):
/// - atribut Laci Meja pelanggan yg sama muncul BERJEJER SATU BARIS PER
///   KATEGORI di atas Total (line 1 titip/ketinggalan, line 2 pinjaman,
///   line 3 pre-order lengkap dgn produk+qty+jaminan);
/// - pengingat hutang akumulatif (berapa nota, total berapa) muncul DI BAWAH
///   nominal Total.
void main() {
  Future<AppDatabase> seedDb() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Gula Pasir'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(
              id: 't1', productUnitId: 'u1', price: 15000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Bu Artia'));
    return db;
  }

  Future<ProviderContainer> pumpKasir(
      WidgetTester tester, AppDatabase db) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Kasir',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
      licenseProvider.overrideWith((ref) =>
          LicenseNotifier()..state = const LicenseState(exp: 'selamanya')),
    ]);
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    router.go('/kasir');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
            theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    // Isi keranjang lewat alur nyata supaya cart bar muncul.
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets(
      'atribut Laci Meja pelanggan muncul BERJEJER per kategori di cart bar '
      '(titip/ketinggalan, pinjaman, pre-order dgn produk+qty+jaminan)',
      (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'txLama',
        localId: 'K1-9',
        status: 'lunas',
        total: 1000,
        paid: 1000,
        changeAmount: 0,
        paymentMethod: 'tunai'));
    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: 'txLama',
        itemName: 'Payung',
        jenis: 'ketinggalan',
        customerId: 'c1');
    await db.addBorrowedItem(
        id: 'b1',
        transactionId: 'txLama',
        itemName: 'Galon kosong',
        qty: 1,
        customerId: 'c1');
    await db.addPreorderEntry(
        id: 'po1',
        productId: 'p1',
        productUnitId: 'u1',
        customerName: 'Bu Artia',
        qtyOrdered: 2,
        depositQty: 2,
        transactionId: 'txLama');

    final container = await pumpKasir(tester, db);
    container
        .read(cartMetaProvider(kMainCartId).notifier)
        .setCustomer('c1', 'Bu Artia');
    // JANGAN pumpAndSettle di sini: nama pelanggan yang tidak muat memicu
    // teks berjalan (`_MarqueeText`) yang animasinya BERULANG selamanya —
    // pumpAndSettle akan timeout. Pump beberapa frame berdurasi tetap saja.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('1 barang ketinggalan'), findsOneWidget,
        reason: 'line 1 — titip/ketinggalan');
    expect(find.text('1 pinjaman belum kembali'), findsOneWidget,
        reason: 'line 2 — pinjaman barang');
    expect(find.text('Pre-order: 2 Gula Pasir (jaminan 2)'), findsOneWidget,
        reason: 'line 3 — pre-order WAJIB sebut produk, qty & jaminan');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'pengingat hutang akumulatif (jumlah nota + total) muncul di cart bar',
      (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());

    // Dua nota belum lunas milik pelanggan yang sama.
    for (final (id, total, paid) in [('t1', 50000, 20000), ('t2', 30000, 0)]) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: 'K1-$id',
          customerId: const Value('c1'),
          status: 'kurang_bayar',
          total: total,
          paid: paid,
          changeAmount: 0,
          paymentMethod: 'tunai'));
    }

    final container = await pumpKasir(tester, db);
    container
        .read(cartMetaProvider(kMainCartId).notifier)
        .setCustomer('c1', 'Bu Artia');
    // JANGAN pumpAndSettle di sini: nama pelanggan yang tidak muat memicu
    // teks berjalan (`_MarqueeText`) yang animasinya BERULANG selamanya —
    // pumpAndSettle akan timeout. Pump beberapa frame berdurasi tetap saja.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // (50.000-20.000) + (30.000-0) = 60.000 di 2 nota.
    expect(find.text('Hutang ${formatRupiah(60000)} di 2 nota'), findsOneWidget,
        reason: 'akumulatif: total rupiah + berapa nota');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('pelanggan tanpa hutang -> baris hutang tidak muncul',
      (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());

    final container = await pumpKasir(tester, db);
    container
        .read(cartMetaProvider(kMainCartId).notifier)
        .setCustomer('c1', 'Bu Artia');
    // JANGAN pumpAndSettle di sini: nama pelanggan yang tidak muat memicu
    // teks berjalan (`_MarqueeText`) yang animasinya BERULANG selamanya —
    // pumpAndSettle akan timeout. Pump beberapa frame berdurasi tetap saja.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Hutang '), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
