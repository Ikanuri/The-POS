import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Item 52 ("Laci Meja") — jalur PERTAMA entry Pre-order: tombol "+ Antri"
/// inline di baris pencarian Kasir (tampilan list), muncul HANYA saat
/// produk ditandai stok habis (markedOutOfStock) — usulan user: jangan
/// terlalu banyak step utk masuk ke pencatatan stok kosong.
void main() {
  testWidgets(
      '"+ Antri" tampil di baris list produk Habis, tap -> catat Pre-order '
      'ke Laci Meja', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Tabung LPG 3kg'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u1',
          productId: 'p1',
          isBaseUnit: const Value(true),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 't1',
          productUnitId: 'u1',
          minQty: const Value(1),
          price: 22000,
        ));
    await db.setMarkedOutOfStock('p1', true);

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Kasir',
      deviceCode: 'K1',
      deviceRole: 'owner',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider
            .overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    // Default tampilan grid — pindah ke list supaya baris "+ Antri" (hanya
    // ada di tampilan list) ikut ter-render.
    await tester.tap(find.byIcon(Icons.view_list_rounded));
    await tester.pumpAndSettle();

    expect(find.text('+ Antri'), findsOneWidget);

    await tester.tap(find.text('+ Antri'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Nama pelanggan'), 'Siti');
    await tester.enterText(
        find.widgetWithText(TextField, 'Jumlah dipesan'), '1');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.preorderEntries).get();
    expect(rows, hasLength(1));
    expect(rows.single.customerName, 'Siti');
    expect(rows.single.productId, 'p1');
    expect(rows.single.transactionId, isNull,
        reason: 'entry dari pencarian Kasir belum ada transaksi berjalan');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
