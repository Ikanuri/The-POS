import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/license_provider.dart';
import 'package:the_pos/core/router/app_router.dart';
import 'package:the_pos/core/theme/app_theme.dart';

/// Item 52 susulan — bug NYATA dilaporkan user via device asli: tap kartu
/// di dashboard Laci Meja untuk redirect ke nota menghasilkan HALAMAN
/// BLANK. Versi awal menaruh `/laci-meja` di LUAR `ShellRoute` (biar bottom
/// nav hilang), sedangkan `/kasir/struk/:txId` bersarang DI DALAM shell —
/// push lintas batas shell itulah yang bikin halaman kosong di device.
///
/// Fix: layar ini dipindah ke DALAM shell sbg `/kasir/laci-meja`,
/// MENGIKUTI POLA Buku Hutang (`/laporan` -> HutangTab -> push
/// `/kasir/struk/:txId`) yang sudah lama terbukti di produksi — push antar
/// rute di dalam SATU shell yang sama.
///
/// Test ini WAJIB pakai `routerProvider` ASLI (bukan router tiruan seperti
/// `laci_meja_dashboard_redirect_test.dart`): router tiruan tidak punya
/// `ShellRoute` sama sekali, jadi struktural tidak pernah bisa menangkap
/// kelas bug batas-shell ini.
void main() {
  testWidgets(
      'tap kartu Titip/Ketinggalan di dashboard (via routerProvider asli) '
      '-> struk nota BENAR-BENAR tampil, bukan halaman blank', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'tx1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.addLeftBehindItem(
        id: 'l1', transactionId: 'tx1', itemName: 'Payung', jenis: 'titip');

    const fakeDevice = DeviceIdentity(
        storeUuid: 's',
        storeKey: 'k',
        storeName: 'Toko',
        deviceName: 'Owner',
        deviceCode: 'K1',
        deviceRole: 'owner');

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      licenseProvider.overrideWith(
          (ref) => LicenseNotifier()..state = const LicenseState(exp: 'selamanya')),
    ]);
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    router.go('/kasir/laci-meja');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Payung'));
    await tester.pumpAndSettle();

    expect(find.text('Struk'), findsOneWidget,
        reason: 'redirect harus benar-benar sampai ke layar Struk, bukan '
            'diam di tempat (halaman blank/tidak bereaksi)');
    expect(find.text('LUNAS'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
