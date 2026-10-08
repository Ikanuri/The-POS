import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Kategori dimatikan: katalog TETAP membuka halaman awal (landing) dengan satu
/// chip "Semua produk" — tidak lagi langsung menampilkan seluruh daftar.
void main() {
  test('landing selalu ada; tanpa kategori hanya chip "Semua produk"', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final html = (await OrderPageService.generateHtml(
            db: db, storeName: 'T', stickers: {}))
        .html;
    expect(html,
        contains("var view = (q || selCat !== null) ? 'list' : 'landing';"));
    expect(html, isNot(contains("(!CATS_ON || q || selCat !== null)")));
    expect(html,
        contains("if (!CATS_ON) return;   // kategori dimatikan: landing hanya"));
    expect(html, contains("byId('extrasSlotL').appendChild(extrasEl);"));
    expect(html, contains('function goLanding(noAnim){\n  selCat = null;'));
  });
}
