import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Kolom cari katalog: saran "Cari <nama>? Tekan →", tetap berputar saat
/// fokus, tombol X outline yang tidak mencuri fokus (keyboard tetap terbuka).
void main() {
  test('kerangka saran, putaran saat fokus, tombol X outline & tahan fokus',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final html = (await OrderPageService.generateHtml(
            db: db, storeName: 'T', stickers: {}))
        .html;
    expect(html, contains("c.textContent = '? Tekan';"));
    expect(html, contains('class="ph-arr"'));
    // Hanya nama produk yang boleh terpotong; ekor "? Tekan →" utuh.
    expect(html, contains('.ph span b{flex-shrink:1;min-width:0;overflow:hidden;'));
    // Berputar walau kolom fokus; berhenti hanya bila ada huruf.
    expect(html, isNot(contains('document.activeElement !== qEl')));
    expect(html, contains('!document.hidden && !qEl.value && !sheetOpen'));
    // X = lingkaran outline.
    expect(html,
        contains('.search.has-text .go{background:transparent;border:1.5px solid'));
    // Tombol tidak mencuri fokus dari kolom cari.
    expect(html, contains("['mousedown', 'pointerdown'].forEach"));
    expect(html, contains('if (document.activeElement === qEl) e.preventDefault();'));
  });
}
