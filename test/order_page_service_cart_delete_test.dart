import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Halaman Pesanan (redesign Mockup B): tombol Kosongkan header = ikon sampah
/// (popup konfirmasi), hapus per-item lewat stepper "Tambah?" (− saat qty 1
/// = hapus langsung), dan token warna aksen merah punya varian terang/gelap.
void main() {
  test('markup + logic hapus per-item & kosongkan-keranjang lengkap', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final result =
        await OrderPageService.generateHtml(db: db, storeName: 'Toko Berkah');
    final html = result.html;

    // Header halaman Pesanan (Mockup B): tombol Kosongkan = ikon sampah di
    // bulatan putih (tanpa teks), tetap ada & tetap popup konfirmasi.
    expect(html, contains('id="clearCartBtn"'));
    final clearBtnStart = html.indexOf('id="clearCartBtn"');
    final clearBtnTag = html.substring(clearBtnStart, clearBtnStart + 300);
    expect(clearBtnTag, contains('<svg'),
        reason: 'tombol Kosongkan header harus punya ikon SVG');
    expect(clearBtnTag, contains('aria-label="Kosongkan pesanan"'));

    // Modal konfirmasi generik (ganti confirm() bawaan browser) ada di markup.
    expect(html, contains('id="confirmOverlay"'));
    expect(html, contains('id="confirmTitle"'));
    expect(html, contains('id="confirmBody"'));
    expect(html, contains('id="confirmOk"'));
    expect(html, contains('id="confirmCancel"'));
    expect(html, contains('function showConfirm('));
    expect(html, contains('function hideConfirm('));

    // clearCart() (header) memakai modal custom, bukan confirm() bawaan.
    final clearCartBody = html.substring(html.indexOf('function clearCart(){'),
        html.indexOf("document.getElementById('clearCartBtn')"));
    expect(clearCartBody, isNot(contains("confirm(")));
    expect(clearCartBody, contains('showConfirm('));
    expect(clearCartBody, contains('Kosongkan Keranjang?'));

    // Hapus per-item: tombol sampah per baris DIGANTI stepper "Tambah?" —
    // tombol − saat qty 1 menghapus baris LANGSUNG (keputusan user).
    expect(html, isNot(contains('function deleteCartItem')));
    expect(html, isNot(contains("className = 'ci-delete'")));
    final handler = html.substring(
        html.indexOf("getElementById('cartItems').addEventListener"),
        html.indexOf("getElementById('cartItems').addEventListener") + 1200);
    expect(handler, contains("act === 'open'"));
    expect(handler, contains("act === 'inc' ? cur + 1 : cur - 1"));
    expect(handler, contains('setQty(id,'));

    // Token warna aksen merah punya varian tema TERANG & GELAP (bukan
    // cuma satu warna hardcode yang bisa norak/kontras buruk di salah
    // satu tema).
    final darkBlock = html.substring(html.indexOf(':root[data-theme="dark"]'),
        html.indexOf(':root[data-theme="light"]'));
    expect(darkBlock, contains('--danger:'));
    expect(darkBlock, contains('--danger-bg:'));
    final lightBlock = html.substring(html.indexOf(':root[data-theme="light"]'),
        html.indexOf(':root[data-theme="light"]') + 300);
    expect(lightBlock, contains('--danger:'));
    expect(lightBlock, contains('--danger-bg:'));

    await db.close();
  });
}
