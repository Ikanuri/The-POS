import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/kategori_harga_screen.dart';

import 'helpers/pump_app.dart';

/// Bug dilaporkan user: layar "Tambah Produk" (Kategori Harga) memakai
/// `db.searchProducts` mentah2 (beda dari `watchProducts` katalog kasir yg
/// SUDAH filter `parentProductId.isNull()`) — varian (produk anak) ikut
/// lolos sbg baris `ListTile` TERPISAH, seolah produk berdiri sendiri.
///
/// Fix: varian di-nested-kan sbg dropdown inline di bawah baris induknya
/// (tap panah utk buka/tutup, mendorong konten di bawah — bukan popup),
/// sama pola dgn produk bervarian di halaman kasir (`_VariantDropdown` di
/// `kasir_screen.dart`).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  Future<void> seedParentWithVariant() async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'parent', name: 'Kaos Polos'));
    const parentUnitId = 'parent_u';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: parentUnitId, productId: 'parent', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'parent_tier', productUnitId: parentUnitId, price: 50000));

    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'variant1',
        name: 'Kaos Polos - Merah',
        parentProductId: const Value('parent')));
    const variantUnitId = 'variant1_u';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: variantUnitId,
        productId: 'variant1',
        isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'variant1_tier', productUnitId: variantUnitId, price: 55000));

    await db.addPriceCategory('Grosir');
  }

  testWidgets(
      'varian TIDAK muncul sbg baris list terpisah di hasil pencarian '
      '"Tambah Produk"', (tester) async {
    await seedParentWithVariant();

    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());
    await tester.tap(find.text('Grosir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Kaos Polos'), findsOneWidget,
        reason: 'produk induk tetap tampil sbg baris utama');
    expect(find.text('Kaos Polos - Merah'), findsNothing,
        reason: 'varian tidak boleh lagi tampil sbg baris list TERPISAH '
            'sebelum dropdown-nya dibuka');

    await drain(tester);
  });

  testWidgets(
      'ketuk panah baris induk -> varian tampil sbg nested dropdown inline',
      (tester) async {
    await seedParentWithVariant();

    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());
    await tester.tap(find.text('Grosir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.expand_more), findsOneWidget,
        reason: 'produk yang punya varian dapat tombol expand');

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.text('Kaos Polos - Merah'), findsOneWidget,
        reason: 'varian muncul sbg baris nested setelah dropdown dibuka');

    // Pilih varian -> lanjut ke sheet margin (ProdukPickerResult dipakai,
    // membuktikan varian bisa dipilih spt produk biasa).
    await tester.tap(find.text('Kaos Polos - Merah'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Kaos Polos - Merah'), findsWidgets,
        reason: 'setelah varian dipilih, sheet margin/dialog berikutnya '
            'tetap merujuk varian yang dipilih (bukan induk)');

    await drain(tester);
  });

  testWidgets('produk tanpa varian TIDAK dapat tombol expand',
      (tester) async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'solo', name: 'Gula 1kg'));
    const unitId = 'solo_u';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId, productId: 'solo', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 'solo_tier', productUnitId: unitId, price: 12000));
    await db.addPriceCategory('Grosir');

    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());
    await tester.tap(find.text('Grosir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Gula 1kg'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing,
        reason: 'produk tanpa varian tidak perlu tombol expand sama sekali');

    await drain(tester);
  });
}
