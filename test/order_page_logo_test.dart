import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Logo header katalog HTML = persik The POS (garis putih di kotak aksen),
/// bukan lagi huruf awal nama toko.
void main() {
  late String html;
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    html = (await OrderPageService.generateHtml(db: db, storeName: 'Budi Mart'))
        .html;
    await db.close();
  });

  test('logo header berisi SVG persik (garis), bukan huruf awal toko', () {
    final a = html.indexOf('id="storeLogo"');
    expect(a, greaterThan(0));
    final span = html.substring(a, html.indexOf('</span>', a));
    expect(span, contains('<svg'));
    expect(span, contains('stroke="currentColor"'));
    // 4 garis: badan, daun, lekukan, kilau.
    expect('<path'.allMatches(span).length, 4);
    // Tidak ada kode yang menimpa isi logo dengan huruf awal toko.
    expect(html, isNot(contains("getElementById('storeLogo').textContent")));
  });

  test('logo: SVG mengikuti ukuran kotak (72%), warna putih dari .tb-logo', () {
    expect(html, contains('.tb-logo svg{width:72%;height:72%;'));
    final a = html.indexOf('.tb-logo{width:42px');
    expect(html.substring(a, html.indexOf('}', a)), contains('color:#fff'));
  });
}
