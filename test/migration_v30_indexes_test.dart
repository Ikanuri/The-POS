import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Audit efisiensi storage — indeks baru utk tabel yang sebelumnya belum
/// terindeks sama sekali (bisa jadi besar seiring katalog produk bertambah),
/// plus `transaction_id` di 3 tabel Laci Meja (dipakai guard baru
/// `TutupBukuService.execute`). Berlaku baik utk DB BARU (onCreate) maupun
/// upgrade dari versi lama.
void main() {
  Future<Set<String>> indexNames(AppDatabase db) async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
        .get();
    return rows.map((r) => r.data['name'] as String).toSet();
  }

  const expectedIndexes = {
    'idx_pu_product',
    'idx_pt_unit',
    'idx_ap_unit',
    'idx_pb_unit',
    'idx_lpl_customer',
    'idx_lbi_tx',
    'idx_bi_tx',
    'idx_pe_tx',
  };

  test('DB BARU (onCreate) langsung punya semua indeks v30', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final names = await indexNames(db);
    expect(names.intersection(expectedIndexes), expectedIndexes);
    await db.close();
  });
}
