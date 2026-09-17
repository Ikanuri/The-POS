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
import 'package:the_pos/features/kasir/cart_debt_settlement_provider.dart';
import 'package:the_pos/features/kasir/cart_preorder_settlement_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart' show kMainCartId;

/// Bug ditemukan (laporan user, screenshot): "Total" di cart bar (layar
/// utama Kasir, SEBELUM buka sheet keranjang) tidak ikut menjumlahkan
/// entri "Lunasi Hutang"/"Pelunasi Pre-order" yang sedang aktif di
/// keranjang — beda dari footer sheet keranjang (`cart_sheet.dart`) yang
/// SUDAH benar menjumlahkan ketiganya (item + debtSettlementTotal +
/// preorderSettlementTotal). Pola bug sama persis Sesi 60 (`_grandTotal`
/// di `payment_screen.dart`), cuma dulu fix-nya tidak menyentuh cart bar
/// layar ini.
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
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 15000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    return db;
  }

  Future<ProviderContainer> pumpKasir(WidgetTester tester, AppDatabase db) async {
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
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tambah 1 item (Rp 15.000) ke keranjang lewat tap "+".
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets(
      'Total di cart bar menjumlahkan item + entri "Lunasi Hutang" yang '
      'aktif di keranjang ini', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    final container = await pumpKasir(tester, db);

    // Prakondisi: sebelum ada settlement, Total cuma harga item.
    expect(find.text(formatRupiah(15000)), findsWidgets);

    container.read(cartDebtSettlementProvider(kMainCartId).notifier).add(
          DebtSettlementEntry(
            id: 'ds1',
            invoiceId: 'tx1',
            invoiceLocalId: 'K1-1',
            invoiceDate: DateTime.now(),
            customerId: 'c1',
            customerName: 'Buk Artia',
            amount: 20000,
            createdAt: DateTime.now(),
          ),
        );
    await tester.pump();
    await tester.pump();

    // Total HARUS jadi 15000 (item) + 20000 (Lunasi Hutang) = 35000, bukan
    // 15000 saja.
    expect(find.text(formatRupiah(35000)), findsWidgets,
        reason: 'Total cart bar wajib ikut menjumlahkan entri Lunasi Hutang '
            'yang aktif, sama seperti footer sheet keranjang');
  });

  testWidgets(
      'Total di cart bar menjumlahkan item + entri "Pelunasi Pre-order" '
      'yang aktif di keranjang ini', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    final container = await pumpKasir(tester, db);

    container.read(cartPreorderSettlementProvider(kMainCartId).notifier).add(
          PreorderSettlementEntry(
            id: 'ps1',
            preorderEntryId: 'po1',
            invoiceId: 'tx1',
            invoiceLocalId: 'K1-1',
            invoiceDate: DateTime.now(),
            customerId: 'c1',
            customerName: 'Buk Artia',
            productName: 'Lpg',
            amount: 36000,
            createdAt: DateTime.now(),
          ),
        );
    await tester.pump();
    await tester.pump();

    // Total HARUS jadi 15000 (item) + 36000 (Pelunasi Pre-order) = 51000.
    expect(find.text(formatRupiah(51000)), findsWidgets,
        reason: 'Total cart bar wajib ikut menjumlahkan entri Pelunasi '
            'Pre-order yang aktif, sama seperti footer sheet keranjang');
  });
}
