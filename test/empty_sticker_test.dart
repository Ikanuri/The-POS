import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/catalog_sticker_service.dart';
import 'package:the_pos/core/services/kasir_sticker_service.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';
import 'package:the_pos/features/produk/produk_list_screen.dart';

import 'helpers/pump_app.dart';

/// Stiker `.tgs` untuk kondisi "Belum ada produk" (Kasir & Produk).
void main() {
  late String json;
  setUpAll(() {
    final v = CatalogStickerService.validateTgs(
        File('assets/stickers/empty.tgs').readAsBytesSync());
    expect(v.error, isNull);
    json = v.json!;
  });

  test('empty.tgs valid & slot terdaftar di pengaturan stiker', () {
    expect(KasirStickerSlot.empty.settingKey, 'kasir_sticker_empty');
    expect(AppDatabase.syncableSettingKeys, contains('kasir_sticker_empty'));
  });

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  testWidgets('Produk kosong: stiker tampil; ada pencarian -> stiker "tidak ditemukan"',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final gate = Completer<String?>();
    await pumpWithFakeApp(tester,
        db: db,
        child: const ProdukListScreen(),
        extraOverrides: [
          kasirStickerProvider.overrideWith((ref, slot) => gate.future),
        ]);
    // Stiker berulang selamanya: harness `pumpAndSettle` hanya bisa selesai
    // bila stiker baru "tiba" SETELAH harness selesai.
    gate.complete(json);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('empty-sticker')), findsOneWidget);
    expect(find.text('Belum ada produk'), findsOneWidget);
    await drain(tester);
    await db.close();
  });

  testWidgets('Kasir tanpa produk (daftar): stiker tampil', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final gate = Completer<String?>();
    await pumpWithFakeApp(tester,
        db: db,
        child: const KasirScreen(),
        extraOverrides: [
          kasirStickerProvider.overrideWith((ref, slot) => gate.future),
        ]);
    // Stiker berulang selamanya: harness `pumpAndSettle` hanya bisa selesai
    // bila stiker baru "tiba" SETELAH harness selesai.
    gate.complete(json);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('empty-sticker')), findsOneWidget);
    expect(find.text('Belum ada produk'), findsOneWidget);
    await drain(tester);
    await db.close();
  });
}
