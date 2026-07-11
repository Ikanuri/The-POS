import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/kasir_permissions_screen.dart';
import 'package:the_pos/features/pengaturan/pengaturan_screen.dart';

import 'helpers/pump_app.dart';

/// Toggle "Izinkan Stok Minus" dipindah dari dalam layar Izin Kasir
/// (kurang terlihat) jadi entri terpisah di halaman utama Pengaturan.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'toggle "Izinkan Stok Minus" tampil di halaman utama Pengaturan (owner)',
      (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const PengaturanScreen());

    expect(find.text('Izinkan Stok Minus'), findsOneWidget);
    final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Izinkan Stok Minus'));
    expect(tile.value, isFalse, reason: 'default OFF');

    await tester.tap(
        find.widgetWithText(SwitchListTile, 'Izinkan Stok Minus'));
    await tester.pumpAndSettle();
    expect(await db.getSetting('allow_negative_stock'), '1');
  });

  testWidgets(
      'toggle "Izinkan Stok Minus" TIDAK LAGI ada di layar Izin Kasir '
      '(sudah pindah ke halaman utama Pengaturan)', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const KasirPermissionsScreen());

    expect(find.text('Izinkan Stok Minus'), findsNothing);

    // Drain drift StreamProvider timer sebelum tearDown (gotcha CLAUDE.md).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
