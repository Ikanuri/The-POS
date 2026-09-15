import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug nyata dilaporkan user: kategori BARU (dibuat lewat "Tambah Kategori")
/// tiba-tiba sudah punya anggota produk yang TIDAK PERNAH dicentang user
/// secara sadar. Akar masalah: `addProductGroup` dulu mendaur ulang baris
/// `product_groups` dgn `name IS NULL` PERTAMA yang ditemukan — termasuk
/// slot placeholder legacy id 3-20 (`_seedDefaults`, utk kompatibilitas CSV
/// Griyo POS yang pakai id kategori angka mentah) yang TIDAK DIJAMIN kosong
/// dari produk kalau CSV pernah menempelkan produk ke id itu sebelum diberi
/// nama (lihat `csv_import_service.dart`).
///
/// Fix: `addProductGroup` SELALU alokasikan id baru, jangan pernah daur
/// ulang baris manapun — kategori baru dijamin benar-benar kosong.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test(
      'kategori baru TIDAK boleh mewarisi produk yang sudah menempel ke '
      'slot legacy id 3-20 (mis. dari CSV import lama)', () async {
    // Simulasikan produk lama yang sudah menempel ke id kategori legacy
    // MENTAH (mis. id 5) SEBELUM slot itu pernah diberi nama -- persis
    // skenario CSV import legacy yang menaruh id angka mentah.
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p-legacy', name: 'Produk Lama', productGroupId: const Value(5)));

    // Owner sekarang bikin kategori baru pertama kalinya.
    await db.addProductGroup('Sembako');

    final sembako = (await db.getAllProductGroups())
        .firstWhere((g) => g.name == 'Sembako');
    // Sebelum fix: `addProductGroup` mengambil slot kosong PERTAMA (id 3),
    // BUKAN id 5 -- tapi kalau kebetulan slot yg diambil = id yg sudah
    // ditempeli produk lama, produk itu akan langsung "muncul" jadi
    // anggota. Uji generik: kategori baru manapun TIDAK BOLEH kebetulan
    // memakai id yang sudah ditempeli produk manapun.
    final members = await db.countProductsInGroup(sembako.id);
    expect(members, 0,
        reason: 'kategori baru harus benar-benar kosong, tidak boleh '
            'kebetulan mewarisi produk dari id lama yang didaur ulang');

    await db.close();
  });

  test('id kategori baru SELALU id baru (tidak pernah id lama yang didaur '
      'ulang), walau ada banyak slot kosong tersisa', () async {
    // 18 slot kosong (id 3-20) sudah ada sejak _seedDefaults -- tanpa fix,
    // addProductGroup akan mengambil salah satu dari sini.
    await db.addProductGroup('Sembako');
    await db.addProductGroup('Minuman');
    await db.addProductGroup('Snack');

    final groups = await db.getAllProductGroups();
    final ids = groups.map((g) => g.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'id tidak boleh dobel');
    // Id baru harus > 20 (di luar rentang slot legacy 3-20) -- membuktikan
    // TIDAK ADA daur ulang slot lama sama sekali.
    for (final g in groups) {
      expect(g.id, greaterThan(20),
          reason:
              'kategori baru harus dapat id baru, bukan daur ulang slot '
              'legacy 3-20 (id ${g.id} utk "${g.name}")');
    }

    await db.close();
  });

  test(
      'kategori yang sudah DIHAPUS dgn benar (deleteProductGroup, membership '
      'sudah dibersihkan) tetap TIDAK didaur ulang -- id baru selalu dipakai',
      () async {
    await db.addProductGroup('Sembako');
    final sembako =
        (await db.getAllProductGroups()).firstWhere((g) => g.name == 'Sembako');
    await db.deleteProductGroup(sembako.id);

    await db.addProductGroup('Minuman');
    final minuman =
        (await db.getAllProductGroups()).firstWhere((g) => g.name == 'Minuman');

    expect(minuman.id, isNot(sembako.id),
        reason: 'walau slot lama sudah bersih, tetap harus dapat id baru '
            '(konsisten, tidak ada pengecualian daur ulang)');

    await db.close();
  });
}
