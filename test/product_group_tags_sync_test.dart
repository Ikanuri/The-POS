import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 54 — `product_group_tags` (kategori tambahan) ikut tersinkron host→
/// klien SELALU full-dump (sama seperti `customer_groups`, lihat `dumpSince`),
/// TERMASUK saat tag dihapus (untag) di owner — baris yang tidak lagi ada di
/// payload WAJIB ikut dihapus di klien juga (bukan cuma diam menumpuk),
/// beda dari tabel master lain yang isinya cuma bertambah/berganti.
void main() {
  late AppDatabase host;
  late AppDatabase client;

  setUp(() async {
    host = AppDatabase(NativeDatabase.memory());
    client = AppDatabase(NativeDatabase.memory());

    Future<void> seedBoth(AppDatabase db) async {
      await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
          id: const Value(1), name: const Value('Minuman')));
      await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
          id: const Value(2), name: const Value('Snack')));
      await db.saveProduct(
        product: ProductsCompanion.insert(
            id: 'p1', name: 'Teh Botol', productGroupId: const Value(2)),
        units: [
          ProductUnitsCompanion.insert(
              id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
        ],
        tiersByUnitTempId: {
          'u1': [
            PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000),
          ],
        },
        barcodesByUnitTempId: const {},
        altPricesByUnitTempId: const {},
      );
    }

    // Host & klien mulai dari state identik (produk+kategori sama), spt
    // hasil sync awal — persis skenario nyata "sudah pernah sync sebelumnya".
    await seedBoth(host);
    await seedBoth(client);
  });

  tearDown(() async {
    await host.close();
    await client.close();
  });

  Future<void> syncHostToClient() async {
    final dump = await host.dumpSince(DateTime.fromMillisecondsSinceEpoch(0));
    for (final entry in dump.entries) {
      final isAppendOnly = const {
        'transactions',
        'transaction_items',
        'transaction_payments',
        'stock_ledger',
        'loyalty_point_ledger',
        'expenses',
      }.contains(entry.key);
      await client.mergeRows(entry.key, entry.value, isAppendOnly);
    }
  }

  test('tag kategori tambahan yang dibuat di host ikut tersinkron ke klien',
      () async {
    await host.setProductGroupMembership('p1', 1, true); // tag tambahan
    await syncHostToClient();

    final tags = await client.getProductGroupTagsFor(['p1']);
    expect(tags['p1'], {1});
  });

  test(
      'tag yang di-UNTAG di host ikut terhapus di klien saat sync berikutnya '
      '(bukan cuma diam menumpuk selamanya)', () async {
    await host.setProductGroupMembership('p1', 1, true);
    await syncHostToClient();
    expect((await client.getProductGroupTagsFor(['p1']))['p1'], {1});

    // Owner batalkan tag di host.
    await host.setProductGroupMembership('p1', 1, false);
    await syncHostToClient();

    expect(await client.getProductGroupTagsFor(['p1']), isEmpty,
        reason: 'baris yg sudah tidak ada di dump host wajib ikut dihapus '
            'di klien, bukan menetap dari sync sebelumnya');
  });
}
