import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/csv_import_service.dart';

/// Test Tier 1 (DB murni) untuk import CSV format Griyo POS — data uji
/// diambil persis dari sampel export nyata user (Products.csv):
/// - Pemisah kolom `;` (bukan `,`), header "Produk"/"Kode Produk"/
///   "Grup Produk"/"Harga Jual"/"Harga Pokok" (bukan alias default kita).
/// - Kolom Satuan & Grup Produk berisi ID mentah (skema legacy Griyo),
///   bukan nama teks — harus dipetakan ke _kDefaultUnitTypes.
void main() {
  const griyoHeader =
      'Produk;Harga Pokok;Harga Jual;Stok;Grup Produk;Satuan;Barcode;Kode Produk;Non Stok\n';

  test('CSV Griyo (pemisah ";", header non-default) berhasil diimport utuh',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    const csv = '$griyoHeader'
        'Sedap Goreng;2700;2800;26;6;12;8998866200301;Biji;1\n'
        'Sedap Soto;2650;2750;104;6;12;8998866200325;Biji;1\n';

    final result =
        await CsvImportService.importFromBytes(bytes: csv.codeUnits, db: db);

    expect(result.errors, isEmpty, reason: result.errors.join('; '));
    expect(result.imported, 2);

    final products = await db.searchProducts('Sedap Goreng');
    expect(products, hasLength(1));
    final units = await db.getProductUnits(products.first.id);
    expect(units, hasLength(1));
    // Satuan="12" (ID mentah legacy) harus terpetakan ke unit type 12 = Biji.
    final unitTypes = await db.getAllUnitTypes();
    final biji = unitTypes.firstWhere((u) => u.id == 12);
    expect(units.first.unitTypeId, biji.id);
    expect(biji.name, 'Biji');

    // Grup="6" (ID mentah legacy) harus terpetakan langsung sebagai ID grup.
    expect(products.first.productGroupId, 6);

    final tiers = await db.getPriceTiers(units.first.id);
    expect(tiers.first.price, 2800);
    expect(tiers.first.costPrice, 2700);

    await db.close();
  });

  test('Satuan legacy ID 7/8 di-merge ke 12 (Biji), sesuai skema lama',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    const csv = '$griyoHeader'
        'Barang Legacy;1000;1500;0;;7;;BRG001;1\n';

    await CsvImportService.importFromBytes(bytes: csv.codeUnits, db: db);
    final products = await db.searchProducts('Barang Legacy');
    final units = await db.getProductUnits(products.first.id);
    expect(units.first.unitTypeId, 12);

    await db.close();
  });

  test(
      'baris nama sama, satuan beda (mis. "234 12" Slop & Pak) masuk sebagai '
      'produk terpisah dan terhitung di sameNameDifferentUnit', () async {
    final db = AppDatabase(NativeDatabase.memory());
    const csv = '$griyoHeader'
        '234 12;1;193000;0;4;9;8999909000605;2341 Slop;1\n'
        '234 12;0;19400;0;4;4;8999909028234;2341 Pak;1\n';

    final result =
        await CsvImportService.importFromBytes(bytes: csv.codeUnits, db: db);

    expect(result.imported, 2, reason: 'flat: tidak digabung otomatis');
    expect(result.sameNameDifferentUnit, 1,
        reason: 'baris kedua nama-nya sudah pernah muncul di baris pertama');

    final products = await db.searchProducts('234 12');
    expect(products, hasLength(2),
        reason: 'dua produk terpisah bernama sama, satuan beda');

    await db.close();
  });
}
