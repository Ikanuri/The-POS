import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Katalog HTML — tombol bawah halaman awal dipecah (Lihat Pesanan ~3/4 +
/// Kosongkan merah ~1/4) dan badge menghitung PRODUK, bukan total qty.
/// (Perilaku visual diverifikasi di browser sungguhan lewat Playwright;
/// test ini mengunci struktur & aturan hitung di sumber HTML.)
void main() {
  late String html;
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    final r =
        await OrderPageService.generateHtml(db: db, storeName: 'Toko Berkah');
    html = r.html;
    await db.close();
  });

  test(
      'tombol Kosongkan terpisah, merah, memakai clearCart() (gerbang konfirmasi)',
      () {
    expect(html, contains('id="mbClear"'));
    expect(html, contains('aria-label="Kosongkan pesanan"'));
    expect(html, contains('<span>Kosongkan pesanan</span>'));
    expect(html, contains(".mb-clear{"));
    expect(html, contains('background:#D64545'));
    expect(
        html,
        contains(
            "document.getElementById('mbClear').addEventListener('click', clearCart)"));
    // clearCart() tetap lewat showConfirm — anti-misclick.
    final body = html.substring(html.indexOf('function clearCart(){'),
        html.indexOf("document.getElementById('clearCartBtn')"));
    expect(body, contains('showConfirm('));
  });

  test(
      'halaman Pesanan: tombol Kosongkan menyusut ke lebar 0 (animasi menyatu)',
      () {
    expect(
        html,
        contains(
            '#app.order-mode .mb-clear{width:0;margin-left:0;padding:0;opacity:0;pointer-events:none;}'));
    expect(html, contains('width .32s cubic-bezier(.3,1.25,.45,1)'));
    // Header halaman Pesanan tetap punya tombol Kosongkan sendiri.
    expect(html, contains('id="clearCartBtn"'));
  });

  test('cartCount() menghitung produk berbeda (bukan total qty)', () {
    final body = html.substring(html.indexOf('function cartCount(){'),
        html.indexOf('function cartTotal()'));
    expect(body, contains('unitProduct[k]'));
    expect(body, contains('seen[key]'));
    expect(body, isNot(contains('n += cart[k]')));
    // Peta unit -> produk diisi utk satuan produk DAN satuan varian.
    expect(html, contains('unitProduct[u.unitId] = pIdx;'));
    expect(html, contains(" produk) akan dihapus"));
    expect(html, contains("' produk dipilih'"));
  });

  test('modal produk: Tambah (3/4) + Hapus merah (1/4) satu baris, pola sama',
      () {
    expect(html, contains('id="itemActions"'));
    // Hapus memakai kelas tombol merah yang SAMA dgn Kosongkan (desain persis).
    expect(html, contains('class="mb-clear" id="itemRemoveBtn"'));
    expect(html, contains('<span>Hapus dari pesanan</span>'));
    // Belum ada di pesanan -> Hapus menyusut ke 0 (Tambah selebar penuh).
    expect(
        html,
        contains(
            '.im-actions.nodel .mb-clear{width:0;margin-left:0;padding:0;opacity:0;pointer-events:none;}'));
    expect(
        html,
        contains(
            "document.getElementById('itemActions').classList.toggle('nodel', !cart[unitId]);"));
    // Hapus tetap langsung (tanpa konfirmasi) & menyimpan keranjang.
    final start =
        html.indexOf("getElementById('itemRemoveBtn').addEventListener");
    final body = html.substring(start, start + 300);
    expect(body, isNot(contains('showConfirm')));
    expect(body, contains('saveCart();'));
  });
}
