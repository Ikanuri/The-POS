import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Animasi roll angka di katalog HTML tidak boleh menggeser "Rp"/digit.
/// Akar bug (diukur Playwright, 360px): spasi di sel flex dgn
/// `white-space:nowrap` (mis. `.mb-total`) runtuh ke lebar 0 selama roll,
/// lalu kembali 6px saat teks diruntuhkan jadi satu node => "Rp" melonjak
/// 4px (tombol) / 6px (total Pesanan). Perilaku visual diukur lewat
/// Playwright (lihat HANDOFF); test ini mengunci perbaikan di sumber HTML.
void main() {
  late String html;
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    html =
        (await OrderPageService.generateHtml(db: db, storeName: 'Toko Berkah'))
            .html;
    await db.close();
  });

  test('semua sel roll memaksa white-space:pre (spasi tidak runtuh)', () {
    expect(html, contains('.roll>span{white-space:pre;}'));
  });

  test('jumlah digit berubah: teks meluncur mulus dari posisi lama', () {
    final a = html.indexOf('function rollSet(el, text){');
    final body = html.substring(a, html.indexOf('function rp(n){', a));
    expect(body, contains('rollLeft(el)'));
    expect(body, contains("el.style.transform = 'translateX(' + dx + 'px)'"));
    // transform dibersihkan saat roll diruntuhkan jadi teks biasa
    expect(body, contains("el.style.transform = '';"));
  });
}
