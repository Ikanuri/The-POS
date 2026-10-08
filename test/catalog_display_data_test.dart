import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/catalog_display_service.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Data katalog HTML untuk halaman awal baru: query terlaris (DB nyata),
/// kategori terurut, pengumuman, escape aman `</script>`, & setting tampilan.
int _seq = 0;

Future<String> _addProduct(
  AppDatabase db, {
  required String name,
  int price = 10000,
  bool isActive = true,
  String? parentProductId,
  bool markedOutOfStock = false,
  int? groupId,
}) async {
  final id = 'p${_seq++}';
  final unitId = '$id-u';
  await db.into(db.products).insert(ProductsCompanion.insert(
        id: id,
        name: name,
        isActive: Value(isActive),
        parentProductId: Value(parentProductId),
        markedOutOfStock: Value(markedOutOfStock),
        productGroupId: Value(groupId),
      ));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId,
        productId: id,
        unitTypeId: const Value(2),
        isBaseUnit: const Value(true),
      ));
  await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: '$unitId-t1',
        productUnitId: unitId,
        minQty: const Value(1),
        price: price,
      ));
  return id;
}

/// Satu nota berisi baris (productId, qty).
Future<void> _sale(
  AppDatabase db,
  DateTime at,
  List<(String, double)> lines, {
  String status = 'lunas',
}) async {
  final txId = 't${_seq++}';
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: txId,
        localId: 'K-$txId',
        status: status,
        total: 1000,
        paid: 1000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt: Value(at),
      ));
  var n = 0;
  for (final l in lines) {
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: '$txId-${n++}',
          transactionId: txId,
          productId: l.$1,
          productUnitId: '${l.$1}-u',
          qty: l.$2,
          priceAtSale: 1000,
          originalPrice: 1000,
          subtotal: 1000,
        ));
  }
}

Map<String, dynamic> _data(String html) {
  final m = RegExp(r'^var DATA = (.+);$', multiLine: true).firstMatch(html);
  expect(m, isNotNull);
  return jsonDecode(m!.group(1)!) as Map<String, dynamic>;
}

void main() {
  final now = DateTime(2026, 10, 7, 12);
  final recent = now.subtract(const Duration(days: 2));

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('getTopSellingParentProducts', () {
    test('peringkat per JUMLAH NOTA (bukan qty), tie-break qty, lalu nama',
        () async {
      final a = await _addProduct(db, name: 'A Produk');
      final b = await _addProduct(db, name: 'B Produk');
      final c = await _addProduct(db, name: 'C Produk');
      // A: 1 nota qty 100; B: 2 nota qty 1+1; C: 2 nota qty 5+5.
      await _sale(db, recent, [(a, 100)]);
      await _sale(db, recent, [(b, 1)]);
      await _sale(db, recent, [(b, 1)]);
      await _sale(db, recent, [(c, 5)]);
      await _sale(db, recent, [(c, 5)]);
      final r = await db.getTopSellingParentProducts(
          now.subtract(const Duration(days: 30)), now);
      expect(r.map((e) => e.productId).toList(), [c, b, a]);
      expect(r.first.txCount, 2);
      expect(r.first.qty, 10);
    });

    test('dua baris produk sama dalam SATU nota dihitung 1 nota', () async {
      final a = await _addProduct(db, name: 'A');
      final b = await _addProduct(db, name: 'B');
      await _sale(db, recent, [(a, 1), (a, 2), (a, 3)]);
      await _sale(db, recent, [(b, 1)]);
      await _sale(db, recent, [(b, 1)]);
      final r = await db.getTopSellingParentProducts(
          now.subtract(const Duration(days: 30)), now);
      expect(r.map((e) => e.productId).toList(), [b, a]);
      expect(r.last.txCount, 1);
    });

    test('periode: nota di luar rentang tidak dihitung', () async {
      final a = await _addProduct(db, name: 'A');
      final b = await _addProduct(db, name: 'B');
      await _sale(db, now.subtract(const Duration(days: 60)), [(a, 1)]);
      await _sale(db, now.subtract(const Duration(days: 60)), [(a, 1)]);
      await _sale(db, recent, [(b, 1)]);
      final r7 = await db.getTopSellingParentProducts(
          now.subtract(const Duration(days: 7)), now);
      expect(r7.map((e) => e.productId).toList(), [b]);
      final r90 = await db.getTopSellingParentProducts(
          now.subtract(const Duration(days: 90)), now);
      expect(r90.map((e) => e.productId).toList(), [a, b]);
    });

    test('nota void dikecualikan; baris retur (qty negatif) tidak dihitung',
        () async {
      final a = await _addProduct(db, name: 'A');
      final b = await _addProduct(db, name: 'B');
      await _sale(db, recent, [(a, 1)], status: 'void');
      await _sale(db, recent, [(a, 1)], status: 'void');
      await _sale(db, recent, [(b, 1)]);
      await _sale(db, recent, [(a, -1)]); // retur
      final r = await db.getTopSellingParentProducts(
          now.subtract(const Duration(days: 30)), now);
      expect(r.map((e) => e.productId).toList(), [b]);
    });

    test('varian digabung ke produk INDUK-nya', () async {
      final parent = await _addProduct(db, name: 'Induk');
      final v1 = await _addProduct(db, name: 'Varian 1', parentProductId: parent);
      final v2 = await _addProduct(db, name: 'Varian 2', parentProductId: parent);
      final other = await _addProduct(db, name: 'Lain');
      await _sale(db, recent, [(v1, 1)]);
      await _sale(db, recent, [(v2, 1)]);
      await _sale(db, recent, [(v1, 1), (v2, 1)]); // satu nota, dua varian
      await _sale(db, recent, [(other, 1)]);
      await _sale(db, recent, [(other, 1)]);
      final r = await db.getTopSellingParentProducts(
          now.subtract(const Duration(days: 30)), now);
      expect(r.map((e) => e.productId).toList(), [parent, other]);
      expect(r.first.txCount, 3);
      expect(r.any((e) => e.productId == v1 || e.productId == v2), isFalse);
    });

    test('induk nonaktif / ditandai habis manual tidak muncul; batas N',
        () async {
      final off = await _addProduct(db, name: 'Off', isActive: false);
      final oos = await _addProduct(db, name: 'Habis', markedOutOfStock: true);
      final ids = <String>[];
      for (var i = 0; i < 5; i++) {
        ids.add(await _addProduct(db, name: 'P$i'));
      }
      await _sale(db, recent, [(off, 1), (oos, 1), ...ids.map((e) => (e, 1.0))]);
      final r = await db.getTopSellingParentProducts(
          now.subtract(const Duration(days: 30)), now);
      expect(r.length, 5);
      final r2 = await db.getTopSellingParentProducts(
          now.subtract(const Duration(days: 30)), now,
          limit: 3);
      expect(r2.length, 3);
    });

    test('tanpa data penjualan -> kosong', () async {
      await _addProduct(db, name: 'A');
      final r = await db.getTopSellingParentProducts(
          now.subtract(const Duration(days: 30)), now);
      expect(r, isEmpty);
    });
  });

  group('DATA katalog', () {
    test('topSellers: nama PERSIS sama dgn DATA.products, hanya yang ada di '
        'katalog & tidak habis, maks N, urut peringkat', () async {
      final a = await _addProduct(db, name: 'Minyak Goreng 2L');
      final b = await _addProduct(db, name: 'Beras Premium 5kg');
      final noPrice = await _addProduct(db, name: 'Tanpa Harga', price: 0);
      final oos = await _addProduct(db, name: 'Habis Manual');
      final c = await _addProduct(db, name: 'Gula Pasir 1kg');
      // Habis manual DITANDAI SETELAH laku -> tak boleh jadi saran.
      await (db.update(db.products)..where((t) => t.id.equals(oos)))
          .write(const ProductsCompanion(markedOutOfStock: Value(true)));
      await _sale(db, recent, [(a, 1), (noPrice, 1), (oos, 1), (b, 1)]);
      await _sale(db, recent, [(a, 1), (noPrice, 1), (oos, 1)]);
      await _sale(db, recent, [(a, 1), (c, 1)]);

      final html = (await OrderPageService.generateHtml(
              db: db,
              storeName: 'T',
              display: const CatalogDisplay(topCount: 3),
              now: now))
          .html;
      final d = _data(html);
      final top = (d['topSellers'] as List).cast<String>();
      expect(top, ['Minyak Goreng 2L', 'Beras Premium 5kg', 'Gula Pasir 1kg']);
      final names = (d['products'] as List).map((p) => p['name']).toSet();
      for (final n in top) {
        expect(names, contains(n), reason: 'nama saran harus persis ada');
      }
    });

    test('topSellers kosong tanpa penjualan', () async {
      await _addProduct(db, name: 'A');
      final d = _data((await OrderPageService.generateHtml(
              db: db, storeName: 'T', now: now))
          .html);
      expect(d['topSellers'], isEmpty);
    });

    test('kategori: urut jumlah produk terbanyak, seri abjad; tanpa kategori '
        'tidak masuk daftar', () async {
      await db.addProductGroup('Minuman');
      await db.addProductGroup('Sembako');
      await db.addProductGroup('Rokok');
      final gs = {for (final g in await db.getAllProductGroups()) g.name!: g.id};
      await _addProduct(db, name: 'a1', groupId: gs['Sembako']);
      await _addProduct(db, name: 'a2', groupId: gs['Sembako']);
      await _addProduct(db, name: 'a3', groupId: gs['Sembako']);
      await _addProduct(db, name: 'b1', groupId: gs['Rokok']);
      await _addProduct(db, name: 'c1', groupId: gs['Minuman']);
      await _addProduct(db, name: 'tanpa');
      final d = _data(
          (await OrderPageService.generateHtml(db: db, storeName: 'T')).html);
      expect(d['categories'], ['Sembako', 'Minuman', 'Rokok']);
      expect(d['showCategories'], isTrue);
    });

    test('showCategories mengikuti setting; default ON', () async {
      await _addProduct(db, name: 'A');
      expect(
          _data((await OrderPageService.generateHtml(db: db, storeName: 'T'))
              .html)['showCategories'],
          isTrue);
      await CatalogDisplayService.setShowCategories(db, false);
      expect(
          _data((await OrderPageService.generateHtml(db: db, storeName: 'T'))
              .html)['showCategories'],
          isFalse);
    });

    test('announcement: null saat nonaktif / kosong; ada saat ON + teks',
        () async {
      await _addProduct(db, name: 'A');
      Future<Object?> ann() async => _data(
          (await OrderPageService.generateHtml(db: db, storeName: 'T'))
              .html)['announcement'];
      expect(await ann(), isNull);
      await CatalogDisplayService.setAnnounceText(db, 'Besok libur');
      expect(await ann(), isNull, reason: 'toggle masih OFF');
      await CatalogDisplayService.setAnnounceEnabled(db, true);
      expect(await ann(), {'text': 'Besok libur', 'enabled': true});
      await CatalogDisplayService.setAnnounceText(db, '   ');
      expect(await ann(), isNull, reason: 'teks kosong = tanpa pengumuman');
    });

    test('announcement dipotong 280 karakter', () async {
      await _addProduct(db, name: 'A');
      await CatalogDisplayService.setAnnounceEnabled(db, true);
      await CatalogDisplayService.setAnnounceText(db, 'x' * 400);
      final d = _data(
          (await OrderPageService.generateHtml(db: db, storeName: 'T')).html);
      expect((d['announcement']['text'] as String).length, 280);
    });

    test('teks pengumuman & nama berisi </script> / <!-- aman di dalam <script>',
        () async {
      await _addProduct(db, name: 'Evil </script><script>alert(1)</script>');
      await CatalogDisplayService.setAnnounceEnabled(db, true);
      await CatalogDisplayService.setAnnounceText(
          db, 'Halo </script><img src=x onerror=alert(1)> <!-- <script>');
      final html = (await OrderPageService.generateHtml(
              db: db, storeName: 'Toko </script>'))
          .html;
      final start = html.indexOf('var DATA = ');
      final line = html.substring(start, html.indexOf('\n', start));
      expect(line.contains('</'), isFalse,
          reason: 'tidak boleh ada "</" mentah di baris DATA');
      expect(line.contains('<!--'), isFalse);
      // Tetap JSON valid & isinya utuh setelah di-decode.
      final d = _data(html);
      expect(d['announcement']['text'],
          'Halo </script><img src=x onerror=alert(1)> <!-- <script>');
    });

    test('reorder default ON; mengikuti toggle', () async {
      await _addProduct(db, name: 'A');
      Future<Object?> r() async => _data(
          (await OrderPageService.generateHtml(db: db, storeName: 'T'))
              .html)['reorder'];
      expect(await r(), isTrue);
      await CatalogDisplayService.setReorderEnabled(db, false);
      expect(await r(), isFalse);
    });
  });

  group('CatalogDisplayService', () {
    test('default aman', () async {
      final d = await CatalogDisplayService.load(db);
      expect(d.showCategories, isTrue);
      expect(d.topDays, 30);
      expect(d.topCount, 8);
      expect(d.announceEnabled, isFalse);
      expect(d.reorderEnabled, isTrue);
      expect(d.hasAnnouncement, isFalse);
    });

    test('simpan & muat; jumlah saran di-clamp 3..12; rentang sendiri',
        () async {
      await CatalogDisplayService.setTopPreset(db, 90);
      await CatalogDisplayService.setTopCount(db, 99);
      var d = await CatalogDisplayService.load(db);
      expect(d.topDays, 90);
      expect(d.topCount, 12);
      await CatalogDisplayService.setTopCount(db, 1);
      expect((await CatalogDisplayService.load(db)).topCount, 3);

      await CatalogDisplayService.setTopRange(
          db, DateTime(2026, 9, 1), DateTime(2026, 9, 10));
      d = await CatalogDisplayService.load(db);
      expect(d.isCustomRange, isTrue);
      final r = d.topRange(DateTime(2026, 10, 7));
      expect(r.from, DateTime(2026, 9, 1));
      expect(r.to, DateTime(2026, 9, 10, 23, 59, 59));
      // Memilih preset lagi menimpa rentang.
      await CatalogDisplayService.setTopPreset(db, 7);
      expect((await CatalogDisplayService.load(db)).isCustomRange, isFalse);
    });

    test('rentang sendiri terbalik dibetulkan', () {
      final d = CatalogDisplay(
          topDays: 0, topFrom: DateTime(2026, 9, 10), topTo: DateTime(2026, 9, 1));
      final r = d.topRange(DateTime(2026, 10, 7));
      expect(r.from, DateTime(2026, 9, 1));
      expect(r.to.day, 10);
    });

    test('lama tampil otomatis = clamp(3000 + 60 ms x huruf, 3000, 12000)', () {
      expect(CatalogDisplay.announceAutoMs(''), 3000);
      expect(CatalogDisplay.announceAutoMs('x' * 100), 9000);
      expect(CatalogDisplay.announceAutoMs('x' * 280), 12000);
    });

    test('semua key setting tampilan ikut disinkron antar perangkat', () {
      for (final k in CatalogDisplayService.allKeys) {
        expect(AppDatabase.syncableSettingKeys, contains(k));
      }
    });
  });
}
