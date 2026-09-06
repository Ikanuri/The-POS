import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/kategori_harga_screen.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user) — layar "Tambah Produk" di Kategori Harga
/// sebelumnya cuma menampilkan nama produk, tidak menampilkan kode produk
/// sama sekali — menyulitkan membedakan produk yang namanya mirip/sama.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  testWidgets(
      'layar Tambah Produk menampilkan kode produk (bukan cuma nama)',
      (tester) async {
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p1', name: 'Beras 5kg', kodeProduk: const Value('BRS-001')));
    const unitId = 'p1_u';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId, productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'p1_tier', productUnitId: unitId, price: 10000));
    final catId = await db.addPriceCategory('Grosir');

    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());
    await tester.tap(find.text('Grosir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Beras 5kg'), findsOneWidget);
    expect(find.text('Kode: BRS-001'), findsOneWidget);

    await drain(tester);
    // catId dipakai murni supaya analyzer tidak menandai unused-local -
    // kategori memang harus ada agar layar detailnya bisa dibuka di atas.
    expect(catId, isNotEmpty);
  });

  testWidgets(
      'produk TANPA kode produk -> baris tetap tampil tanpa subtitle kode',
      (tester) async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p2', name: 'Telur'));
    const unitId = 'p2_u';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId, productId: 'p2', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'p2_tier', productUnitId: unitId, price: 25000));
    await db.addPriceCategory('Grosir');

    await pumpWithFakeApp(tester, db: db, child: const KategoriHargaScreen());
    await tester.tap(find.text('Grosir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Telur'), findsOneWidget);
    expect(find.textContaining('Kode:'), findsNothing);

    await drain(tester);
  });
}
