import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/pengaturan/asisten_permissions_screen.dart';
import 'package:the_pos/features/pengaturan/kasir_permissions_screen.dart';
import 'package:the_pos/features/pengaturan/pengaturan_screen.dart';

import 'helpers/pump_app.dart';

Future<void> _setPermission(AppDatabase db, String key, bool enabled) =>
    (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals(key)))
        .write(KasirPermissionsCompanion(isEnabled: Value(enabled)));

/// Screening "guard file sensitif" (permintaan user): dulu "Backup &
/// Restore" TIDAK PERNAH digate sama sekali (menu terlihat & bisa dibuka
/// oleh Kasir MAUPUN Asisten tanpa syarat apa pun — celah nyata dibanding
/// "Import/Export CSV Produk" yang sudah owner-only). "Alihkan Owner" juga
/// senasib (tidak digate).
///
/// Fix: owner selalu bisa; Kasir/Asisten opsional lewat toggle baru
/// (`akses_backup`/`akses_csv_produk` utk Kasir, versi `asisten_` utk
/// Asisten — default OFF, owner yang putuskan per toko). "Alihkan Owner"
/// SENGAJA TETAP owner-only murni tanpa toggle (menimpa TOTAL identitas
/// + data toko/device, bukan cuma data biasa).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  const kasirDevice = DeviceIdentity(
    storeUuid: 's',
    storeKey: 'k',
    storeName: 'Toko',
    deviceName: 'Kasir 1',
    deviceCode: 'K2',
    deviceRole: 'kasir',
  );
  const asistenDevice = DeviceIdentity(
    storeUuid: 's',
    storeKey: 'k',
    storeName: 'Toko',
    deviceName: 'Asisten 1',
    deviceCode: 'K3',
    deviceRole: 'asisten',
  );

  testWidgets('owner: Backup & Restore, CSV, dan Alihkan Owner semua tampil',
      (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const PengaturanScreen());

    expect(find.text('Backup & Restore'), findsOneWidget);
    expect(find.text('Import Produk CSV'), findsOneWidget);
    expect(find.text('Export Produk CSV'), findsOneWidget);
    expect(find.text('Alihkan Owner'), findsOneWidget);

    await drain(tester);
  });

  testWidgets(
      'kasir TANPA izin apa pun: Backup & Restore, CSV, DAN Alihkan Owner '
      'semua TIDAK tampil', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const PengaturanScreen(), device: kasirDevice);

    expect(find.text('Backup & Restore'), findsNothing);
    expect(find.text('Import Produk CSV'), findsNothing);
    expect(find.text('Export Produk CSV'), findsNothing);
    expect(find.text('Alihkan Owner'), findsNothing,
        reason: 'Alihkan Owner tidak pernah dapat toggle -- owner-only '
            'murni apa pun izin lain yang aktif');

    await drain(tester);
  });

  testWidgets(
      'kasir DENGAN izin akses_backup ON: Backup & Restore tampil, CSV '
      'tetap tidak (izin terpisah), Alihkan Owner tetap tidak',
      (tester) async {
    await _setPermission(db, 'akses_backup', true);
    await pumpWithFakeApp(tester,
        db: db, child: const PengaturanScreen(), device: kasirDevice);

    expect(find.text('Backup & Restore'), findsOneWidget);
    expect(find.text('Import Produk CSV'), findsNothing);
    expect(find.text('Alihkan Owner'), findsNothing);

    await drain(tester);
  });

  testWidgets(
      'kasir DENGAN izin akses_csv_produk ON: CSV tampil, Backup tetap '
      'tidak (izin terpisah)', (tester) async {
    await _setPermission(db, 'akses_csv_produk', true);
    await pumpWithFakeApp(tester,
        db: db, child: const PengaturanScreen(), device: kasirDevice);

    expect(find.text('Import Produk CSV'), findsOneWidget);
    expect(find.text('Export Produk CSV'), findsOneWidget);
    expect(find.text('Backup & Restore'), findsNothing);

    await drain(tester);
  });

  testWidgets(
      'asisten DENGAN izin asisten_akses_backup ON: Backup tampil (key '
      'BEDA dari punya kasir, tidak boleh nyasar)', (tester) async {
    await _setPermission(db, 'asisten_akses_backup', true);
    await pumpWithFakeApp(tester,
        db: db, child: const PengaturanScreen(), device: asistenDevice);

    expect(find.text('Backup & Restore'), findsOneWidget);
    expect(find.text('Import Produk CSV'), findsNothing);
    expect(find.text('Alihkan Owner'), findsNothing);

    await drain(tester);
  });

  testWidgets(
      'izin akses_backup milik KASIR ON tidak ikut menyalakan punya '
      'ASISTEN (key terpisah total)', (tester) async {
    await _setPermission(db, 'akses_backup', true);
    await pumpWithFakeApp(tester,
        db: db, child: const PengaturanScreen(), device: asistenDevice);

    expect(find.text('Backup & Restore'), findsNothing,
        reason: 'toggle punya Kasir tidak boleh nyasar ke Asisten');

    await drain(tester);
  });

  testWidgets('toggle baru tampil & berfungsi di layar Izin Pegawai',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const KasirPermissionsScreen());

    expect(find.text('Backup & Restore'), findsOneWidget);
    expect(find.text('Import/Export CSV Produk'), findsOneWidget);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Backup & Restore'));
    await tester.pumpAndSettle();
    expect(await db.isPermissionEnabled('akses_backup'), isTrue);

    await drain(tester);
  });

  testWidgets('toggle baru tampil & berfungsi di layar Izin Asisten',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const AsistenPermissionsScreen());

    expect(find.text('Backup & Restore'), findsOneWidget);
    expect(find.text('Import/Export CSV Produk'), findsOneWidget);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Backup & Restore'));
    await tester.pumpAndSettle();
    expect(await db.isPermissionEnabled('asisten_akses_backup'), isTrue);

    await drain(tester);
  });
}
