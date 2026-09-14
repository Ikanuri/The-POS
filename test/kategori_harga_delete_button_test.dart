import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/kategori_harga_screen.dart';

import 'helpers/pump_app.dart';

/// Permintaan user: beri opsi hapus Kategori Harga — sebelumnya hapus HANYA
/// bisa lewat swipe (`Dismissible`), tidak ada tombol terlihat sama sekali
/// sehingga tidak mudah ditemukan. Tombol hapus eksplisit ditambah di
/// samping tombol "Ubah nama" yang sudah ada; swipe TETAP berfungsi sbg
/// jalan pintas tambahan (tidak dihapus).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  testWidgets(
      'tombol hapus (ikon delete) tampil eksplisit di baris kategori, '
      'BUKAN cuma bisa lewat swipe', (tester) async {
    await db.addPriceCategory('Grosir');
    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());

    expect(find.byTooltip('Hapus kategori'), findsOneWidget);
    expect(find.byTooltip('Ubah nama'), findsOneWidget);

    await drain(tester);
  });

  testWidgets(
      'ketuk tombol hapus -> dialog konfirmasi -> konfirmasi -> kategori '
      'hilang dari daftar & tertombstone di DB', (tester) async {
    final id = await db.addPriceCategory('Grosir');
    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());

    await tester.tap(find.byTooltip('Hapus kategori'));
    await tester.pumpAndSettle();

    expect(find.text('Hapus Grosir?'), findsOneWidget,
        reason: 'tombol harus memunculkan dialog konfirmasi yang sama '
            'dengan swipe, bukan langsung hapus tanpa konfirmasi');

    await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await tester.pumpAndSettle();

    expect(find.text('Grosir'), findsNothing);
    final cats = await db.getAllPriceCategories();
    expect(cats.any((c) => c.id == id), isFalse);

    await drain(tester);
  });

  testWidgets('ketuk tombol hapus -> Batal -> kategori TETAP ada',
      (tester) async {
    await db.addPriceCategory('Grosir');
    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());

    await tester.tap(find.byTooltip('Hapus kategori'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    expect(find.text('Grosir'), findsOneWidget);

    await drain(tester);
  });
}
