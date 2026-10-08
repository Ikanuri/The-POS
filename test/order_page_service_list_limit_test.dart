import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Katalog HTML — daftar produk dibatasi PAGE_SIZE baris + indeks pencarian
/// dihitung sekali. Perilaku visual/performa diukur lewat Playwright; test
/// ini mengunci struktur utamanya di sumber HTML (tanpa detail rapuh).
void main() {
  late String html;
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    final r =
        await OrderPageService.generateHtml(db: db, storeName: 'Toko Berkah');
    html = r.html;
    await db.close();
  });

  String renderListBody() {
    final start = html.indexOf('function renderList(force){');
    expect(start, greaterThan(0));
    return html.substring(start, html.indexOf('// "+" selalu menambah'));
  }

  test('daftar dibatasi PAGE_SIZE = 60 + tombol "Tampilkan lagi"', () {
    expect(html, contains('var PAGE_SIZE = 60;'));
    expect(html, contains('id="moreBtn"'));
    expect(html, contains('Menampilkan '));
    expect(html, contains('ketik nama barang untuk mencari'));
    expect(html, contains('shownLimit += PAGE_SIZE;'));
    // Baris yang dibangun dibatasi shownLimit, bukan seluruh produk.
    expect(renderListBody(), contains('Math.min(shownLimit, _matches.length)'));
  });

  test('indeks pencarian dibangun SEKALI, renderList tidak toLowerCase per produk',
      () {
    expect(html, contains('var SEARCH_INDEX = DATA.products.map('));
    expect(RegExp(r'SEARCH_INDEX\s*=').allMatches(html).length, 1);
    final body = renderListBody();
    expect(body, contains('matchesQuery('));
    expect(body.contains('p.name.toLowerCase()'), isFalse);
    expect(body.contains('v.name.toLowerCase()'), isFalse);
  });

  test('query berubah mereset limit + gulir ke atas; render ulang bisa dipaksa',
      () {
    final body = renderListBody();
    expect(body, contains('shownLimit = PAGE_SIZE;'));
    expect(body, contains('qChanged ? 0 : keepScroll'));
    // Pemicu lain (keranjang berubah, shopClosed) memaksa render ulang.
    expect(html, contains('function render(){ renderList(true);'));
    expect(html, contains('renderList(true); // shopClosed berubah'));
  });
}
