import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/price_match_service.dart';
import 'package:the_pos/core/services/price_sync_service.dart';

/// Item 35 — sinkron harga antar-toko: matching lewat SKU tidak boleh
/// menebak produk saat `kode_produk` tidak unik (kasus nyata dari log user:
/// banyak produk berkode nama satuan "Dos"/"Bal", bikin item nyasar ke
/// produk tak berhubungan & harga saling-timpa tiap sync / non-konvergen).
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Tipe satuan (id tinggi supaya tidak tabrakan dgn seed default 1-4):
    // 101=Dos, 102=Pak, 103=Pcs, 104=Bal.
    await db.batch((b) {
      b.insertAll(db.unitTypes, [
        UnitTypesCompanion.insert(id: const Value(101), name: 'Dos'),
        UnitTypesCompanion.insert(id: const Value(102), name: 'Pak'),
        UnitTypesCompanion.insert(id: const Value(103), name: 'Pcs'),
        UnitTypesCompanion.insert(id: const Value(104), name: 'Bal'),
      ]);
    });
  });
  tearDown(() async => db.close());

  Future<void> seedProduct({
    required String id,
    required String name,
    required String? kode,
    required int unitTypeId,
    required String unitId,
    required int price,
  }) async {
    await db.saveProduct(
      product: ProductsCompanion.insert(
        id: id,
        name: name,
        kodeProduk: Value(kode),
      ),
      units: [
        ProductUnitsCompanion.insert(
          id: unitId,
          productId: id,
          unitTypeId: Value(unitTypeId),
          isBaseUnit: const Value(true),
        ),
      ],
      tiersByUnitTempId: {
        unitId: [
          PriceTiersCompanion.insert(
              id: 't_$unitId', productUnitId: unitId, price: price),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
  }

  test('SKU tabrakan (kode "Dos" dimiliki 2 produk) TIDAK auto-match ke '
      'produk pertama yang salah', () async {
    // Dua produk berkode sama "Dos" — persis pola log user.
    await seedProduct(
        id: 'p_agar',
        name: 'Agar Satelit',
        kode: 'Dos',
        unitTypeId: 101,
        unitId: 'u_agar',
        price: 96000);
    await seedProduct(
        id: 'p_adem',
        name: 'Adem Sari Cingku',
        kode: 'Dos',
        unitTypeId: 101,
        unitId: 'u_adem',
        price: 7100);

    final result = await PriceMatchService.match(
      db: db,
      catalog: const [
        PriceCatalogItem(
          productName: 'Adem Sari Cingku',
          kodeProduk: 'Dos',
          barcode: null,
          unitTypeName: 'Dos',
          price: 168000,
          costPrice: 0,
        ),
      ],
    );

    // Yang PALING penting: TIDAK nyasar ke "Agar Satelit".
    final wrong = result.matched
        .where((m) => m.localProductName == 'Agar Satelit')
        .toList();
    expect(wrong, isEmpty,
        reason: 'SKU non-unik tidak boleh auto-match ke produk pertama');

    // Pencocokan nama-persis menyelamatkan ke produk yang BENAR (masuk tab
    // "Perlu Ditinjau", butuh konfirmasi manual — bukan auto-apply).
    expect(result.matched, isEmpty);
    expect(
        result.ambiguous
            .expand((a) => a.candidates)
            .map((c) => c.productName),
        contains('Adem Sari Cingku'));
  });

  test('SKU unik tapi satuan tidak ada di produk itu → ditolak (bukan '
      'nempel ke base unit yang salah)', () async {
    // "Atira 2000" berkode "bal" TAPI satuannya "Pcs", bukan "Bal".
    await seedProduct(
        id: 'p_atira',
        name: 'Atira 2000',
        kode: 'bal',
        unitTypeId: 103, // Pcs
        unitId: 'u_atira',
        price: 29000);

    final result = await PriceMatchService.match(
      db: db,
      catalog: const [
        PriceCatalogItem(
          productName: '76 12',
          kodeProduk: 'bal',
          barcode: null,
          unitTypeName: 'Bal',
          price: 3085000,
          costPrice: 0,
        ),
      ],
    );

    expect(result.matched.where((m) => m.localProductName == 'Atira 2000'),
        isEmpty,
        reason: 'satuan "Bal" tidak ada di Atira 2000 → SKU match tidak valid');
    // Tak ada produk lokal bernama mirip "76 12" → jatuh ke notFound.
    expect(result.notFound.map((c) => c.productName), contains('76 12'));
  });

  test('kontrol positif: SKU unik + satuan cocok TETAP match & deteksi '
      'perubahan harga', () async {
    await seedProduct(
        id: 'p_amp',
        name: 'Amplop Mini',
        kode: 'amp-mini',
        unitTypeId: 102, // Pak
        unitId: 'u_amp',
        price: 4000);

    final result = await PriceMatchService.match(
      db: db,
      catalog: const [
        PriceCatalogItem(
          productName: 'Amplop Mini',
          kodeProduk: 'amp-mini',
          barcode: null,
          unitTypeName: 'Pak',
          price: 5000,
          costPrice: 0,
        ),
      ],
    );

    expect(result.matched, hasLength(1));
    final m = result.matched.first;
    expect(m.localProductName, 'Amplop Mini');
    expect(m.matchType, MatchType.sku);
    expect(m.localPrice, 4000);
    expect(m.priceChanged, isTrue);
  });

  test('Item 35(opsional) — mode barcode-saja: item TANPA barcode langsung '
      'notFound, TIDAK dicoba lewat SKU walau kodenya unik & cocok',
      () async {
    await seedProduct(
        id: 'p_amp2',
        name: 'Amplop Mini',
        kode: 'amp-mini',
        unitTypeId: 102,
        unitId: 'u_amp2',
        price: 4000);

    final result = await PriceMatchService.match(
      db: db,
      barcodeOnly: true,
      catalog: const [
        PriceCatalogItem(
          productName: 'Amplop Mini',
          kodeProduk: 'amp-mini', // SKU unik & cocok, tapi HARUS diabaikan
          barcode: null,
          unitTypeName: 'Pak',
          price: 5000,
          costPrice: 0,
        ),
      ],
    );

    expect(result.matched, isEmpty);
    expect(result.ambiguous, isEmpty,
        reason: 'mode barcode-saja tidak boleh jatuh ke fuzzy sama sekali');
    expect(result.notFound.map((c) => c.productName), contains('Amplop Mini'));
  });

  test('Item 35(opsional) — mode barcode-saja: barcode cocok TETAP match '
      'normal', () async {
    await seedProduct(
        id: 'p_teh',
        name: 'Teh Celup',
        kode: null,
        unitTypeId: 102,
        unitId: 'u_teh',
        price: 8000);
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
          id: 'bc_teh',
          productUnitId: 'u_teh',
          barcode: '899123456',
          isPrimary: const Value(true),
        ));

    final result = await PriceMatchService.match(
      db: db,
      barcodeOnly: true,
      catalog: const [
        PriceCatalogItem(
          productName: 'Teh Celup',
          kodeProduk: null,
          barcode: '899123456',
          unitTypeName: 'Pak',
          price: 9000,
          costPrice: 0,
        ),
      ],
    );

    expect(result.matched, hasLength(1));
    expect(result.matched.first.matchType, MatchType.barcode);
    expect(result.matched.first.localProductName, 'Teh Celup');
  });
}
