import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Susulan permintaan user: (1) opsi hapus per-item di keranjang katalog
/// HTML (alih-alih cuma bisa turunkan qty ke 0), dengan konfirmasi; (2)
/// tombol "Kosongkan" diganti ikon tempat sampah + teks "Kosongkan
/// Keranjang", pojok kanan-atas header sheet, aksen merah; (3) kompatibel
/// tema gelap (token warna baru punya varian dark).
void main() {
  test('markup + logic hapus per-item & kosongkan-keranjang lengkap', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final result =
        await OrderPageService.generateHtml(db: db, storeName: 'Toko Berkah');
    final html = result.html;

    // Tombol "Kosongkan Keranjang" — ikon tempat sampah + teks lengkap,
    // BUKAN lagi "Kosongkan" polos bergaris bawah.
    expect(html, contains('Kosongkan Keranjang'));
    expect(html, contains('id="clearCartBtn"'));
    final clearBtnStart = html.indexOf('id="clearCartBtn"');
    final clearBtnTag = html.substring(clearBtnStart, clearBtnStart + 300);
    expect(clearBtnTag, contains('<svg'),
        reason: 'tombol Kosongkan Keranjang harus punya ikon SVG di dalamnya');

    // Modal konfirmasi generik (ganti confirm() bawaan browser) ada di markup.
    expect(html, contains('id="confirmOverlay"'));
    expect(html, contains('id="confirmTitle"'));
    expect(html, contains('id="confirmBody"'));
    expect(html, contains('id="confirmOk"'));
    expect(html, contains('id="confirmCancel"'));
    expect(html, contains('function showConfirm('));
    expect(html, contains('function hideConfirm('));

    // clearCart() TIDAK lagi pakai confirm() bawaan browser — pakai modal
    // custom supaya ikut tema app (dulu: `!confirm('Kosongkan semua...`).
    final clearCartBody = html.substring(
        html.indexOf('function clearCart(){'),
        html.indexOf('function deleteCartItem'));
    expect(clearCartBody, isNot(contains("confirm(")));
    expect(clearCartBody, contains('showConfirm('));
    expect(clearCartBody, contains('Kosongkan Keranjang?'));

    // deleteCartItem(unitId) — hapus SATU barang, terpisah dari stepper −,
    // dengan konfirmasi eksplisit sebelum benar-benar menghapus.
    expect(html, contains('function deleteCartItem(unitId){'));
    final deleteFnBody = html.substring(
        html.indexOf('function deleteCartItem(unitId){'),
        html.indexOf('function deleteCartItem(unitId){') + 400);
    expect(deleteFnBody, contains('showConfirm('));
    expect(deleteFnBody, contains('Hapus Barang?'));
    expect(deleteFnBody, contains('setQty(unitId, 0)'));

    // Baris keranjang (renderCartSheet) merender tombol hapus per-item
    // (class ci-delete, data-act="delete") berdampingan dgn stepper qty —
    // bukan cuma mengandalkan stepper − sampai 0.
    final cartSheetBody = html.substring(
        html.indexOf('function renderCartSheet(){'),
        html.indexOf('function renderCartSheet(){') + 2000);
    expect(cartSheetBody, contains("className = 'ci-delete'"));
    expect(cartSheetBody, contains("dataset.act = 'delete'"));

    // Delegasi klik #cartItems menangani data-act="delete" -> panggil
    // deleteCartItem (BUKAN langsung setQty ke 0 tanpa konfirmasi).
    final delegationBody = html.substring(
        html.indexOf("getElementById('cartItems').addEventListener"),
        html.indexOf("getElementById('cartItems').addEventListener") + 400);
    expect(delegationBody, contains("dataset.act === 'delete'"));
    expect(delegationBody, contains('deleteCartItem(id)'));

    // Token warna aksen merah punya varian tema TERANG & GELAP (bukan
    // cuma satu warna hardcode yang bisa norak/kontras buruk di salah
    // satu tema).
    final darkBlock = html.substring(
        html.indexOf(':root[data-theme="dark"]'),
        html.indexOf(':root[data-theme="light"]'));
    expect(darkBlock, contains('--danger:'));
    expect(darkBlock, contains('--danger-bg:'));
    final lightBlock = html.substring(
        html.indexOf(':root[data-theme="light"]'),
        html.indexOf(':root[data-theme="light"]') + 300);
    expect(lightBlock, contains('--danger:'));
    expect(lightBlock, contains('--danger-bg:'));

    await db.close();
  });
}
