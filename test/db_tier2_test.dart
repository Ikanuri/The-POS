import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/price_service.dart';

void main() {
  group('PriceService.resolvePrice', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('tanpa tier sama sekali → price 0, source none', () async {
      final resolved =
          await PriceService(db).resolvePrice(productUnitId: 'U-none', qty: 1);
      expect(resolved.price, 0);
      expect(resolved.source, PriceSource.none);
    });

    test('satu tier minQty=1 → source base (bukan qtyTier)', () async {
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: 't1',
            productUnitId: 'U1',
            minQty: const Value(1),
            price: 5000,
            costPrice: const Value(3000),
          ));
      final resolved =
          await PriceService(db).resolvePrice(productUnitId: 'U1', qty: 1);
      expect(resolved.price, 5000);
      expect(resolved.costPrice, 3000);
      expect(resolved.source, PriceSource.base);
    });

    test('qty tepat di batas tier grosir → tier grosir menang (bukan tier di atasnya)',
        () async {
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: 't1', productUnitId: 'U1', minQty: const Value(1), price: 5000));
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: 't2', productUnitId: 'U1', minQty: const Value(5), price: 4500));
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: 't3', productUnitId: 'U1', minQty: const Value(10), price: 4000));

      final atFive =
          await PriceService(db).resolvePrice(productUnitId: 'U1', qty: 5);
      expect(atFive.price, 4500, reason: 'qty==minQty tier grosir harus dapat harga grosir');
      expect(atFive.source, PriceSource.qtyTier);

      final atSeven =
          await PriceService(db).resolvePrice(productUnitId: 'U1', qty: 7);
      expect(atSeven.price, 4500, reason: 'tier terbesar yang <= qty (5), bukan (10)');

      final atTwelve =
          await PriceService(db).resolvePrice(productUnitId: 'U1', qty: 12);
      expect(atTwelve.price, 4000);
    });

    test('qty di bawah semua tier (mis. 0.5 pcs) → pakai tier terkecil', () async {
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: 't1', productUnitId: 'U1', minQty: const Value(1), price: 5000));
      final resolved =
          await PriceService(db).resolvePrice(productUnitId: 'U1', qty: 0.5);
      expect(resolved.price, 5000);
      expect(resolved.source, PriceSource.base);
    });

    test('harga group pelanggan mengalahkan semua tier qty', () async {
      await db.into(db.customerGroups).insert(CustomerGroupsCompanion.insert(
            id: 'g1', name: 'Grosir Langganan'));
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: 't1', productUnitId: 'U1', minQty: const Value(1), price: 5000));
      await db.into(db.customerGroupPrices).insert(CustomerGroupPricesCompanion.insert(
            id: 'gp1', productUnitId: 'U1', customerGroupId: 'g1', price: 3500));

      final resolved = await PriceService(db).resolvePrice(
          productUnitId: 'U1', qty: 1, customerGroupId: 'g1');
      expect(resolved.price, 3500);
      expect(resolved.source, PriceSource.customerGroup);
    });

    test('group pelanggan tanpa harga khusus untuk unit ini → jatuh ke tier biasa',
        () async {
      await db.into(db.customerGroups).insert(CustomerGroupsCompanion.insert(
            id: 'g1', name: 'Grosir Langganan'));
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: 't1', productUnitId: 'U1', minQty: const Value(1), price: 5000));
      // Tidak ada baris customer_group_prices untuk (U1, g1).

      final resolved = await PriceService(db).resolvePrice(
          productUnitId: 'U1', qty: 1, customerGroupId: 'g1');
      expect(resolved.price, 5000, reason: 'tanpa harga group khusus → tier normal');
      expect(resolved.source, PriceSource.base);
    });
  });

  group('mergeRows — master data (last-write-wins)', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Map<String, Object?> productRow(
            {required String id, required String name, required int updatedAt}) =>
        {
          'id': id,
          'name': name,
          'product_group_id': null,
          'kode_produk': null,
          'parent_product_id': null,
          'is_active': 1,
          'created_at': 1700000000,
          'updated_at': updatedAt,
        };

    test('baris masuk dengan updated_at LEBIH LAMA di-skip, data lokal menang',
        () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: 'p1',
            name: 'Nama Lokal (Terbaru)',
            updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(2000 * 1000)),
          ));

      final count = await db.mergeRows(
          'products', [productRow(id: 'p1', name: 'Nama Basi', updatedAt: 1000)], false);

      expect(count, 0, reason: 'tidak ada baris yang benar-benar ter-INSERT/REPLACE');
      final p = await (db.select(db.products)..where((t) => t.id.equals('p1'))).getSingle();
      expect(p.name, 'Nama Lokal (Terbaru)',
          reason: 'data lokal yang lebih baru tidak boleh tertimpa data basi dari sync');
    });

    test('baris masuk dengan updated_at LEBIH BARU menang, menimpa data lokal',
        () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: 'p1',
            name: 'Nama Lama',
            updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(1000 * 1000)),
          ));

      final count = await db.mergeRows(
          'products', [productRow(id: 'p1', name: 'Nama Baru', updatedAt: 2000)], false);

      expect(count, 1);
      final p = await (db.select(db.products)..where((t) => t.id.equals('p1'))).getSingle();
      expect(p.name, 'Nama Baru');
    });

    test('produk baru (id belum ada) langsung masuk terlepas dari updated_at',
        () async {
      final count = await db.mergeRows(
          'products', [productRow(id: 'p-new', name: 'Produk Baru', updatedAt: 1)], false);
      expect(count, 1);
      final p = await (db.select(db.products)..where((t) => t.id.equals('p-new'))).getSingle();
      expect(p.name, 'Produk Baru');
    });
  });

  group('mergeRows — price_tiers dedup', () {
    test('tier lama dengan (product_unit_id, min_qty) sama dihapus, tier masuk menang',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: 'old-tier', productUnitId: 'U1', minQty: const Value(1), price: 1000));

      final count = await db.mergeRows(
          'price_tiers',
          [
            {
              'id': 'new-tier',
              'product_unit_id': 'U1',
              'min_qty': 1,
              'price': 2000,
              'cost_price': 0,
              'created_at': 1700000000,
            }
          ],
          false);

      expect(count, 1);
      final tiers = await (db.select(db.priceTiers)
            ..where((t) => t.productUnitId.equals('U1') & t.minQty.equals(1)))
          .get();
      expect(tiers.length, 1,
          reason: 'tier lama harus dihapus agar tidak ada duplikat (unit, minQty) sama');
      expect(tiers.single.id, 'new-tier');
      expect(tiers.single.price, 2000);

      await db.close();
    });
  });

  group('restoreFromDump', () {
    test('data lama terhapus total, data dari dump tertanam persis', () async {
      final db = AppDatabase(NativeDatabase.memory());

      // Data lama yang HARUS lenyap setelah restore.
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: 'p-old', name: 'Produk Lama'));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx-old',
            localId: 'OLD-1',
            status: 'lunas',
            total: 1000,
            paid: 1000,
            changeAmount: 0,
            paymentMethod: 'tunai',
          ));

      final dump = <String, List<Map<String, Object?>>>{
        'products': [
          {
            'id': 'p-new',
            'name': 'Produk Dari Backup',
            'product_group_id': null,
            'kode_produk': null,
            'parent_product_id': null,
            'is_active': 1,
            'created_at': 1700000000,
            'updated_at': 1700000000,
          }
        ],
        'transactions': [
          {
            'id': 'tx-new',
            'local_id': 'K1-BACKUP-1',
            'kasir_id': null,
            'customer_id': null,
            'customer_name': null,
            'status': 'lunas',
            'total': 25000,
            'paid': 25000,
            'change_amount': 0,
            'payment_method': 'tunai',
            'internal_note': null,
            'struk_note': null,
            'employee_name': null,
            'points_earned': 0,
            'created_at': 1700000000,
            'synced_at': null,
          }
        ],
        // Tabel lain sengaja tidak disertakan → harus tetap kosong, tidak error.
      };

      await db.restoreFromDump(dump);

      final products = await db.select(db.products).get();
      expect(products.length, 1, reason: 'produk lama harus lenyap, hanya sisa dari dump');
      expect(products.single.id, 'p-new');
      expect(products.single.name, 'Produk Dari Backup');

      final txs = await db.select(db.transactions).get();
      expect(txs.length, 1);
      expect(txs.single.id, 'tx-new');
      expect(txs.single.total, 25000);

      await db.close();
    });

    test('baris kosong ({}) di dump dilewati tanpa error', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final dump = <String, List<Map<String, Object?>>>{
        'products': [<String, Object?>{}],
      };
      await db.restoreFromDump(dump); // tidak boleh throw
      expect(await db.select(db.products).get(), isEmpty);
      await db.close();
    });
  });

  group('generateUniqueLocalId', () {
    test('tanpa transaksi sebelumnya → dimulai dari 0001', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final id = await db.generateUniqueLocalId('K1', DateTime(2026, 7, 1));
      expect(id, 'K1-20260701-0001');
      await db.close();
    });

    test('ada celah nomor (retur berbagi ruang sequence dgn penjualan) → tidak boleh tabrakan',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      final at = DateTime(2026, 7, 1);
      // Simulasikan: sudah ada 0001 dan 0002, TAPI 0003 juga sudah dipakai
      // (mis. oleh nota retur yang berbagi ruang sequence) — hanya 3 baris
      // total, tapi nomor tertinggi yang terpakai adalah 0003, bukan 0002.
      // Heuristik naif "used.length+1" akan menghasilkan 0004 — kebetulan
      // benar di kasus ini, jadi kita buat gap yang benar-benar menjebak:
      for (final n in ['0001', '0002', '0004']) {
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx-$n',
              localId: 'K1-20260701-$n',
              status: 'lunas',
              total: 1000,
              paid: 1000,
              changeAmount: 0,
              paymentMethod: 'tunai',
            ));
      }
      // used.length == 3 → heuristik naif akan mencoba '0004' duluan, yang
      // TERNYATA sudah dipakai → while-loop wajib lanjut ke '0005'.
      final id = await db.generateUniqueLocalId('K1', at);
      expect(id, 'K1-20260701-0005',
          reason: 'candidate pertama (0004) sudah terpakai — loop harus lanjut, bukan tabrakan diam-diam');
      await db.close();
    });

    test('device code / tanggal berbeda tidak saling memengaruhi', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx1',
            localId: 'K1-20260701-0001',
            status: 'lunas',
            total: 1000,
            paid: 1000,
            changeAmount: 0,
            paymentMethod: 'tunai',
          ));

      final otherDevice =
          await db.generateUniqueLocalId('K2', DateTime(2026, 7, 1));
      expect(otherDevice, 'K2-20260701-0001');

      final otherDate = await db.generateUniqueLocalId('K1', DateTime(2026, 7, 2));
      expect(otherDate, 'K1-20260702-0001');

      await db.close();
    });
  });
}
