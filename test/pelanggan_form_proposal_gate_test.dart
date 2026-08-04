import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/license_provider.dart';
import 'package:the_pos/core/router/app_router.dart';
import 'package:the_pos/core/theme/app_theme.dart';

/// Susulan (permintaan user) — usulan sync pelanggan: device BUKAN owner
/// yang tambah/ubah pelanggan HARUS menandai `locallyModified=true`
/// (`markCustomerLocallyModified`), device OWNER TIDAK PERNAH (pola sama
/// persis dgn gerbang `device.isOwner` di `produk_form_screen.dart`, lihat
/// `produk_form_non_stock_toggle_test.dart` utk pola test lewat router
/// sungguhan — `_save()` menutup layar via `context.pop()`).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<ProviderContainer> pumpPelangganForm(
    WidgetTester tester, {
    required String deviceRole,
    String customerId = 'baru',
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Device',
      deviceCode: 'K1',
      deviceRole: deviceRole,
    );
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      licenseProvider.overrideWith((ref) =>
          LicenseNotifier()..state = const LicenseState(exp: 'selamanya')),
    ]);
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    router.go('/pelanggan/$customerId');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
      'device OWNER tambah pelanggan baru -> locallyModified TETAP false '
      '(owner adalah sumber kebenaran, tidak perlu mengusulkan ke diri '
      'sendiri)', (tester) async {
    await pumpPelangganForm(tester, deviceRole: 'owner');

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama Pelanggan *'), 'Budi Owner');
    await tester.tap(find.text('Simpan Pelanggan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.customers).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Budi Owner');
    expect(rows.single.locallyModified, isFalse);
  });

  testWidgets(
      'device NON-owner (kasir) tambah pelanggan baru -> locallyModified '
      'jadi TRUE (masuk usulan sync, bukan langsung dianggap final)',
      (tester) async {
    await pumpPelangganForm(tester, deviceRole: 'kasir');

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama Pelanggan *'), 'Ani Kasir');
    await tester.tap(find.text('Simpan Pelanggan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.customers).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Ani Kasir');
    expect(rows.single.locallyModified, isTrue);
  });

  testWidgets(
      'device NON-owner (asisten) UBAH pelanggan yang sudah ada -> '
      'locallyModified jadi TRUE juga (bukan cuma pelanggan baru)',
      (tester) async {
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'c1',
          name: 'Nama Lama',
        ));

    await pumpPelangganForm(tester, deviceRole: 'asisten', customerId: 'c1');

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama Pelanggan *'), 'Nama Baru');
    await tester.tap(find.text('Perbarui Data'));
    await tester.pumpAndSettle();

    final row = await (db.select(db.customers)..where((t) => t.id.equals('c1')))
        .getSingle();
    expect(row.name, 'Nama Baru');
    expect(row.locallyModified, isTrue);
  });
}
