import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/catalog_display_service.dart';
import 'package:the_pos/core/services/order_page_service.dart';
import 'package:the_pos/features/pengaturan/order_share_screen.dart';

import 'helpers/pump_app.dart';

/// Layar Katalog Pesanan — kartu pengaturan tampilan katalog baru: kategori,
/// periode & jumlah saran terlaris, pengumuman toko, Pesan lagi. Viewport
/// sesempit HP (360 px): tidak boleh overflow; nilai tersimpan & ikut
/// mempengaruhi `generateHtml`.
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  Map<String, dynamic> dataOf(String html) {
    final m = RegExp(r'^var DATA = (.+);$', multiLine: true).firstMatch(html)!;
    return jsonDecode(m.group(1)!) as Map<String, dynamic>;
  }

  Future<void> pumpScreen(WidgetTester tester, AppDatabase db) async {
    await pumpWithFakeApp(tester,
        db: db,
        child: const OrderShareScreen(),
        surfaceSize: const Size(360, 3600));
    await tester.pumpAndSettle();
  }

  testWidgets('default: kategori ON, 30 hari, 8 saran, Pesan lagi ON',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await pumpScreen(tester, db);

    expect(find.text('Tampilkan kategori'), findsOneWidget);
    expect(find.text('Jumlah saran'), findsOneWidget);
    expect(find.text('Tampilkan pengumuman'), findsOneWidget);
    expect(find.text('Tampilkan "Pesan lagi"'), findsOneWidget);
    expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('display-categories')))
            .value,
        isTrue);
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('top-days-30')))
            .selected,
        isTrue);
    expect(tester.widget<DropdownButton<int>>(find.byKey(const ValueKey('top-count'))).value, 8);
    expect(tester.takeException(), isNull);
    await drain(tester);
  });

  testWidgets('toggle kategori, periode, jumlah saran, Pesan lagi tersimpan '
      '& mempengaruhi generateHtml', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await pumpScreen(tester, db);

    await tester.tap(find.byKey(const ValueKey('display-categories')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('top-days-90')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('top-count')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('display-reorder')));
    await tester.pumpAndSettle();

    final d = await CatalogDisplayService.load(db);
    expect(d.showCategories, isFalse);
    expect(d.topDays, 90);
    expect(d.topCount, 5);
    expect(d.reorderEnabled, isFalse);

    final data = dataOf(
        (await tester.runAsync(() => OrderPageService.generateHtml(
                db: db, storeName: 'Toko')))!
            .html);
    expect(data['showCategories'], isFalse);
    expect(data['reorder'], isFalse);
    expect(tester.takeException(), isNull);
    await drain(tester);
  });

  testWidgets('pengumuman: toggle + teks, penghitung & perkiraan lama tampil',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await pumpScreen(tester, db);

    expect(find.text('0 / 280'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('announce-enabled')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('announce-text')), 'Besok toko libur');
    await tester.pumpAndSettle();

    // 16 huruf -> 3000 + 60*16 = 3960 ms ~ 4 detik.
    expect(find.text('16 / 280 · tampil otomatis ± 4 detik'), findsOneWidget);
    final d = await CatalogDisplayService.load(db);
    expect(d.announceEnabled, isTrue);
    expect(d.announceText, 'Besok toko libur');

    final data = dataOf(
        (await tester.runAsync(() => OrderPageService.generateHtml(
                db: db, storeName: 'Toko')))!
            .html);
    expect(data['announcement'], {'text': 'Besok toko libur', 'enabled': true});
    expect(tester.takeException(), isNull);
    await drain(tester);
  });

  testWidgets('teks pengumuman dibatasi 280 karakter', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await pumpScreen(tester, db);
    await tester.enterText(
        find.byKey(const ValueKey('announce-text')), 'x' * 400);
    await tester.pumpAndSettle();
    expect(find.textContaining('280 / 280'), findsOneWidget);
    expect((await CatalogDisplayService.load(db)).announceText.length, 280);
    await drain(tester);
  });

  testWidgets('rentang tanggal sendiri tampil sebagai label chip',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await CatalogDisplayService.setTopRange(
        db, DateTime(2026, 9, 1), DateTime(2026, 9, 10));
    await pumpScreen(tester, db);
    expect(find.text('1 Sep - 10 Sep 2026'), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('top-days-30')))
            .selected,
        isFalse);
    await drain(tester);
  });
}
