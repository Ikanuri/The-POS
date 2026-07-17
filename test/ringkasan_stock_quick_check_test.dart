import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/ringkasan/ringkasan_screen.dart';

import 'helpers/pump_app.dart';

/// Item 30(a) — kartu cek cepat stok di Ringkasan Harian: hitung "N stok
/// menipis, M habis" dari stok riil & tampilkan preview tertipis dulu.
void main() {
  Future<String> addProduct(
    AppDatabase db,
    String name, {
    int? minStock,
  }) async {
    final id = 'p-$name';
    final unitId = '$id-u';
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: id, name: name));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: id,
          isBaseUnit: const Value(true),
          minStock: Value(minStock),
        ));
    return unitId;
  }

  testWidgets('kartu tampilkan ringkasan menipis/habis & baris tertipis '
      'lebih dulu', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final uHabis = await addProduct(db, 'Gula Habis');
    final uMenipis = await addProduct(db, 'Beras Menipis', minStock: 10);
    final uAman = await addProduct(db, 'Minyak Aman', minStock: 5);
    await db.adjustStock(productUnitId: uHabis, newQty: 0);
    await db.adjustStock(productUnitId: uMenipis, newQty: 3);
    await db.adjustStock(productUnitId: uAman, newQty: 50);

    await pumpWithFakeApp(
        tester, db: db, child: const RingkasanScreen());

    expect(find.textContaining('1 produk stok menipis, 1 habis'),
        findsOneWidget);
    // Tertipis dulu: Gula Habis (0) sebelum Beras Menipis (3).
    final gulaCenter = tester.getCenter(find.text('Gula Habis'));
    final berasCenter = tester.getCenter(find.text('Beras Menipis'));
    expect(gulaCenter.dy, lessThan(berasCenter.dy));

    await db.close();
  });
}
