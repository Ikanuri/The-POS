import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/kasir_permissions_screen.dart';

import 'helpers/pump_app.dart';

/// Item 24d — izin baru "Terima Pembayaran" (default OFF). Tanpa izin ini,
/// device role Pegawai (deviceRole internal tetap 'kasir') tidak bisa
/// menyelesaikan pembayaran sendiri — tombol "Bayar" berubah jadi "Kirim ke
/// Owner/Asisten" (lihat kasir_screen.dart).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('DB baru: permission terima_pembayaran ada & default OFF', () async {
    final row = await (db.select(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('terima_pembayaran')))
        .getSingleOrNull();
    expect(row, isNotNull,
        reason: 'baris permission harus otomatis dibuat via seed default');
    expect(row!.isEnabled, isFalse);
  });

  testWidgets(
      'layar Izin Pegawai menampilkan toggle "Terima Pembayaran", tap '
      'menyalakannya di DB', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const KasirPermissionsScreen());

    expect(find.text('Izin Pegawai'), findsOneWidget);
    expect(find.text('Terima Pembayaran'), findsOneWidget);

    final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Terima Pembayaran'));
    expect(tile.value, isFalse, reason: 'default OFF');

    await tester.tap(find.widgetWithText(SwitchListTile, 'Terima Pembayaran'));
    await tester.pumpAndSettle();

    final row = await (db.select(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('terima_pembayaran')))
        .getSingle();
    expect(row.isEnabled, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
