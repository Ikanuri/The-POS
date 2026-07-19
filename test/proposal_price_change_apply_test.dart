import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug dilaporkan user: usulan sync antar-role bisa MENAMBAH produk, tapi
/// usulan UBAH HARGA — walau di-approve — tidak mengubah harga owner, malah
/// harga asisten balik ke semula saat sync.
///
/// Akar: form meregenerasi id tier tiap simpan (`_uuid.v4()`), sedangkan
/// `applyProductProposals` cuma INSERT OR REPLACE (per-id) tanpa menghapus
/// tier LAMA milik owner → tier `min_qty=1` menumpuk (harga owner tak
/// berubah), lalu tier lama itu ikut ter-dump balik ke asisten (harga asisten
/// revert). Fix: replace penuh price_tiers/alt_prices per satuan yg di-approve.
void main() {
  Future<void> seedProduct(AppDatabase db,
      {required int price,
      required String tierId,
      bool locallyModified = false}) async {
    await db.saveProduct(
      product: ProductsCompanion.insert(
          id: 'P', name: 'Gula', locallyModified: Value(locallyModified)),
      units: [
        ProductUnitsCompanion.insert(
            id: 'U',
            productId: 'P',
            unitTypeId: const Value(1),
            isBaseUnit: const Value(true),
            ratioToBase: const Value(1.0)),
      ],
      tiersByUnitTempId: {
        'U': [
          PriceTiersCompanion.insert(
              id: tierId, productUnitId: 'U', price: price)
        ],
      },
      barcodesByUnitTempId: const {},
    );
  }

  test(
      'approve ubah harga: owner jadi harga baru TANPA tier duplikat, & sync '
      'balik tidak me-revert harga asisten', () async {
    final host = AppDatabase(NativeDatabase.memory());
    final asisten = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await host.close();
      await asisten.close();
    });

    // Mula-mula sama: tier 't1' harga 5000.
    await seedProduct(host, price: 5000, tierId: 't1');
    await seedProduct(asisten, price: 5000, tierId: 't1');

    // Asisten ubah harga → tier baru 't2' 7000 (id regenerasi), tandai usulan.
    await seedProduct(asisten, price: 7000, tierId: 't2', locallyModified: true);
    expect((await asisten.getPriceTiers('U')).single.price, 7000,
        reason: 'prasyarat: asisten sudah pakai harga terbaru 7000');

    // Owner terima usulan & approve.
    final proposal = await asisten.dumpLocalProposals();
    final applied = await host.applyProductProposals(proposal, {'P'});
    expect(applied, greaterThan(0));

    // Gejala #1: harga owner harus BERUBAH ke 7000, TANPA tier duplikat.
    final hostTiers = await host.getPriceTiers('U');
    expect(hostTiers.length, 1,
        reason: 'tier lama harus terhapus — tidak boleh menumpuk jadi 2');
    expect(hostTiers.single.price, 7000,
        reason: 'harga owner harus jadi 7000 setelah approve');

    // Gejala #2: sync master-data balik owner→asisten tidak boleh me-revert
    // harga asisten ke 5000. Tiru jalur nyata: dump price_tiers owner lalu
    // mergeRows di asisten (isAppendOnly=false utk master data).
    final dump = (await host.customSelect('SELECT * FROM price_tiers').get())
        .map((r) => r.data)
        .toList();
    await asisten.mergeRows('price_tiers', dump, false);

    final aTiers = await asisten.getPriceTiers('U');
    expect(aTiers.length, 1);
    expect(aTiers.single.price, 7000,
        reason: 'harga asisten TIDAK boleh balik ke 5000 setelah sync');
  });
}
