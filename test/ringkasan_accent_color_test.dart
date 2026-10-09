import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/ringkasan/ringkasan_screen.dart';

import 'helpers/pump_app.dart';

/// Redesain Ringkasan (gaya landing): kartu utama bergradien terracotta,
/// periode (Minggu/Bulan/Rata-rata) dalam satu kartu putih berikon bulat
/// warna fungsi, kartu Kontrol Stok putih (bukan tint penuh).
void main() {
  testWidgets('hero gradien + kartu periode + kartu stok putih',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const RingkasanScreen());

    final hero = tester.widget<Container>(find.byKey(const Key('ringkasan-hero')));
    final deco = hero.decoration as BoxDecoration;
    expect(deco.gradient, isNotNull);

    expect(find.byKey(const Key('ringkasan-periode')), findsOneWidget);
    for (final l in ['Minggu Ini', 'Bulan Ini', 'Rata-rata/Hari']) {
      expect(find.text(l), findsOneWidget);
    }

    final stock = tester.widget<Card>(find.byKey(const Key('ringkasan-stok')));
    expect(stock.color, isNull, reason: 'kartu stok memakai warna kartu tema');
    expect(find.text('Hari Ini'), findsOneWidget);
    expect(AppTheme.changeBg(false), isNotNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets('muat di lebar 360 & skala font 1.3 tanpa overflow',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpWithFakeApp(tester, db: db, child: const RingkasanScreen());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
