import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/catalog_sticker_service.dart';
import 'package:the_pos/core/services/order_page_service.dart';
import 'package:the_pos/features/pengaturan/order_share_screen.dart';

import 'helpers/pump_app.dart';

/// Stiker animasi katalog HTML: validasi .tgs, bawaan vs unggahan, penyematan
/// (pustaka hanya bila ada stiker), serta kerangka halaman Toko tutup /
/// Pesanan dikirim dan urutan tombol kirim.
void main() {
  Future<Uint8List> asset(String p) async =>
      Uint8List.fromList(File(p).readAsBytesSync());

  Uint8List gz(Object json) =>
      Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(json))));

  Map<String, dynamic> lottie({int op = 60, List<dynamic>? layers}) => {
        'v': '5.5.2',
        'fr': 30,
        'ip': 0,
        'op': op,
        'w': 512,
        'h': 512,
        'layers': layers ?? [],
      };

  group('validateTgs', () {
    test('keempat stiker bawaan valid', () async {
      for (final s in StickerSlot.values) {
        final v = CatalogStickerService.validateTgs(await asset(s.assetPath));
        expect(v.error, isNull, reason: s.name);
        expect(v.json, isNotNull);
        expect((jsonDecode(v.json!) as Map)['layers'], isNotEmpty);
      }
    });

    test('menolak: bukan gzip, kosong, JSON rusak, bukan Lottie, terlalu panjang, '
        'terlalu besar, memakai expression', () {
      String? err(Uint8List b) => CatalogStickerService.validateTgs(b).error;
      expect(err(Uint8List(0)), isNotNull);
      expect(err(Uint8List.fromList(utf8.encode('{"a":1}'))), isNotNull);
      expect(
          err(Uint8List.fromList(gzip.encode(utf8.encode('bukan json')))),
          isNotNull);
      expect(err(gz({'foo': 1})), isNotNull);
      expect(err(gz(lottie(op: 5000))), contains('panjang'));
      expect(err(Uint8List(CatalogStickerService.maxTgsBytes + 1)),
          contains('besar'));
      // ~300 KB JSON (dekompresi) tapi terkompresi kecil.
      expect(
          err(gz(lottie(layers: [
            {'nm': 'x' * (CatalogStickerService.maxJsonBytes + 10)}
          ]))),
          contains('besar'));
      expect(
          err(gz(lottie(layers: [
            {
              'ks': {
                'o': {'x': 'var \$bm_rt = time;', 'k': 0}
              }
            }
          ]))),
          contains('expression'));
      expect(CatalogStickerService.validateTgs(gz(lottie())).error, isNull);
    });
  });

  group('loadForPublish', () {
    test('bawaan; unggahan menggantikan; unggahan rusak jatuh ke bawaan; '
        'reset kembali ke bawaan', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async => db.close());
      var s = await CatalogStickerService.loadForPublish(db, loadAsset: asset);
      expect(s.keys.toSet(), StickerSlot.values.toSet());
      final defHome = s[StickerSlot.home];

      final mine = gz(lottie(layers: [
        {'nm': 'punya-owner'}
      ]));
      await CatalogStickerService.setCustom(db, StickerSlot.home, mine);
      expect(await CatalogStickerService.isCustom(db, StickerSlot.home), isTrue);
      s = await CatalogStickerService.loadForPublish(db, loadAsset: asset);
      expect(s[StickerSlot.home], contains('punya-owner'));
      expect(s[StickerSlot.closed], isNot(contains('punya-owner')));

      await db.setSetting(
          StickerSlot.home.settingKey, base64Encode(utf8.encode('rusak')));
      s = await CatalogStickerService.loadForPublish(db, loadAsset: asset);
      expect(s[StickerSlot.home], defHome);

      await CatalogStickerService.setCustom(db, StickerSlot.home, mine);
      await CatalogStickerService.resetToDefault(db, StickerSlot.home);
      expect(await CatalogStickerService.isCustom(db, StickerSlot.home), isFalse);
      s = await CatalogStickerService.loadForPublish(db, loadAsset: asset);
      expect(s[StickerSlot.home], defHome);
    });

    test('aset gagal dimuat = slot dilewati, bukan error', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async => db.close());
      final s = await CatalogStickerService.loadForPublish(db,
          loadAsset: (_) async => throw Exception('tidak ada'));
      expect(s, isEmpty);
    });

    test('key setting ikut sinkron antar perangkat toko', () {
      for (final k in CatalogStickerService.allKeys) {
        expect(AppDatabase.syncableSettingKeys, contains(k));
      }
      expect(CatalogStickerService.allKeys,
          StickerSlot.values.map((s) => s.settingKey).toList());
    });
  });

  group('generateHtml', () {
    test('ada stiker: JSON per slot + pustaka tersemat SEKALI; tanpa stiker: '
        'tidak ada pustaka', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async => db.close());
      final stk = await CatalogStickerService.loadForPublish(db, loadAsset: asset);
      final withStk = (await OrderPageService.generateHtml(
              db: db,
              storeName: 'T',
              stickers: stk,
              stickerPlayer: '/*PLAYER*/window.lottie={};'))
          .html;
      for (final s in StickerSlot.values) {
        expect(withStk, contains('application/json" id="stk-${s.name}"'));
      }
      expect('/*PLAYER*/'.allMatches(withStk).length, 1);
      expect(withStk, isNot(contains('__STICKER_BLOCKS__')));

      final none = (await OrderPageService.generateHtml(
              db: db, storeName: 'T', stickers: {}, stickerPlayer: '/*PLAYER*/'))
          .html;
      expect(none, isNot(contains('/*PLAYER*/')));
      expect(none, isNot(contains('application/json" id="stk-')));
      expect(none, isNot(contains('__STICKER_BLOCKS__')));

      // Pemutar tak termuat -> tidak ada blok sama sekali (halaman normal).
      final noPlayer = (await OrderPageService.generateHtml(
              db: db,
              storeName: 'T',
              stickers: stk,
              stickerPlayer: ''))
          .html;
      expect(noPlayer, isNot(contains('application/json" id="stk-')));
    });

    test('JSON stiker memuat "</script>" tidak menutup blok lebih awal', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async => db.close());
      final html = (await OrderPageService.generateHtml(
              db: db,
              storeName: 'T',
              stickers: {StickerSlot.home: '{"nm":"</script><b>x</b>"}'},
              stickerPlayer: 'var P=1;'))
          .html;
      expect(html, isNot(contains('</script><b>x</b>')));
      expect(html, contains(r'<\/script><b>x'));
    });

    test('kerangka: kotak stiker di 4 tempat, halaman tutup & terkirim, '
        'urutan tombol Kosongkan | Telegram | WhatsApp', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async => db.close());
      final html = (await OrderPageService.generateHtml(
              db: db, storeName: 'T', stickers: {}))
          .html;
      expect(html, contains('data-stk="home"'));
      expect(html, contains('data-stk="closed"'));
      expect(html, contains('data-stk="sent"'));
      expect(html, contains("data-stk', 'notFound'"));
      // Halaman tutup.
      expect(html, contains('id="closedPage"'));
      expect(html, contains('Toko sedang tutup</h2>'));
      expect(html, contains('Buka lagi '));
      expect(html, contains('Pesan titipan · toko tutup'));
      expect(html, contains('#app.shop-closed #annBtn'));
      expect(html, isNot(contains('id="closedBanner"')));
      // Halaman terkirim.
      expect(html, contains('id="pageSent"'));
      expect(html, contains('Pesanan dikirim!'));
      expect(html, contains('Kembali ke halaman awal</button>'));
      expect(html, contains('if (sentOpen) { closeSent(true); return; }'));
      expect('showSent();'.allMatches(html).length, 2); // WA + Telegram
      // Tidak ditemukan: teks saja, tanpa saran/tombol.
      expect(html, contains('tidak ditemukan\''));
      expect(html, isNot(contains('<div class="empty">Produk "')));
      // Urutan visual tombol: WhatsApp selalu paling kanan.
      expect(html, contains('#mbClear{order:0;}'));
      expect(html, contains('#mainBtnTg{order:1;}'));
      expect(html, contains('#mainBtn{order:2;}'));
      expect(html, contains('#app.order-mode.has-tg #mainBtn{margin-left:8px;}'));
    });
  });

  testWidgets('kartu Stiker animasi: 4 slot, Bawaan; berkas tak valid tak '
      'mengubah apa pun; Reset kembali ke bawaan', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await pumpWithFakeApp(tester,
        db: db,
        child: const OrderShareScreen(),
        surfaceSize: const Size(360, 4200));
    await tester.pumpAndSettle();
    for (final s in StickerSlot.values) {
      expect(find.byKey(ValueKey('sticker-${s.name}')), findsOneWidget);
      expect(find.byKey(ValueKey('sticker-pick-${s.name}')), findsOneWidget);
      expect(find.byKey(ValueKey('sticker-reset-${s.name}')), findsNothing);
    }
    expect(find.text('Bawaan'), findsNWidgets(4));

    await tester.runAsync(() => CatalogStickerService.setCustom(
        db, StickerSlot.sent, gz(lottie())));
    // Provider dibaca ulang saat layar dibangun ulang.
    await tester.pumpWidget(const SizedBox());
    await pumpWithFakeApp(tester,
        db: db,
        child: const OrderShareScreen(),
        surfaceSize: const Size(360, 4200));
    await tester.pumpAndSettle();
    expect(find.text('Unggahan sendiri'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sticker-reset-sent')));
    await tester.pumpAndSettle();
    expect(find.text('Unggahan sendiri'), findsNothing);
    expect(
        await tester.runAsync(
            () => CatalogStickerService.isCustom(db, StickerSlot.sent)),
        isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
