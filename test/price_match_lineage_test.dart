import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/price_match_service.dart';
import 'package:the_pos/core/services/price_sync_service.dart';

/// Redesain sinkron harga induk-cabang (disepakati 21 Juli, task manager) —
/// fuzzy Levenshtein DIBUANG TOTAL. Test ini membuktikan tingkat kepercayaan
/// baru: (2) kode_produk/SKU warisan clone lama unik di KEDUA sisi menang
/// atas barcode 8-digit fabrikasi, TAPI mundur ke tinjauan manual kalau
/// KEDUA barcode sama-sama terlihat resmi & beda (anomali sungguhan);
/// (3) nama+satuan cocok PERSIS & unik → 1 kandidat, usulan; (4) nama cocok
/// ke banyak produk → kandidat ganda, user pilih sendiri (bukan ditebak via
/// skor kemiripan).
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.batch((b) {
      b.insertAll(db.unitTypes, [
        UnitTypesCompanion.insert(id: const Value(101), name: 'Slop'),
        UnitTypesCompanion.insert(id: const Value(102), name: 'Pak'),
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
    String? barcode,
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
      barcodesByUnitTempId: barcode == null
          ? const {}
          : {
              unitId: [
                ProductBarcodesCompanion.insert(
                  id: 'bc_$unitId',
                  productUnitId: unitId,
                  barcode: barcode,
                  isPrimary: const Value(true),
                ),
              ],
            },
      altPricesByUnitTempId: const {},
    );
  }

  group('Tingkat 2 — kode_produk (SKU) lineage warisan clone lama', () {
    test(
        'kode sama & unik di kedua sisi, barcode lokal 8-digit (fabrikasi) '
        'BEDA dari katalog → tetap auto-match via SKU (bukan anomali)',
        () async {
      await seedProduct(
        id: 'p_korek',
        name: 'Korek 2000',
        kode: 'krk2 biji',
        unitTypeId: 101,
        unitId: 'u_korek',
        price: 96000,
        barcode: '09842137', // 8 digit — fabrikasi, bukan barcode pabrik.
      );

      final result = await PriceMatchService.match(
        db: db,
        catalog: const [
          PriceCatalogItem(
            productName: 'Korek 2000',
            kodeProduk: 'krk2 biji',
            barcode: '25838282', // 8 digit juga, BEDA — fabrikasi toko lain.
            unitTypeName: 'Slop',
            price: 98000,
            costPrice: 0,
          ),
        ],
      );

      expect(result.matched, hasLength(1));
      expect(result.matched.first.matchType, MatchType.sku);
      expect(result.matched.first.linkBarcode, '25838282',
          reason: 'barcode katalog harus ditulis sbg alias permanen saat '
              'diterapkan, supaya sync berikutnya lompat ke Tingkat 1');
      expect(result.ambiguous, isEmpty);
    });

    test(
        'kode sama & unik, TAPI kedua barcode sama-sama 13-digit (terlihat '
        'resmi) & beda → anomali sungguhan, JATUH ke tinjauan manual',
        () async {
      await seedProduct(
        id: 'p_anomali',
        name: 'Produk Anomali',
        kode: 'anm1',
        unitTypeId: 102,
        unitId: 'u_anm',
        price: 10000,
        barcode: '8991906101767', // 13 digit, terlihat resmi.
      );

      final result = await PriceMatchService.match(
        db: db,
        catalog: const [
          PriceCatalogItem(
            productName: 'Produk Anomali',
            kodeProduk: 'anm1',
            barcode: '8991906101768', // 13 digit juga, terlihat resmi, BEDA.
            unitTypeName: 'Pak',
            price: 11000,
            costPrice: 0,
          ),
        ],
      );

      expect(result.matched, isEmpty,
          reason: 'JANGAN auto-match — dua barcode resmi berbeda adalah '
              'anomali sungguhan');
      expect(result.ambiguous, hasLength(1));
      expect(result.ambiguous.first.reason, AmbiguousReason.kodeConflict);
      expect(result.ambiguous.first.candidates.single.productName,
          'Produk Anomali');
    });

    test('kode_produk TIDAK unik di KATALOG MASUK (dipakai >1 baris) → '
        'tidak dipercaya sbg SKU, jatuh ke pencocokan nama', () async {
      await seedProduct(
        id: 'p_x',
        name: 'Barang X',
        kode: 'dos',
        unitTypeId: 102,
        unitId: 'u_x',
        price: 5000,
      );

      final result = await PriceMatchService.match(
        db: db,
        catalog: const [
          PriceCatalogItem(
            productName: 'Barang X',
            kodeProduk: 'dos', // dipakai 2x di katalog masuk → tak dipercaya.
            barcode: null,
            unitTypeName: 'Pak',
            price: 6000,
            costPrice: 0,
          ),
          PriceCatalogItem(
            productName: 'Barang Y',
            kodeProduk: 'dos',
            barcode: null,
            unitTypeName: 'Pak',
            price: 7000,
            costPrice: 0,
          ),
        ],
      );

      expect(result.matched, isEmpty,
          reason: 'kode "dos" dipakai 2 baris di katalog → tidak boleh '
              'jadi dasar auto-match SKU');
      // "Barang X" tetap terselamatkan lewat nama persis (Tingkat 3).
      expect(
          result.ambiguous
              .expand((a) => a.candidates)
              .map((c) => c.productName),
          contains('Barang X'));
    });
  });

  group('Tingkat 3/4 — nama+satuan persis (BUKAN fuzzy)', () {
    test('nama cocok persis ke SATU produk lokal → 1 kandidat, usulan '
        '(nameUniqueCandidate)', () async {
      await seedProduct(
        id: 'p_234',
        name: '234 16',
        kode: null,
        unitTypeId: 102,
        unitId: 'u_234',
        price: 25000,
      );

      final result = await PriceMatchService.match(
        db: db,
        catalog: const [
          PriceCatalogItem(
            productName: '234 16',
            kodeProduk: null,
            barcode: null,
            unitTypeName: 'Pak',
            price: 25500,
            costPrice: 0,
          ),
        ],
      );

      expect(result.matched, isEmpty);
      expect(result.ambiguous, hasLength(1));
      expect(result.ambiguous.first.reason,
          AmbiguousReason.nameUniqueCandidate);
      expect(result.ambiguous.first.candidates, hasLength(1));
    });

    test(
        'nama mirip TAPI TIDAK persis (mis. beda ukuran/varian) → TIDAK '
        'dianggap kandidat sama sekali (beda dari fuzzy lama)', () async {
      await seedProduct(
        id: 'p_uk12',
        name: 'cup pop ice uk 12',
        kode: null,
        unitTypeId: 102,
        unitId: 'u_uk12',
        price: 10000,
      );
      await seedProduct(
        id: 'p_uk18',
        name: 'cup pop ice uk 18',
        kode: null,
        unitTypeId: 102,
        unitId: 'u_uk18',
        price: 12000,
      );

      final result = await PriceMatchService.match(
        db: db,
        catalog: const [
          PriceCatalogItem(
            productName: 'cup pop ice uk 16', // TIDAK ada lokal persis ini.
            kodeProduk: null,
            barcode: null,
            unitTypeName: 'Pak',
            price: 11000,
            costPrice: 0,
          ),
        ],
      );

      expect(result.matched, isEmpty);
      expect(result.ambiguous, isEmpty,
          reason: 'dulu fuzzy akan menembak uk 12/18 sbg "mirip" — sekarang '
              'TIDAK ADA kandidat sama sekali krn nama tidak persis sama');
      expect(result.notFound.map((c) => c.productName),
          contains('cup pop ice uk 16'));
    });

    test('nama cocok persis ke LEBIH DARI SATU produk lokal (nama duplikat, '
        'mis. varian beda induk) → kandidat ganda, user pilih sendiri',
        () async {
      await seedProduct(
        id: 'p_dup1',
        name: 'Barang Kembar',
        kode: null,
        unitTypeId: 102,
        unitId: 'u_dup1',
        price: 8000,
      );
      await seedProduct(
        id: 'p_dup2',
        name: 'Barang Kembar',
        kode: null,
        unitTypeId: 102,
        unitId: 'u_dup2',
        price: 9500,
      );

      final result = await PriceMatchService.match(
        db: db,
        catalog: const [
          PriceCatalogItem(
            productName: 'Barang Kembar',
            kodeProduk: null,
            barcode: null,
            unitTypeName: 'Pak',
            price: 9000,
            costPrice: 0,
          ),
        ],
      );

      expect(result.matched, isEmpty);
      expect(result.ambiguous, hasLength(1));
      expect(result.ambiguous.first.reason,
          AmbiguousReason.nameMultipleCandidates);
      expect(result.ambiguous.first.candidates, hasLength(2),
          reason: 'kedua kandidat harus ditampilkan, TIDAK ada yang '
              'ditebak/dipilihkan otomatis via skor kemiripan');
    });
  });
}
