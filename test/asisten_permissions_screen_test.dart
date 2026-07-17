import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';
import 'package:the_pos/features/pengaturan/asisten_permissions_screen.dart';

import 'helpers/pump_app.dart';

/// Bug dilaporkan user: owner sudah nyalakan toggle "Izinkan Stok Minus" di
/// layar Izin Asisten, tapi asisten tetap TIDAK BISA override stok minus
/// saat checkout.
void main() {
  testWidgets(
      'toggle "Izinkan Stok Minus" ON di layar Izin Asisten -> DB benar2 '
      'tersimpan, DAN resolveAllowNegativeStock utk device asisten jadi true',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.setSetting('allow_negative_stock', '0');

    await pumpWithFakeApp(tester, db: db, child: const AsistenPermissionsScreen());

    expect(find.text('Izinkan Stok Minus'), findsOneWidget);
    final switchFinder = find.byType(SwitchListTile);
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // UI harus merefleksikan ON setelah tap.
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);

    // DB benar-benar tersimpan (bukan cuma state widget lokal).
    expect(await db.isPermissionEnabled('asisten_stok_minus'), isTrue);

    // Dan device asisten sungguhan sekarang boleh override stok minus.
    const asisten = DeviceIdentity(deviceRole: 'asisten');
    expect(await resolveAllowNegativeStock(db, asisten), isTrue);

    await db.close();
  });
}
