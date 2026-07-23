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

/// Item 55/56 — segmen "Bayar" terracotta di cart bar (tab meta, sejajar
/// "Tahan"): muncul utk owner/asisten/pegawai BERIZIN `terima_pembayaran`,
/// tap langsung ke layar Pembayaran (TANPA lewat sheet keranjang dulu).
/// Disembunyikan utk pegawai TANPA izin (jalur mereka tetap "Kirim ke
/// Owner/Asisten" via cart sheet, lihat kasir_handoff_qr_test.dart).
void main() {
  Future<AppDatabase> seedDb({bool terimaPembayaran = false}) async {
    final db = AppDatabase(NativeDatabase.memory());
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('terima_pembayaran')))
        .write(KasirPermissionsCompanion(isEnabled: Value(terimaPembayaran)));
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

  Future<void> pumpKasir(WidgetTester tester, AppDatabase db,
      {required String deviceRole}) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Kasir',
          deviceCode: 'K1',
          deviceRole: deviceRole,
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

    // Tambah item ke keranjang lewat tap ikon "+" (AddControl/quickAdd) di
    // kartu produk (menaikkan cartProvider melalui alur nyata, bukan seed
    // langsung provider — memastikan trigger reservasi nomor nota Item 55
    // ikut teruji). Tap BODY kartu hanya membuka ItemEntrySheet, tidak
    // langsung menambah ke keranjang — lihat onTapBody vs onQuickAdd di
    // kasir_screen.dart.
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('owner melihat segmen Bayar di cart bar, tap ke Pembayaran',
      (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    await pumpKasir(tester, db, deviceRole: 'owner');

    expect(find.text('Bayar'), findsOneWidget);

    await tester.tap(find.text('Bayar'));
    await tester.pumpAndSettle();

    expect(find.text('Pembayaran'), findsOneWidget,
        reason: 'tap Bayar harus langsung ke AppBar layar Pembayaran');
  });

  testWidgets(
      'pegawai TANPA izin terima_pembayaran TIDAK melihat segmen Bayar di '
      'cart bar', (tester) async {
    final db = await seedDb(terimaPembayaran: false);
    addTearDown(() async => db.close());
    await pumpKasir(tester, db, deviceRole: 'kasir');

    expect(find.text('Bayar'), findsNothing);
  });

  testWidgets(
      'pegawai DENGAN izin terima_pembayaran melihat segmen Bayar',
      (tester) async {
    final db = await seedDb(terimaPembayaran: true);
    addTearDown(() async => db.close());
    await pumpKasir(tester, db, deviceRole: 'kasir');

    expect(find.text('Bayar'), findsOneWidget);
  });

  testWidgets(
      'nomor nota (#1) muncul di cart bar setelah item pertama masuk '
      '(reservasi Item 55)', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    await pumpKasir(tester, db, deviceRole: 'owner');

    // Reservasi async — beri kesempatan selesai.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.textContaining('#1'), findsWidgets);
  });
}
