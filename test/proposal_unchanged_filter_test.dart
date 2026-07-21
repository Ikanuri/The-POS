import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Laporan nyata user: usulan harga/produk (Item 40) yang isinya SUDAH
/// SAMA dgn data owner tetap terus muncul lagi & lagi tiap sync, menumpuk
/// di layar review — padahal review screen SUDAH benar menampilkan "Tidak
/// ada perubahan harga" utk baris itu (logika bandingnya sudah benar),
/// masalahnya baris itu MASIH ADA di daftar sama sekali, tidak pernah
/// disaring keluar. Akar: flag `locally_modified` di device klien bisa
/// "macet" true (mis. form disimpan ulang tanpa perubahan nilai, timestamp
/// klien ikut maju & terus menang last-write-wins thd baris balikan host)
/// sehingga `dumpLocalProposals()` terus mengirim produk yang sama
/// walaupun isinya sudah identik. Fix: `AppDatabase.filterUnchangedProposals`
/// membandingkan payload usulan thd data LIVE host, buang produk yang
/// benar-benar tidak ada bedanya SEBELUM masuk antrian review.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> seedProduct({
    required String productId,
    required String unitId,
    required String name,
    required int price,
  }) async {
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: productId,
          name: name,
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: productId,
          isBaseUnit: const Value(true),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: '$unitId-tier1',
          productUnitId: unitId,
          price: price,
        ));
  }

  Map<String, List<Map<String, Object?>>> proposalFor({
    required String productId,
    required String unitId,
    required String name,
    required int price,
  }) {
    return {
      'products': [
        {
          'id': productId,
          'name': name,
          'product_group_id': null,
          'is_active': 1,
          'marked_out_of_stock': 0,
          'locally_modified': 1,
        }
      ],
      'product_units': [
        {
          'id': unitId,
          'product_id': productId,
          'unit_type_id': null,
          'is_base_unit': 1,
          'ratio_to_base': 1.0,
          'is_non_stock': 0,
          'min_stock': null,
        }
      ],
      'price_tiers': [
        {
          'id': '$unitId-tier-baru',
          'product_unit_id': unitId,
          'min_qty': 1,
          'price': price,
          'cost_price': 0,
        }
      ],
      'alt_prices': const [],
      'product_barcodes': const [],
    };
  }

  test('produk BARU (belum ada di DB owner) selalu lolos filter', () async {
    final proposal = proposalFor(
        productId: 'p-baru', unitId: 'u-baru', name: 'Produk Baru', price: 5000);
    final filtered = await db.filterUnchangedProposals(proposal);
    expect(filtered['products'], hasLength(1));
  });

  test(
      'produk existing dgn isi PERSIS SAMA (nama+satuan+tier) — DIBUANG dari '
      'usulan (tidak ada yg perlu direview)', () async {
    await seedProduct(
        productId: 'p1', unitId: 'u1', name: 'Gula Pasir', price: 15000);
    final proposal = proposalFor(
        productId: 'p1', unitId: 'u1', name: 'Gula Pasir', price: 15000);

    final filtered = await db.filterUnchangedProposals(proposal);

    expect(filtered['products'], isEmpty,
        reason: 'nama & harga persis sama dgn data owner — tidak perlu '
            'ditinjau ulang');
    expect(filtered['product_units'], isEmpty);
    expect(filtered['price_tiers'], isEmpty);
  });

  test(
      'produk existing dgn harga BEDA — TETAP lolos filter (genuinely perlu '
      'direview)', () async {
    await seedProduct(
        productId: 'p2', unitId: 'u2', name: 'Beras 5kg', price: 65000);
    final proposal = proposalFor(
        productId: 'p2', unitId: 'u2', name: 'Beras 5kg', price: 70000);

    final filtered = await db.filterUnchangedProposals(proposal);

    expect(filtered['products'], hasLength(1),
        reason: 'harga benar-benar beda — harus tetap diusulkan ke owner');
    expect(filtered['price_tiers']!.single['price'], 70000);
  });

  test(
      'campuran: 1 produk identik + 1 produk beda — HANYA yang beda ikut '
      'usulan, yang identik disaring keluar', () async {
    await seedProduct(
        productId: 'p-sama', unitId: 'u-sama', name: 'Teh Celup', price: 8000);
    await seedProduct(
        productId: 'p-beda', unitId: 'u-beda', name: 'Kopi Sachet', price: 2000);

    final samaProposal =
        proposalFor(productId: 'p-sama', unitId: 'u-sama', name: 'Teh Celup', price: 8000);
    final bedaProposal =
        proposalFor(productId: 'p-beda', unitId: 'u-beda', name: 'Kopi Sachet', price: 2500);

    final combined = {
      'products': [
        ...samaProposal['products']!,
        ...bedaProposal['products']!,
      ],
      'product_units': [
        ...samaProposal['product_units']!,
        ...bedaProposal['product_units']!,
      ],
      'price_tiers': [
        ...samaProposal['price_tiers']!,
        ...bedaProposal['price_tiers']!,
      ],
      'alt_prices': const <Map<String, Object?>>[],
      'product_barcodes': const <Map<String, Object?>>[],
    };

    final filtered = await db.filterUnchangedProposals(combined);

    expect(filtered['products']!.map((p) => p['id']), ['p-beda']);
    expect(filtered['product_units']!.map((u) => u['id']), ['u-beda']);
  });

  test('nama produk BEDA (walau harga sama) — tetap lolos filter', () async {
    await seedProduct(
        productId: 'p3', unitId: 'u3', name: 'Minyak Goreng 1L', price: 18000);
    final proposal = proposalFor(
        productId: 'p3',
        unitId: 'u3',
        name: 'Minyak Goreng Sania 1L',
        price: 18000);

    final filtered = await db.filterUnchangedProposals(proposal);

    expect(filtered['products'], hasLength(1),
        reason: 'nama beda walau harga sama — tetap perubahan nyata');
  });
}
