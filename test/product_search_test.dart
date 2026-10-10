import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';
import 'package:the_pos/core/utils/product_search.dart';

/// Pencarian produk toleran (urutan kata bebas, tanda baca/aksen/spasi
/// diabaikan, satuan dinormalkan, ikut cari kode & kategori). Kasir/Produk
/// (Dart) dan katalog HTML (JS) memakai aturan YANG SAMA.
void main() {
  group('ProductSearch.normalize', () {
    test('huruf kecil, tanda baca jadi spasi, aksen dibuang', () {
      expect(
          ProductSearch.normalize('Cone-Snack  KUNING!'), 'cone snack kuning');
      expect(ProductSearch.normalize('Café Crème'), 'cafe creme');
    });
    test('satuan dinormalkan', () {
      expect(ProductSearch.normalize('Gula 500 gr'), 'gula 500g');
      expect(ProductSearch.normalize('Gula 500gram'), 'gula 500g');
      expect(ProductSearch.normalize('Minyak 1 liter'), 'minyak 1l');
      expect(ProductSearch.normalize('Susu 250 ml'), 'susu 250ml');
      expect(ProductSearch.normalize('Beras 5 kg'), 'beras 5kg');
    });
  });

  group('ProductSearch.matches', () {
    bool m(String q, String name, {String? kode, String? group}) =>
        ProductSearch(q).matches(name, kode: kode, group: group);

    test('urutan kata bebas', () {
      expect(m('goreng indomie', 'Indomie Goreng'), isTrue);
      expect(m('indomie goreng', 'Indomie Goreng'), isTrue);
      expect(m('indomie soto', 'Indomie Goreng'), isFalse);
    });
    test('tanda baca & spasi diabaikan', () {
      expect(m('cone snack', 'Cone-Snack Kuning'), isTrue);
      expect(m('conesnack', 'Cone-Snack Kuning'), isTrue);
      expect(m('cone-snack', 'Cone Snack Kuning'), isTrue);
    });
    test('satuan', () {
      expect(m('gula 500gr', 'Gula Pasir 500 g'), isTrue);
      expect(m('500 gram gula', 'Gula Pasir 500g'), isTrue);
    });
    test('kode & kategori ikut dicari', () {
      expect(m('gbf', 'Gajah Baru Filter', kode: 'GBF'), isTrue);
      expect(m('minuman', 'Teh Botol', group: 'Minuman'), isTrue);
      expect(m('teh minuman', 'Teh Botol', group: 'Minuman'), isTrue);
      expect(m('minuman', 'Teh Botol'), isFalse);
    });
    test('potongan di tengah kata tetap cocok (perilaku lama)', () {
      expect(m('ndom', 'Indomie Goreng'), isTrue);
    });
    test('kueri kosong = cocok semua', () {
      expect(m('', 'Apa saja'), isTrue);
      expect(m('   ', 'Apa saja'), isTrue);
    });
    test('SEMUA yang dulu cocok (potongan berurutan) tetap cocok', () {
      const names = [
        'Indomie Goreng',
        'Cone-Snack Kuning',
        'Gula 1.5 kg',
        'A/B C'
      ];
      for (final n in names) {
        final lower = n.toLowerCase();
        for (var i = 0; i < lower.length; i++) {
          for (var j = i + 1; j <= lower.length; j++) {
            final sub = lower.substring(i, j);
            if (sub.trim().isEmpty) continue;
            expect(ProductSearch(sub).matches(n), isTrue,
                reason: '"$sub" dulu cocok di "$n"');
          }
        }
      }
    });
  });

  group('database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() async => db.close());

    Future<void> add(String id, String name,
        {String? kode, int? groupId}) async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: id,
            name: name,
            kodeProduk: Value(kode),
            productGroupId: Value(groupId),
          ));
    }

    Future<int> group(String name) => db
        .into(db.productGroups)
        .insert(ProductGroupsCompanion.insert(name: Value(name)));

    test('searchProducts & watchProducts: urutan bebas, kode, kategori',
        () async {
      final minuman = await group('Minuman');
      await add('1', 'Teh Botol Sosro', groupId: minuman);
      await add('2', 'Indomie Goreng');
      await add('3', 'Gajah Baru Filter', kode: 'GBF');
      Future<List<String>> names(String q) async =>
          (await db.searchProducts(q)).map((p) => p.name).toList();
      expect(await names('goreng indomie'), ['Indomie Goreng']);
      expect(await names('gbf'), ['Gajah Baru Filter']);
      expect(await names('minuman'), ['Teh Botol Sosro']);
      expect(await names('botol minuman'), ['Teh Botol Sosro']);
      expect(await names('zzz'), isEmpty);
      expect((await names('')).length, 3);

      final w = await db.watchProducts(query: 'sosro botol').first;
      expect(w.map((p) => p.name), ['Teh Botol Sosro']);
      final wc =
          await db.watchProducts(query: 'minuman', groupId: minuman).first;
      expect(wc.map((p) => p.name), ['Teh Botol Sosro']);
    });

    test('watchProductsForKasir (chip kategori + kueri) memakai aturan sama',
        () async {
      final minuman = await group('Minuman');
      await add('1', 'Teh Botol Sosro', groupId: minuman);
      await add('2', 'Teh Kotak', groupId: minuman);
      final r = await db
          .watchProductsForKasir(query: 'sosro teh', groupId: minuman)
          .first;
      expect(r.map((p) => p.name), ['Teh Botol Sosro']);
    });

    test('stream aktif: hasil ikut berubah saat produk baru ditambah',
        () async {
      await add('1', 'Indomie Goreng');
      final events = <List<String>>[];
      final sub = db
          .watchProducts(query: 'goreng indomie')
          .listen((l) => events.add(l.map((p) => p.name).toList()));
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await add('2', 'Mie Goreng Indomie Jumbo');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(events.last,
          containsAll(['Indomie Goreng', 'Mie Goreng Indomie Jumbo']));
    });
  });

  group('katalog HTML (JS)', () {
    Future<String?> nodePath() async {
      final r = await Process.run('which', ['node']);
      return r.exitCode == 0 ? (r.stdout as String).trim() : null;
    }

    test('matchesQuery JS = aturan Dart (dijalankan lewat node)', () async {
      final node = await nodePath();
      if (node == null) {
        markTestSkipped('node tidak tersedia');
        return;
      }
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async => db.close());
      final html = (await OrderPageService.generateHtml(
              db: db, storeName: 'T', stickers: {}))
          .html;
      final a = html.indexOf('function normSearch(text){');
      final b = html.indexOf('function fmtCount(n){');
      expect(a, greaterThan(0));
      expect(b, greaterThan(a));
      final js = html.substring(a, b);
      final script = '''
var DATA = { products: [
  {name:'Indomie Goreng', category:'Mie', variants:[]},
  {name:'Cone-Snack Kuning', category:'Snack', variants:[]},
  {name:'Gula Pasir 500 g', category:'Sembako', variants:[{name:'Merah'}]},
  {name:'Teh Botol', category:'Minuman', variants:[]}
]};
$js
function t(q){ var r=[]; for (var i=0;i<DATA.products.length;i++) if (matchesQuery(i,q)) r.push(i); return r.join(','); }
console.log(JSON.stringify({
  a: t('goreng indomie'), b: t('cone snack'), c: t('conesnack'),
  d: t('gula 500gr'), e: t('minuman'), f: t('merah gula'), g: t('zzz'),
  h: t('ndom'), i: t('')
}));
''';
      final r = await Process.run(node, ['-e', script]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((r.stdout as String).trim(),
          '{"a":"0","b":"1","c":"1","d":"2","e":"3","f":"2","g":"","h":"0","i":"0,1,2,3"}');
    });
  });
}
