import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/csv_import_service.dart';

/// Test Tier 1 (DB murni) untuk bug dedup importer CSV — kunci dedup lama
/// cuma nama+satuan, jadi dua SKU BERBEDA (barcode beda) dengan nama+satuan
/// sama persis dibuang diam-diam sebagai "duplikat". Kasus nyata ditemukan
/// di dataset user: "Sedap Goreng" satuan Dos dari 2 barcode berbeda.
void main() {
  test(
      'baris CSV dengan nama+satuan sama TAPI barcode beda TIDAK dianggap '
      'duplikat (SKU berbeda harus tetap masuk keduanya)', () async {
    final db = AppDatabase(NativeDatabase.memory());

    const csv = 'nama,satuan,harga_jual,harga_beli,barcode\n'
        'Sedap Goreng,Dos,113000,108500,11060048\n'
        'Sedap Goreng,Dos,111000,108500,25588880\n';

    final result = await CsvImportService.importFromBytes(
      bytes: csv.codeUnits,
      db: db,
    );

    expect(result.duplicates, 0,
        reason: 'dua baris ini SKU berbeda (barcode beda), bukan duplikat');
    expect(result.imported, 2,
        reason: 'kedua baris harus masuk sebagai produk terpisah');

    await db.close();
  });

  test(
      'baris CSV nama+satuan sama TANPA barcode/kode sama sekali tetap '
      'dianggap duplikat (fallback, tidak ada identitas SKU lain)',
      () async {
    final db = AppDatabase(NativeDatabase.memory());

    const csv = 'nama,satuan,harga_jual,harga_beli\n'
        'Barang Tanpa Identitas,Pcs,10000,8000\n'
        'Barang Tanpa Identitas,Pcs,10000,8000\n';

    final result = await CsvImportService.importFromBytes(
      bytes: csv.codeUnits,
      db: db,
    );

    expect(result.duplicates, 1);
    expect(result.imported, 1);

    await db.close();
  });
}
