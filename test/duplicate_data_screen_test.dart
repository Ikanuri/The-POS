import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/duplicate_data_screen.dart';

import 'helpers/pump_app.dart';

/// Layar "Cek Duplikat Data" (Pengaturan > Diagnostik) — dibuat menyusul
/// laporan user (produk "Amplop" punya 2 barcode Primer akibat restore
/// backup dari device yang datanya basi, lihat
/// `master_data_duplicate_detection_test.dart` utk detail akar masalah).
void main() {
  late AppDatabase db;

  tearDown(() async => db.close());

  testWidgets('database bersih -> tampil pesan "tidak ditemukan"',
      (tester) async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Kopi'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
        id: 'bc1',
        productUnitId: 'u1',
        barcode: '1110000000000',
        isPrimary: const Value(true)));

    await pumpWithFakeApp(tester, db: db, child: const DuplicateDataScreen());

    expect(find.textContaining('Tidak ditemukan'), findsOneWidget);
  });

  testWidgets(
      'produk dgn 2 barcode Primer -> muncul di daftar dgn nama produk & '
      'keterangan jumlah', (tester) async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Amplop'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
        id: 'bc1',
        productUnitId: 'u1',
        barcode: '68888602',
        isPrimary: const Value(true)));
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
        id: 'bc2',
        productUnitId: 'u1',
        barcode: '09130982',
        isPrimary: const Value(true)));

    await pumpWithFakeApp(tester, db: db, child: const DuplicateDataScreen());

    expect(find.text('Amplop'), findsOneWidget);
    expect(find.textContaining('2 barcode'), findsOneWidget);
  });
}
