import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/db_export_service.dart';

/// Item 50 (task manager 21 Juli) — ekspor katalog harga terenkripsi
/// (.berkahpos, magic BPRC1) utk toko yang tidak selalu satu WiFi saat
/// mau sinkron harga. Round-trip export→decrypt harus mengembalikan
/// item yang sama persis, dan file harus ditolak jika format/password
/// salah.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.batch((b) {
      b.insertAll(db.unitTypes,
          [UnitTypesCompanion.insert(id: const Value(102), name: 'Pak')]);
    });
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p_1', name: 'Garam Dapur'),
      units: [
        ProductUnitsCompanion.insert(
          id: 'u_1',
          productId: 'p_1',
          unitTypeId: const Value(102),
          isBaseUnit: const Value(true),
        ),
      ],
      tiersByUnitTempId: {
        'u_1': [
          PriceTiersCompanion.insert(id: 't_1', productUnitId: 'u_1', price: 3000),
        ],
      },
      barcodesByUnitTempId: {
        'u_1': [
          ProductBarcodesCompanion.insert(
              id: 'b_1',
              productUnitId: 'u_1',
              barcode: '8991234567890',
              isPrimary: const Value(true)),
        ],
      },
      altPricesByUnitTempId: const {},
    );
  });
  tearDown(() async => db.close());

  test('round-trip: ekspor lalu decrypt mengembalikan katalog yang sama',
      () async {
    final bytes = await DbExportService.exportPriceCatalog(
        db: db, password: 'rahasia123');

    final items = await DbExportService.decryptPriceCatalog(
        fileBytes: bytes, password: 'rahasia123');

    expect(items, hasLength(1));
    expect(items.single.productName, 'Garam Dapur');
    expect(items.single.barcode, '8991234567890');
    expect(items.single.price, 3000);
  });

  test('password salah ditolak dgn BackupException', () async {
    final bytes = await DbExportService.exportPriceCatalog(
        db: db, password: 'rahasia123');

    expect(
      () => DbExportService.decryptPriceCatalog(
          fileBytes: bytes, password: 'salah-password'),
      throwsA(isA<BackupException>()),
    );
  });

  test('file bukan format BPRC1 (mis. backup biasa) ditolak', () async {
    final backupBytes =
        await DbExportService.exportPortable(db: db, password: 'rahasia123');

    expect(
      () => DbExportService.decryptPriceCatalog(
          fileBytes: backupBytes, password: 'rahasia123'),
      throwsA(isA<BackupException>()),
    );
  });
}
