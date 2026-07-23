import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

import 'helpers/pump_app.dart';

/// Item 54 — chip kategori tab Kasir: tampil sbg tombol kecil di bawah
/// topbar, single-select (union kategori utama + tag tambahan), tap ulang
/// chip yang sama = matikan filter ("Semua" implisit).
void main() {
  Future<String> seedProduct(AppDatabase db, String id, String name,
      {int? groupId}) async {
    await db.saveProduct(
      product: ProductsCompanion.insert(
          id: id, name: name, productGroupId: Value(groupId)),
      units: [
        ProductUnitsCompanion.insert(
            id: '${id}_u', productId: id, isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        '${id}_u': [
          PriceTiersCompanion.insert(
              id: '${id}_t', productUnitId: '${id}_u', price: 5000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    return id;
  }

  testWidgets(
      'tap chip kategori memfilter produk (union kategori utama + tag), '
      'tap ulang mematikan filter', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(1), name: const Value('Minuman')));
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(2), name: const Value('Snack')));

    await seedProduct(db, 'p1', 'Teh Botol', groupId: 1);
    await seedProduct(db, 'p2', 'Keripik', groupId: 2);
    // p3: kategori utama Snack, TAPI juga di-tag ke Minuman (tambahan) —
    // harus ikut muncul saat filter "Minuman" aktif (union, bukan primary-only).
    await seedProduct(db, 'p3', 'Es Krim', groupId: 2);
    await db.setProductGroupMembership('p3', 1, true);

    await pumpWithFakeApp(tester, db: db, child: const KasirScreen());
    await tester.pumpAndSettle();

    expect(find.text('Minuman'), findsOneWidget);
    expect(find.text('Snack'), findsOneWidget);
    // Semua produk tampil tanpa filter.
    expect(find.textContaining('Teh Botol'), findsOneWidget);
    expect(find.textContaining('Keripik'), findsOneWidget);
    expect(find.textContaining('Es Krim'), findsOneWidget);

    // Tap chip "Minuman" -> filter aktif: Teh Botol (utama) & Es Krim (tag)
    // tampil, Keripik (murni Snack) hilang.
    await tester.tap(find.text('Minuman'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Teh Botol'), findsOneWidget);
    expect(find.textContaining('Es Krim'), findsOneWidget,
        reason: 'tag tambahan (bukan kategori utama) harus ikut union filter');
    expect(find.textContaining('Keripik'), findsNothing);

    // Tap ulang chip yang sama -> filter mati, semua tampil lagi.
    await tester.tap(find.text('Minuman'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Teh Botol'), findsOneWidget);
    expect(find.textContaining('Keripik'), findsOneWidget);
    expect(find.textContaining('Es Krim'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
