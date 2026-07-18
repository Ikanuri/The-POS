import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/product_group_screen.dart';

import 'helpers/pump_app.dart';

/// Widget-tier utk fitur bulk add/remove kategori (permintaan user).
void main() {
  testWidgets(
      'Tambah Massal: input multi-baris menambah semua kategori sekaligus',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const ProductGroupScreen());

    await tester.tap(find.byTooltip('Tambah Massal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Minuman\nMakanan\nSnack');
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();

    expect(find.text('Minuman'), findsOneWidget);
    expect(find.text('Makanan'), findsOneWidget);
    expect(find.text('Snack'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'long-press masuk mode pilih, centang beberapa, Hapus Terpilih '
      'menghapus semuanya sekaligus', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.addProductGroups(['Minuman', 'Makanan', 'Snack']);
    await pumpWithFakeApp(tester, db: db, child: const ProductGroupScreen());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Minuman'));
    await tester.pumpAndSettle();

    expect(find.text('1 dipilih'), findsOneWidget);

    await tester.tap(find.text('Makanan'));
    await tester.pumpAndSettle();
    expect(find.text('2 dipilih'), findsOneWidget);

    await tester.tap(find.byTooltip('Hapus Terpilih'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();

    expect(find.text('Minuman'), findsNothing);
    expect(find.text('Makanan'), findsNothing);
    expect(find.text('Snack'), findsOneWidget,
        reason: 'kategori yg tidak dicentang tidak boleh ikut terhapus');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
