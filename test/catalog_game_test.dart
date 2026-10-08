import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/catalog_display_service.dart';
import 'package:the_pos/core/services/order_page_service.dart';
import 'package:the_pos/features/pengaturan/order_share_screen.dart';

import 'helpers/pump_app.dart';

/// Game labirin di katalog HTML: bawaan NYALA, bisa dimatikan dari pengaturan,
/// tersinkron antar perangkat, dan ikut di HTML (kartu + skrip).
void main() {
  Map<String, dynamic> dataOf(String html) {
    final m = RegExp(r'^var DATA = (.+);$', multiLine: true).firstMatch(html)!;
    return jsonDecode(m.group(1)!) as Map<String, dynamic>;
  }

  test('bawaan nyala; dimatikan -> DATA.game false; key ikut sync', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    expect((await CatalogDisplayService.load(db)).gameEnabled, isTrue);
    var html = (await OrderPageService.generateHtml(
            db: db, storeName: 'T', stickers: {}))
        .html;
    expect(dataOf(html)['game'], isTrue);
    expect(html, contains('id="mazeCard"'));
    expect(html, contains('id="gameSlot"'));
    expect(html, contains('function placeGame(closed)'));
    // Kartu dipindah ke halaman tutup saat init: pakai entri IntersectionObserver
    // TERBARU (es[0] basi bikin loop game tak pernah jalan).
    expect(html, contains('es[es.length - 1].isIntersecting'));
    // Papan berubah ukuran (awal 320 bawaan -> lebar asli): dinding dibangun
    // ulang & bola diskalakan, kalau tidak lubang tujuan "melayang" di luar
    // labirin; ukuran 0 (tersembunyi) tidak mereset papan.
    expect(html, contains('buildRects();\n      var span = W - 2 * pad'));
    expect(html, contains('if (!cw && cv.width) return;'));

    await CatalogDisplayService.setGameEnabled(db, false);
    expect((await CatalogDisplayService.load(db)).gameEnabled, isFalse);
    html = (await OrderPageService.generateHtml(
            db: db, storeName: 'T', stickers: {}))
        .html;
    expect(dataOf(html)['game'], isFalse);
    expect(AppDatabase.syncableSettingKeys,
        contains(CatalogDisplayService.gameKey));
    expect(CatalogDisplayService.allKeys,
        contains(CatalogDisplayService.gameKey));
  });

  testWidgets('saklar "Tampilkan game labirin": nyala bawaan, tersimpan saat '
      'dimatikan', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await pumpWithFakeApp(tester,
        db: db,
        child: const OrderShareScreen(),
        surfaceSize: const Size(360, 4200));
    await tester.pumpAndSettle();
    const k = ValueKey('display-game');
    expect(tester.widget<SwitchListTile>(find.byKey(k)).value, isTrue);
    await tester.tap(find.byKey(k));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(k)).value, isFalse);
    expect((await tester.runAsync(() => CatalogDisplayService.load(db)))!
        .gameEnabled, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
