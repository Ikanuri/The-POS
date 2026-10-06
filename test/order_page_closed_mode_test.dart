import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/catalog_access_service.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Katalog HTML — mode toko tutup: jadwal jam (zona HP owner), kode per
/// pelanggan (hash saja), harga disembunyikan saat tutup. Perilaku di browser
/// diverifikasi lewat Playwright (jam disimulasikan); test ini mengunci data
/// yang masuk ke HTML & strukturnya.
void main() {
  test('tanpa jam/kode: HTML memuat hours:null & access:null (perilaku lama)',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final html =
        (await OrderPageService.generateHtml(db: db, storeName: 'Toko')).html;
    expect(html, contains('"hours":null'));
    expect(html, contains('"access":null'));
  });

  test('jam & kode: DATA berisi jadwal + HASH, tanpa kode asli/nama pelanggan',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await db
        .into(db.customers)
        .insert(CustomersCompanion.insert(id: 'C1', name: 'Bu Rahasia Sekali'));
    final code = await CatalogAccessService.rotateCode(db, 'C1');
    await CatalogAccessService.saveHours(
        db,
        const CatalogHours(
            enabled: true, openMinutes: 420, closeMinutes: 1260));
    final html =
        (await OrderPageService.generateHtml(db: db, storeName: 'Toko')).html;
    expect(html, contains('"open":420'));
    expect(html, contains('"close":1260'));
    expect(html, contains('"tz":'));
    final a = (await CatalogAccessService.accessJson(db))!;
    expect(html, contains((a['hashes'] as List).single as String));
    expect(html, isNot(contains(code)));
    expect(html, isNot(contains(CatalogAccessService.normalizeCode(code))));
    expect(html, isNot(contains('Bu Rahasia Sekali')));
  });

  test('tombol darurat "Tutup sekarang" masuk sbg forced:true', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await CatalogAccessService.saveHours(
        db, const CatalogHours(forcedClosed: true));
    final html =
        (await OrderPageService.generateHtml(db: db, storeName: 'Toko')).html;
    expect(html, contains('"forced":true'));
  });

  test('struktur HTML: banner, dialog kode, cek berkala, harga disembunyikan',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final html =
        (await OrderPageService.generateHtml(db: db, storeName: 'Toko')).html;
    expect(html, contains('id="closedBanner"'));
    expect(html, contains('Pelanggan langganan? Masukkan kode'));
    expect(html, contains('id="codeOverlay"'));
    expect(html, contains('function hoursState()'));
    expect(html, contains('DATA.hours.tz * 60000'));
    expect(html, contains("'Toko tutup · buka '"));
    // Jadwal dicek ulang berkala & saat tab kembali aktif.
    expect(html, contains('setInterval(applyOpenState, 30000)'));
    expect(html, contains("document.addEventListener('visibilitychange'"));
    // Harga hanya disembunyikan di tampilan daftar.
    expect(html, contains("var metaHtml = shopClosed ? '—'"));
    // Kode: PBKDF2 sama dgn app; tersimpan hanya HASH-nya di localStorage.
    expect(html, contains("name: 'PBKDF2'"));
    expect(html, contains("hash: 'SHA-256'"));
    expect(
        html,
        contains(
            "localStorage.setItem(ACCESS_KEY, JSON.stringify({hash: h}))"));
    // Pesanan saat tutup = order biasa: tidak ada label/mode pre-order.
    expect(html, isNot(contains('PRE-ORDER')));
    expect(html, isNot(contains('Mode titipan')));
  });
}
