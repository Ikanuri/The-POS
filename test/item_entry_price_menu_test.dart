import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/widgets/item_entry_sheet.dart';

import 'helpers/pump_app.dart';

/// Item 19 REVISI (25 Juli, usulan user dari screenshot): dulu tier grosir +
/// Harga Lain milik satuan terpilih disembunyikan di balik SATU tombol
/// "Harga lain (N)" yang harus diketuk dulu utk buka popup menu. Sekarang
/// setiap opsi harga (termasuk "Harga dasar") langsung tampil sbg CHIP
/// sendiri-sendiri di baris "Pilih harga" — pola yang sama dgn "Pilih
/// satuan" di atasnya (widget `_PriceChip` yang sama, dipakai ulang) —
/// tanpa perlu buka apa pun dulu utk melihat opsinya.
void main() {
  late AppDatabase db;
  late Product product;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Kopi'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    // Harga dasar 5000.
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 'pt1', productUnitId: 'u1', price: 5000));
    // Harga Lain "Harga Grosir" 4000.
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'ap1',
        productUnitId: 'u1',
        label: 'Harga Grosir',
        price: 4000));
    product = (await db.searchProducts('')).first;
  });

  tearDown(() async => db.close());

  TextField priceField(WidgetTester tester) => tester.widget<TextField>(
        find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.prefixText == 'Rp '),
      );

  testWidgets(
      'chip "Harga dasar" & "Harga Grosir" langsung tampil TANPA perlu buka '
      'apa pun dulu; ketuk chip "Harga Grosir" mengisi field',
      (tester) async {
    await pumpWithFakeApp(tester, db: db, child: ItemEntrySheet(product: product));

    // Kedua opsi langsung terlihat sekaligus, bukan disembunyikan di balik
    // satu tombol "Harga lain (1)" yang mesti diketuk dulu.
    expect(find.text('Harga dasar'), findsOneWidget);
    expect(find.text('Harga Grosir'), findsOneWidget);
    expect(find.text('Harga lain'), findsNothing,
        reason: 'label tombol popup lama tidak boleh ada lagi');
    expect(priceField(tester).controller!.text, '5.000');

    await tester.tap(find.text('Harga Grosir'));
    await tester.pumpAndSettle();

    expect(priceField(tester).controller!.text, '4.000');
    // Chip yang baru dipilih masih terlihat (bukan menu yang tertutup).
    expect(find.text('Harga Grosir'), findsOneWidget);
    expect(find.text('Harga dasar'), findsOneWidget);
  });

  testWidgets(
      'ketuk chip "Harga dasar" setelah pilih Harga Grosir -> field kembali '
      'ke harga dasar', (tester) async {
    await pumpWithFakeApp(tester, db: db, child: ItemEntrySheet(product: product));

    await tester.tap(find.text('Harga Grosir'));
    await tester.pumpAndSettle();
    expect(priceField(tester).controller!.text, '4.000');

    await tester.tap(find.text('Harga dasar'));
    await tester.pumpAndSettle();
    expect(priceField(tester).controller!.text, '5.000');
  });

  testWidgets(
      'produk TANPA Harga Lain/tier grosir: baris "Pilih harga" tidak '
      'muncul sama sekali (cuma 1 opsi = harga dasar sendiri)',
      (tester) async {
    final db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db2.close());
    await db2.into(db2.products).insert(
        ProductsCompanion.insert(id: 'p2', name: 'Teh'));
    await db2.into(db2.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u2', productId: 'p2', isBaseUnit: const Value(true)));
    await db2.into(db2.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'pt2', productUnitId: 'u2', price: 3000));
    final teh = (await db2.searchProducts('')).first;

    await pumpWithFakeApp(tester, db: db2, child: ItemEntrySheet(product: teh));

    expect(find.text('Pilih harga'), findsNothing,
        reason: 'tanpa Harga Lain/tier grosir, baris pilih-harga tak perlu '
            'muncul (tidak ada apa pun utk dipilih selain harga dasar)');
  });
}
