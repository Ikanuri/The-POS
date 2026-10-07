import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Header katalog HTML: info tidak boleh terpotong, tombol tampilan tidak
/// ada di landing, titik status cukup besar & tidak terpotong. Ukuran piksel
/// diukur lewat Playwright (lihat HANDOFF); test ini mengunci sumber HTML.
void main() {
  late String html;
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    html =
        (await OrderPageService.generateHtml(db: db, storeName: 'Toko Berkah'))
            .html;
    await db.close();
  });

  String css(String selector) {
    final a = html.indexOf(selector);
    expect(a, greaterThan(0), reason: 'CSS $selector harus ada');
    return html.substring(a, html.indexOf('}', a) + 1);
  }

  test('nama toko membungkus maks 2 baris, status tidak di-ellipsis', () {
    final store = css('.menu-top .tb-store{');
    expect(store, contains('-webkit-line-clamp:2'));
    expect(store, contains('white-space:normal'));
    final status = css('.tb-status{');
    expect(status, contains('white-space:normal'));
    expect(status, isNot(contains('overflow:hidden')));
    expect(status, isNot(contains('text-overflow')));
  });

  test('status tanpa jam buka: "Diperbarui <waktu>" di baris sendiri, utuh', () {
    final a = html.indexOf('function renderStatus(){');
    final body = html.substring(a, html.indexOf('// ── Pengumuman toko', a));
    expect(body, contains("'Katalog pesanan'"));
    expect(body, contains("'Diperbarui '"));
    expect(body, contains("nb.className = 'nb'"));
    expect(body, isNot(contains('diperbarui \' +')));
    expect(css('.tb-status .nb{'), contains('white-space:nowrap'));
  });

  test('tombol tampilan daftar/kotak disembunyikan di landing', () {
    expect(html,
        contains('#pageMenu[data-view="landing"] #layoutBtn{display:none;}'));
  });

  test('titik status: inti 10px, halo 4px, tidak terpotong overflow', () {
    final dot = css('.st-dot{');
    expect(dot, contains('width:10px;height:10px'));
    expect(dot, contains('0 0 0 4px'));
    expect(dot, contains('margin:4px 0 0 4px'));
    expect(css('.st-dot.closed{'), contains('0 0 0 4px'));
  });

  test('ringkasan Pesan lagi tidak dipotong (tanpa line-clamp)', () {
    expect(css('.again .s{'), isNot(contains('line-clamp')));
    expect(css('.hist-it .s{'), isNot(contains('line-clamp')));
  });
}
