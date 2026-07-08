import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

import 'helpers/pump_app.dart';

/// Widget test — kolom cari di topbar kasir: expand/collapse animasi saat
/// difokus, tombol x (shrink saat kosong / hapus teks saat berisi), dan
/// tap/scroll di luar field mengeluarkan fokus TANPA menghapus teks yang
/// sudah diketik (field hanya shrink secara visual).
void main() {
  Future<double> searchFieldWidth(WidgetTester tester) async {
    final box = tester.renderObject<RenderBox>(find.byType(TextField).first);
    return box.size.width;
  }

  testWidgets(
      'field cari collapsed di awal, melebar saat disentuh, dan tombol x '
      'muncul hanya saat expanded', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const KasirScreen());

    final widthBefore = await searchFieldWidth(tester);
    expect(widthBefore, lessThan(200),
        reason: 'field harus collapsed (sempit) sebelum disentuh');
    expect(find.byIcon(Icons.clear_rounded), findsNothing,
        reason: 'tombol x tidak boleh tampil saat collapsed');

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    final widthAfter = await searchFieldWidth(tester);
    expect(widthAfter, greaterThan(widthBefore + 100),
        reason: 'field harus melebar signifikan setelah disentuh/difokus');
    expect(find.byIcon(Icons.clear_rounded), findsOneWidget,
        reason: 'tombol x harus muncul setelah field expanded');

    await db.close();
  });

  testWidgets(
      'tombol x saat field berisi teks: menghapus teks TAPI tetap expanded '
      '(tidak shrink)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const KasirScreen());

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'gula');
    await tester.pumpAndSettle();

    final widthWithText = await searchFieldWidth(tester);

    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pumpAndSettle();

    expect(find.text('gula'), findsNothing,
        reason: 'teks harus terhapus setelah tap x');
    final widthAfterClear = await searchFieldWidth(tester);
    expect(widthAfterClear, closeTo(widthWithText, 1),
        reason: 'field TIDAK boleh shrink saat x menghapus teks (masih ada '
            'karakter sebelum tap, jadi hanya clear bukan shrink)');
    expect(find.byIcon(Icons.clear_rounded), findsOneWidget,
        reason: 'field tetap expanded (fokus tidak hilang) setelah clear');

    await db.close();
  });

  testWidgets(
      'tombol x saat field kosong: shrink field (unfocus), bukan clear '
      '(karena memang sudah kosong)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const KasirScreen());

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.clear_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pumpAndSettle();

    final width = await searchFieldWidth(tester);
    expect(width, lessThan(200), reason: 'field harus shrink lagi (collapsed)');
    expect(find.byIcon(Icons.clear_rounded), findsNothing,
        reason: 'tombol x hilang lagi setelah collapsed');

    await db.close();
  });

  testWidgets(
      'tap di luar field (mis. area daftar produk) keluar dari state input '
      '(fokus hilang, field shrink) TANPA menghapus teks yang sudah diketik',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const KasirScreen());

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'gula pasir');
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.clear_rounded), findsOneWidget,
        reason: 'prasyarat: field masih expanded sebelum tap di luar');

    // Tap area kosong daftar produk (query aktif, produk tak ditemukan) —
    // di luar field.
    await tester.tap(find.text('Produk tidak ditemukan'));
    await tester.pumpAndSettle();

    final width = await searchFieldWidth(tester);
    expect(width, lessThan(200),
        reason: 'field harus shrink lagi setelah tap di luar field');
    final ctrlText =
        tester.widget<TextField>(find.byType(TextField).first).controller!.text;
    expect(ctrlText, 'gula pasir',
        reason: 'teks yang sudah diketik TIDAK BOLEH hilang hanya karena '
            'field di-collapse oleh tap di luar');

    await db.close();
  });
}
