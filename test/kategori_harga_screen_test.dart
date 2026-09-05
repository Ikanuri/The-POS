import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/kategori_harga_screen.dart';

import 'helpers/pump_app.dart';

/// Fase B "Kategori Harga" — level UI (`pumpWithFakeApp`). Lihat dok
/// `AppDatabase.getPriceCategoryMembers`/`setPriceCategoryMargin` untuk
/// logic level-DB (sudah dites terpisah di `price_categories_db_test.dart`).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// Sama dgn drain() di `payment_method_edit_delete_test.dart` — WAJIB di
  /// akhir tiap testWidgets yg memakai layar dgn `StreamProvider` drift
  /// (`watchPriceCategories`), lihat CLAUDE.md §Gotcha.
  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  Future<String> seedProduct({
    required String id,
    required String name,
    required int basePrice,
    required int costPrice,
  }) async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: id, name: name));
    final unitId = '${id}_u';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId, productId: id, isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: '${id}_tier',
          productUnitId: unitId,
          minQty: const Value(1),
          price: basePrice,
          costPrice: Value(costPrice),
        ));
    return unitId;
  }

  testWidgets('tambah kategori baru muncul di list', (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Grosir');
    await tester.tap(find.widgetWithText(FilledButton, 'Tambah'));
    await tester.pumpAndSettle();

    expect(find.text('Grosir'), findsOneWidget);
    final cats = await db.getAllPriceCategories();
    expect(cats.map((c) => c.name), contains('Grosir'));
    await drain(tester);
  });

  testWidgets(
      'tambah produk ke kategori + isi margin via field Margin -> Harga '
      'Jual ikut update -> simpan tertulis ke AltPrices', (tester) async {
    await seedProduct(
        id: 'p1', name: 'Beras 5kg', basePrice: 10000, costPrice: 7000);
    final catId = await db.addPriceCategory('Grosir');

    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());
    await tester.tap(find.text('Grosir'));
    await tester.pumpAndSettle();

    expect(find.text('Produk — Grosir'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // Layar pemilih produk.
    expect(find.text('Tambah Produk'), findsOneWidget);
    await tester.tap(find.text('Beras 5kg'));
    await tester.pumpAndSettle();

    // Editor margin terbuka otomatis, default acuan Dasar + Persen.
    expect(find.text('Beras 5kg · Kg'), findsOneWidget);
    final marginField =
        find.widgetWithText(TextField, 'Margin').first;
    await tester.enterText(marginField, '20');
    await tester.pump();

    // 10000 * 1.2 = 12000.
    expect(find.widgetWithText(TextField, 'Harga Jual'), findsOneWidget);
    final sellFieldFinder = find.byWidgetPredicate((w) =>
        w is TextField &&
        w.decoration?.labelText == 'Harga Jual');
    final sellField = tester.widget<TextField>(sellFieldFinder);
    expect(sellField.controller!.text, '12000');

    await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await tester.pumpAndSettle();

    final members = await db.getPriceCategoryMembers(catId);
    expect(members, hasLength(1));
    expect(members.single.currentPrice, 12000);
    expect(members.single.marginType, 'percent');
    expect(members.single.marginValue, 20);
    await drain(tester);
  });

  testWidgets(
      'isi via field Harga Jual -> Margin ikut update (arah kebalikan)',
      (tester) async {
    final unitId = await seedProduct(
        id: 'p1', name: 'Beras 5kg', basePrice: 10000, costPrice: 7000);
    final catId = await db.addPriceCategory('Grosir');

    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());
    await tester.tap(find.text('Grosir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beras 5kg'));
    await tester.pumpAndSettle();

    final sellFieldFinder = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'Harga Jual');
    await tester.enterText(sellFieldFinder, '15000');
    await tester.pump();

    // (15000 - 10000) / 10000 * 100 = 50.
    final marginFieldFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Margin');
    final marginField = tester.widget<TextField>(marginFieldFinder);
    expect(marginField.controller!.text, '50');

    await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await tester.pumpAndSettle();

    final alts = await db.getAltPrices(unitId);
    expect(alts.single.price, 15000);
    // ignore: unused_local_variable
    final _ = catId;
    await drain(tester);
  });

  testWidgets(
      'toggle Acuan "Harga Modal" DISABLED kalau costPrice produk <= 0',
      (tester) async {
    await seedProduct(
        id: 'p1', name: 'Rokok Ecer', basePrice: 2000, costPrice: 0);
    await db.addPriceCategory('Ecer');

    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());
    await tester.tap(find.text('Ecer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rokok Ecer'));
    await tester.pumpAndSettle();

    expect(find.text('Harga Modal (HPP) belum diisi untuk produk ini — '
            'pakai Harga Dasar, atau isi HPP dulu di form Produk.'),
        findsOneWidget);

    // Coba tap segment "Harga Modal" — disabled, tidak boleh berubah acuan
    // (masih Dasar, verifikasi via harga jual yg tetap konsisten dgn dasar).
    await tester.tap(find.text('Harga Modal'), warnIfMissed: false);
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Margin'), '10');
    await tester.pump();
    final sellFieldFinder = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'Harga Jual');
    final sellField = tester.widget<TextField>(sellFieldFinder);
    // 2000 * 1.10 = 2200 (dari Dasar, BUKAN dari costPrice 0 yang mustahil).
    expect(sellField.controller!.text, '2200');
    await drain(tester);
  });

  testWidgets(
      'toggle Jenis Rupiah/Persen mengubah label & hasil perhitungan',
      (tester) async {
    await seedProduct(
        id: 'p1', name: 'Gula 1kg', basePrice: 10000, costPrice: 7000);
    await db.addPriceCategory('Grosir');

    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());
    await tester.tap(find.text('Grosir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gula 1kg'));
    await tester.pumpAndSettle();

    // Default Jenis = Persen — pastikan itu prakondisinya, lalu ganti ke
    // Rupiah dulu: isi margin 2000 -> harga jual 12000 (10000 + 2000).
    var marginFieldFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Margin');
    var marginField = tester.widget<TextField>(marginFieldFinder);
    expect(marginField.decoration?.suffixText, '%',
        reason: 'prakondisi: default jenis margin adalah Persen');

    await tester.tap(find.text('Rupiah'));
    await tester.pump();
    marginFieldFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Margin');
    marginField = tester.widget<TextField>(marginFieldFinder);
    expect(marginField.decoration?.prefixText, 'Rp ');
    expect(marginField.decoration?.suffixText, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Margin'), '2000');
    await tester.pump();
    var sellFieldFinder = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'Harga Jual');
    var sellField = tester.widget<TextField>(sellFieldFinder);
    expect(sellField.controller!.text, '12000');

    // Ganti ke Persen — margin field yg sama (2000) sekarang berarti 2000%,
    // harga jual otomatis dihitung ulang mengikuti jenis baru.
    await tester.tap(find.text('Persen'));
    await tester.pump();
    sellFieldFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Harga Jual');
    sellField = tester.widget<TextField>(sellFieldFinder);
    expect(sellField.controller!.text, '210000'); // 10000 * (1+2000/100)

    // Suffix % harus tampil lagi di field Margin saat jenis Persen aktif.
    marginFieldFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Margin');
    marginField = tester.widget<TextField>(marginFieldFinder);
    expect(marginField.decoration?.suffixText, '%');
    expect(marginField.decoration?.prefixText, isNull);
    await drain(tester);
  });

  testWidgets('keluarkan produk dari kategori -> baris AltPrice terhapus',
      (tester) async {
    final unitId = await seedProduct(
        id: 'p1', name: 'Beras 5kg', basePrice: 10000, costPrice: 7000);
    final catId = await db.addPriceCategory('Grosir');
    await db.setPriceCategoryMargin(
      priceCategoryId: catId,
      productUnitId: unitId,
      categoryName: 'Grosir',
      marginAnchor: 'dasar',
      marginType: 'percent',
      marginValue: 20,
      computedPrice: 12000,
    );

    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());
    await tester.tap(find.text('Grosir'));
    await tester.pumpAndSettle();

    expect(find.text('Beras 5kg · Kg'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Keluarkan'));
    await tester.pumpAndSettle();

    expect(find.text('Beras 5kg · Kg'), findsNothing);
    final alts = await db.getAltPrices(unitId);
    expect(alts, isEmpty);
    await drain(tester);
  });
}
