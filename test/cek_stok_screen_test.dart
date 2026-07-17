import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/cek_stok_screen.dart';

import 'helpers/pump_app.dart';

/// Item 30(b) — layar "Cek Stok": centang HARUS (1) update markedOutOfStock
/// sungguhan di DB, DAN (2) muncul di panel teks order restock — bukan
/// checklist manual terpisah dari stok riil (poin user: "untuk apa ada
/// stok kalau akhirnya dicek manual juga").
void main() {
  Future<String> addProduct(AppDatabase db, String name) async {
    final id = 'p-$name';
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: id, name: name));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: '$id-u',
          productId: id,
          isBaseUnit: const Value(true),
        ));
    return id;
  }

  testWidgets(
      'centang baris → markedOutOfStock jadi true di DB & teks order '
      'restock muncul; uncentang → sebaliknya', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await addProduct(db, 'Gula Pasir');

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());

    expect(find.text('Gula Pasir'), findsOneWidget);
    expect(find.text('Teks Order Restock'), findsNothing,
        reason: 'panel belum muncul sebelum ada yg dicentang');

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    final product = await (db.select(db.products)
          ..where((t) => t.id.equals('p-Gula Pasir')))
        .getSingle();
    expect(product.markedOutOfStock, isTrue);
    expect(find.text('Teks Order Restock'), findsOneWidget);
    expect(find.textContaining('Gula Pasir'), findsWidgets);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    final productAfter = await (db.select(db.products)
          ..where((t) => t.id.equals('p-Gula Pasir')))
        .getSingle();
    expect(productAfter.markedOutOfStock, isFalse);
    expect(find.text('Teks Order Restock'), findsNothing);

    await db.close();
  });

  testWidgets('filter kategori: hanya produk kategori terpilih yang tampil',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(1), name: const Value('Sembako')));
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(2), name: const Value('Minuman')));
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'p-Beras',
          name: 'Beras',
          productGroupId: const Value(1),
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'p-Beras-u',
          productId: 'p-Beras',
          isBaseUnit: const Value(true),
        ));
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'p-Teh',
          name: 'Teh Botol',
          productGroupId: const Value(2),
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'p-Teh-u',
          productId: 'p-Teh',
          isBaseUnit: const Value(true),
        ));

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());

    expect(find.text('Beras'), findsOneWidget);
    expect(find.text('Teh Botol'), findsOneWidget);

    await tester.tap(find.text('Minuman'));
    await tester.pumpAndSettle();

    expect(find.text('Teh Botol'), findsOneWidget);
    expect(find.text('Beras'), findsNothing);

    await db.close();
  });
}
