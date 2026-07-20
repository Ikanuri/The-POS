import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Keluhan user: katalog HTML statis kehilangan seluruh keranjang saat
/// pelanggan refresh browser (variabel `cart` murni di memori JS). Tombol
/// refresh tidak bisa dihilangkan/diblokir dari halaman web biasa (apalagi
/// dibuka lewat in-app browser WhatsApp yang tidak selalu dukung
/// `beforeunload`) — solusi yang disepakati: cache ke `localStorage`,
/// di-keyed per versi katalog (`DATA.generatedAt`) + kedaluwarsa 1 hari,
/// plus tombol "Kosongkan" untuk pesanan batch baru.
void main() {
  test('katalog HTML memuat mekanisme persist keranjang (localStorage, TTL '
      '1 hari, keyed per versi katalog) & tombol Kosongkan', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'p1',
          name: 'Gula Pasir',
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u1',
          productId: 'p1',
          unitTypeId: const Value(2),
          isBaseUnit: const Value(true),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'u1-t1',
          productUnitId: 'u1',
          minQty: const Value(1),
          price: 15000,
        ));

    final result =
        await OrderPageService.generateHtml(db: db, storeName: 'Toko Berkah');
    final html = result.html;

    // TTL 1 hari (24*60*60*1000 ms) & key localStorage.
    expect(html, contains('CART_TTL_MS = 24 * 60 * 60 * 1000'));
    expect(html, contains("CART_STORAGE_KEY = 'posOrderCart'"));

    // Disimpan keyed per versi katalog (generatedAt) — cache dari katalog
    // LAMA harus otomatis basi kalau toko generate ulang.
    expect(html, contains('generatedAt: DATA.generatedAt'));
    expect(html, contains('saved.generatedAt !== DATA.generatedAt'));

    // Fungsi inti persist ada & dipanggil di titik mutasi keranjang.
    expect(html, contains('function saveCart()'));
    expect(html, contains('function loadCart()'));
    expect(html, contains('function clearCart()'));
    expect(html, contains('localStorage.setItem(CART_STORAGE_KEY'));
    expect(html, contains('localStorage.getItem(CART_STORAGE_KEY)'));

    // loadCart() dipanggil SEBELUM render() pertama saat halaman dibuka.
    final loadIdx = html.indexOf('loadCart();');
    final renderIdx = html.indexOf('render();', loadIdx);
    expect(loadIdx, greaterThan(-1));
    expect(renderIdx, greaterThan(loadIdx),
        reason: 'loadCart() harus dipanggil sebelum render() awal, supaya '
            'cache termuat sebelum layar pertama digambar');

    // Tombol "Kosongkan" di header sheet Pesanan, terhubung ke clearCart().
    expect(html, contains('id="clearCartBtn"'));
    expect(html, contains('Kosongkan'));
    expect(
        html,
        contains(
            "document.getElementById('clearCartBtn').addEventListener('click', clearCart)"));

    await db.close();
  });

  test('setQty() dan handler modal tambah/hapus item sama-sama memanggil '
      'saveCart() — tidak ada jalur mutasi cart yang terlewat', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final result =
        await OrderPageService.generateHtml(db: db, storeName: 'Toko Berkah');
    final html = result.html;

    // setQty() — dipakai tombol +/- di daftar & di sheet keranjang.
    final setQtyBody = html.substring(
        html.indexOf('function setQty(unitId, qty){'),
        html.indexOf('function refreshProwControls'));
    expect(setQtyBody, contains('saveCart();'));

    // itemAddBtn / itemRemoveBtn — mutasi langsung dari modal tap-item.
    final addBtnBody = html.substring(
        html.indexOf("getElementById('itemAddBtn').addEventListener"),
        html.indexOf("getElementById('itemRemoveBtn').addEventListener"));
    expect(addBtnBody, contains('saveCart();'));

    final removeBtnStart =
        html.indexOf("getElementById('itemRemoveBtn').addEventListener");
    final removeBtnBody =
        html.substring(removeBtnStart, removeBtnStart + 300);
    expect(removeBtnBody, contains('saveCart();'));

    await db.close();
  });
}
