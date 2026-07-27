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
/// BLANK. `laci_meja_dashboard_redirect_test.dart` (router sederhana buatan
/// sendiri, TANPA ShellRoute) tidak menangkap ini krn di sana
/// '/kasir/struk/:txId' cuma rute top-level biasa — beda dari router ASLI
/// app (`routerProvider`) yang membungkus rute itu di DALAM `ShellRoute`
/// (`MainShell`), sedangkan `/laci-meja` sengaja di LUAR ShellRoute (biar
/// bottom nav hilang, layar penuh).
///
/// Akar bug: `context.push()` dari rute DI LUAR ShellRoute ke rute
/// BERSARANG di dalam ShellRoute diam-diam GAGAL TOTAL — lokasi tidak
/// pernah berubah sama sekali, TANPA exception/error yang terlihat di mana
/// pun. `context.go()` (replace seluruh stack) bekerja normal. Test ini
/// pakai `routerProvider` ASLI (bukan router buatan sendiri) supaya benar²
/// menangkap kelas bug integrasi ShellRoute ini kalau terulang.
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
    router.go('/laci-meja');
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
