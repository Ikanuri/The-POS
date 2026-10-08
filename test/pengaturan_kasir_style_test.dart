import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/pengaturan_screen.dart';

import 'helpers/pump_app.dart';

/// Pengaturan > Gaya Kasir: Klasik menampilkan sakelar Mode Gelap di sini;
/// gaya Baru memindahkannya ke layar Kasir (disembunyikan di Pengaturan).
void main() {
  testWidgets('Klasik: Mode Gelap ada di Pengaturan', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const PengaturanScreen());
    await tester.scrollUntilVisible(
        find.byKey(const Key('setting-kasir-style')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('setting-dark-mode')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets('Baru: Mode Gelap disembunyikan dari Pengaturan', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester,
        db: db,
        child: const PengaturanScreen(),
        initialPrefs: {'kasir_style': 'modern'});
    await tester.scrollUntilVisible(
        find.byKey(const Key('setting-kasir-style')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('setting-dark-mode')), findsNothing);
    expect(find.byKey(const Key('setting-kasir-sticker')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
