import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

import 'helpers/pump_app.dart';

/// Widget test — saat field cari kasir dapat fokus ULANG sedangkan teks lama
/// masih ada, seluruh kata otomatis ter-select (select-all). Tujuannya: cari
/// produk berikutnya cukup tap field lalu ketik (langsung menimpa), tanpa
/// harus menjangkau tombol x untuk menghapus dulu.
void main() {
  TextField searchField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first);

  testWidgets(
      'fokus ulang dgn teks lama → seluruh kata ter-select (ketik langsung '
      'menimpa)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const KasirScreen());

    // Fokus + ketik query pertama.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'gula');
    await tester.pumpAndSettle();

    // Keluar dari field (fokus hilang, kolom shrink) — teks tetap ada.
    await tester.tap(find.text('Produk tidak ditemukan'));
    await tester.pumpAndSettle();
    expect(searchField(tester).controller!.text, 'gula',
        reason: 'prasyarat: teks lama masih ada setelah collapse');

    // Fokus ULANG.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    final sel = searchField(tester).controller!.selection;
    expect(sel.baseOffset, 0,
        reason: 'select-all harus mulai dari karakter pertama');
    expect(sel.extentOffset, 'gula'.length,
        reason: 'select-all harus mencakup sampai karakter terakhir');

    // Buktikan efek fungsionalnya: mengetik menimpa seluruh kata lama.
    await tester.enterText(find.byType(TextField).first, 'kopi');
    await tester.pumpAndSettle();
    expect(searchField(tester).controller!.text, 'kopi',
        reason: 'ketik saat seluruh teks ter-select harus menimpa, bukan '
            'menyambung jadi "gulakopi"');

    await db.close();
  });

  testWidgets('fokus pertama saat field kosong → tidak ada teks untuk di-select',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const KasirScreen());

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    // Tak ada teks — tidak ada select-all yang perlu diverifikasi, cukup
    // pastikan tidak crash & controller kosong.
    expect(searchField(tester).controller!.text, isEmpty);

    await db.close();
  });
}
