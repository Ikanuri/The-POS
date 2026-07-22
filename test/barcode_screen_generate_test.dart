import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/barcode_screen.dart';

import 'helpers/pump_app.dart';

/// Layar Barcode produk — Item 51 (22 Juli): "Generate Barcode" DIPINDAH
/// ke field Barcode di form Edit Produk (bukan lagi di layar ini, lihat
/// `produk_form_barcode_generate_test.dart`). Layar ini sekarang murni
/// utk mencetak label satuan yang SUDAH punya barcode (asli maupun hasil
/// generate) — satuan kosong cuma tampil pesan info, tanpa tombol aksi.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Telur'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', unitTypeId: const Value(1)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(
              id: 't1', productUnitId: 'u1', price: 25000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
  });
  tearDown(() => db.close());

  testWidgets(
      'satuan tanpa barcode menampilkan pesan info, TANPA tombol Generate '
      '(sudah dipindah ke form Edit Produk)', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const BarcodeScreen(productId: 'p1'));

    expect(
        find.textContaining('Belum ada barcode untuk satuan ini'),
        findsOneWidget);
    expect(find.text('Generate Barcode'), findsNothing);
    expect(find.text('Cetak Label'), findsNothing);
  });

  testWidgets(
      'satuan yang SUDAH punya barcode menampilkan tombol Cetak Label; '
      'tap tanpa printer diatur menampilkan pesan error, tidak crash',
      (tester) async {
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
          id: 'b1',
          productUnitId: 'u1',
          barcode: '2900000000015',
          isPrimary: const Value(true),
          isGenerated: const Value(true),
        ));

    await pumpWithFakeApp(tester,
        db: db, child: const BarcodeScreen(productId: 'p1'));

    expect(find.text('2900000000015'), findsOneWidget);
    expect(find.text('Cetak Label'), findsOneWidget);

    await tester.tap(find.text('Cetak Label'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Printer belum diatur'), findsOneWidget);
  });
}
