import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/barcode_screen.dart';

import 'helpers/pump_app.dart';

/// Fitur "Generate Barcode" + "Cetak Label" di layar Barcode produk —
/// satuan yang belum punya barcode sama sekali menampilkan tombol
/// "Generate Barcode"; setelah digenerate, kartu berubah menampilkan
/// barcode baru + tombol "Cetak Label".
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
      'satuan tanpa barcode menampilkan tombol Generate; setelah tap, '
      'barcode baru tersimpan & tombol Cetak Label muncul', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const BarcodeScreen(productId: 'p1'));

    expect(find.text('Belum ada barcode untuk satuan ini.'), findsOneWidget);
    expect(find.text('Generate Barcode'), findsOneWidget);
    expect(find.text('Cetak Label'), findsNothing);

    await tester.tap(find.text('Generate Barcode'));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada barcode untuk satuan ini.'), findsNothing);
    expect(find.text('Cetak Label'), findsOneWidget);

    final barcodes = await db.getProductBarcodes('u1');
    expect(barcodes, hasLength(1));
    expect(barcodes.single.barcode.startsWith('29'), isTrue);
    expect(barcodes.single.isPrimary, isTrue);
    expect(barcodes.single.isGenerated, isTrue);
  });

  testWidgets(
      'tap Cetak Label tanpa printer diatur menampilkan pesan error, '
      'tidak crash', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const BarcodeScreen(productId: 'p1'));
    await tester.tap(find.text('Generate Barcode'));
    await tester.pumpAndSettle();

    // Drain SnackBar "Barcode dibuat: ..." dari langkah Generate — kalau
    // masih tampil, SnackBar berikutnya (Cetak Label) cuma DI-QUEUE oleh
    // ScaffoldMessenger (satu SnackBar tampil sekaligus), tidak langsung
    // dirender, sehingga assertion di bawah gagal-diam.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cetak Label'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Printer belum diatur'), findsOneWidget);
  });
}
