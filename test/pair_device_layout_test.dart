import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/pengaturan/pair_device_screen.dart';

import 'helpers/pump_app.dart';

/// Layar Pair Device: tidak overflow di HP pendek (QR 232 + isian) karena
/// isinya kini bisa digulir; ganti role + generate QR tetap bekerja.
void main() {
  testWidgets('HP 360x640: generate QR tanpa overflow, bisa digulir',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await pumpWithFakeApp(
      tester,
      db: db,
      surfaceSize: const Size(360, 640),
      device: DeviceIdentity(
        storeUuid: 'u',
        storeKey: 'a' * 64,
        deviceName: 'X',
        deviceCode: 'O1',
        deviceRole: 'owner',
      ),
      child: const PairDeviceScreen(),
    );
    await tester.pump();
    expect(find.text('Role device yang akan di-pair'), findsOneWidget);
    await tester.tap(find.text('Asisten'));
    await tester.pump();
    await tester.tap(find.text('Generate QR'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Buat Ulang QR'), findsOneWidget);
    expect(find.textContaining('Berlaku:'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // drain: hentikan hitung mundur & stream.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
