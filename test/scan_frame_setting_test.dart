import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/scan_frame_provider.dart';
import 'package:the_pos/features/pengaturan/pengaturan_screen.dart';

import 'helpers/pump_app.dart';

/// Saklar eksperimental "Bingkai Scanner ala Telegram": default mati,
/// tersimpan di SharedPreferences, ada di Pengaturan.
void main() {
  test('provider: default mati, set() menyimpan ke prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(scanFrameTelegramProvider), isFalse);
    await c.read(scanFrameTelegramProvider.notifier).set(true);
    expect(c.read(scanFrameTelegramProvider), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ScanFrameStyleNotifier.prefKey), isTrue);
  });

  test('provider: memuat nilai tersimpan', () async {
    SharedPreferences.setMockInitialValues({'scan_frame_telegram': true});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(scanFrameTelegramProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(scanFrameTelegramProvider), isTrue);
  });

  testWidgets('Pengaturan: ada saklar & bisa dinyalakan', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const PengaturanScreen());
    final sw = find.byKey(const Key('setting-scan-frame'));
    await tester.ensureVisible(sw);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(sw).value, isFalse);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(sw).value, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
