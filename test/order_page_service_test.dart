import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/csv_import_service.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Test Tier 1 (DB murni) untuk fitur eksperimental "Katalog Pesanan".
/// Membuktikan katalog yang di-embed di HTML benar-benar mencerminkan data
/// aktif di database — bukan sekadar template ter-render.

Future<String> _addProduct(
  AppDatabase db, {
  required String name,
  required int price,
  int costPrice = 0,
  bool isActive = true,
  String? parentProductId,
  int unitTypeId = 2, // Pcs
}) async {
  final productId = 'p-${DateTime.now().microsecondsSinceEpoch}-$name';
  final unitId = '$productId-u';
  await db.into(db.products).insert(ProductsCompanion.insert(
        id: productId,
        name: name,
        isActive: Value(isActive),
        parentProductId: Value(parentProductId),
      ));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId,
        productId: productId,
        unitTypeId: Value(unitTypeId),
        isBaseUnit: const Value(true),
      ));
  await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: '$unitId-t1',
        productUnitId: unitId,
        minQty: const Value(1),
        price: price,
        costPrice: Value(costPrice),
      ));
  return productId;
}

Future<String> _unitIdOf(AppDatabase db, String productId) async {
  final u = await (db.select(db.productUnits)
        ..where((t) => t.productId.equals(productId)))
      .getSingle();
  return u.id;
}

Map<String, dynamic> _extractEmbeddedData(String html) {
  // jsonEncode selalu menghasilkan satu baris (tanpa newline literal, hanya
  // \n ter-escape di dalam string) — cukup tangkap sampai akhir baris. Pola
  // dotAll+greedy sebelumnya menangkap sampai `};` TERAKHIR di seluruh
  // <script> (banyak fungsi JS lain juga diakhiri `};`), menghasilkan JSON
  // tidak valid.
  final match = RegExp(r'^var DATA = (.+);$', multiLine: true).firstMatch(html);
  expect(match, isNotNull, reason: 'HTML harus memuat blok `var DATA = {...}`');
  return jsonDecode(match!.group(1)!) as Map<String, dynamic>;
}

void main() {
  test('katalog HTML memuat produk aktif berharga valid, mengecualikan yang '
      'tidak aktif / harga 0', () async {
    final db = AppDatabase(NativeDatabase.memory());

    await _addProduct(db, name: 'Gula Pasir', price: 15000);
    await _addProduct(db, name: 'Nonaktif', price: 10000, isActive: false);
    await _addProduct(db, name: 'Belum Diberi Harga', price: 0);

    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');
    final data = _extractEmbeddedData(result.html);
    final names =
        (data['products'] as List).map((p) => p['name']).toSet();

    expect(names, contains('Gula Pasir'));
    expect(names, isNot(contains('Nonaktif')),
        reason: 'produk isActive=false tidak boleh muncul di katalog publik');
    expect(names, isNot(contains('Belum Diberi Harga')),
        reason: 'produk tanpa harga valid (0) membingungkan pelanggan bila '
            'ditampilkan sebagai Rp 0');
    expect(result.productCount, 1);
    await db.close();
  });

  test('varian ikut ter-embed di bawah produk induknya dengan harga sendiri',
      () async {
    final db = AppDatabase(NativeDatabase.memory());

    final parentId =
        await _addProduct(db, name: 'Pop Ice', price: 2000);
    await _addProduct(db,
        name: 'Coklat', price: 2500, parentProductId: parentId);
    await _addProduct(db,
        name: 'Stroberi', price: 2500, parentProductId: parentId);

    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');
    final data = _extractEmbeddedData(result.html);
    final products = data['products'] as List;

    // Varian TIDAK boleh muncul sebagai baris induk terpisah — hanya
    // bersarang di bawah 'Pop Ice', sama seperti katalog kasir.
    expect(products.map((p) => p['name']), ['Pop Ice']);
    final variants = products.first['variants'] as List;
    expect(variants.map((v) => v['name']).toSet(), {'Coklat', 'Stroberi'});
    expect(variants.first['price'], anyOf(2500, 2500));
    await db.close();
  });

  test('identitas baris pakai productUnitId asli — parsing di fase '
      'berikutnya bisa lookup langsung ke DB tanpa kodeProduk', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId =
        await _addProduct(db, name: 'Minyak Goreng', price: 32000);
    final unitId = await _unitIdOf(db, productId);

    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');
    final data = _extractEmbeddedData(result.html);
    final products = data['products'] as List;

    expect(products.first['unitId'], unitId,
        reason: 'unitId di katalog harus persis productUnitId di DB, bukan '
            'kodeProduk (yang boleh kosong/tidak unik)');
    await db.close();
  });

  test('nomor WhatsApp toko disaring hanya digit sebelum di-embed', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await _addProduct(db, name: 'Beras', price: 65000);

    final result = await OrderPageService.generateHtml(
      db: db,
      storeName: 'Toko Berkah',
      storeWhatsapp: '+62 812-3456-7890',
    );
    final data = _extractEmbeddedData(result.html);
    expect(data['waNumber'], '6281234567890');
    await db.close();
  });

  test('nama toko & konten HTML tidak menyisipkan tag/skrip berbahaya '
      '(XSS) walau nama toko mengandung karakter aneh', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await _addProduct(db, name: 'Gula', price: 15000);

    final result = await OrderPageService.generateHtml(
      db: db,
      storeName: 'Toko "Berkah" </script><script>alert(1)</script>',
    );
    // Tag </script> mentah tidak boleh muncul apa adanya di dalam blok data
    // (harus ter-escape "<\/script>"), supaya browser tidak menutup blok
    // <script> lebih awal lalu mengeksekusi sisipan HTML sebagai skrip baru.
    expect(result.html.contains('</script><script>alert'), isFalse);
    await db.close();
  });

  test('produk tanpa satuan dasar (data rusak) dilewati dengan aman, '
      'bukan crash', () async {
    final db = AppDatabase(NativeDatabase.memory());
    // Produk tanpa productUnits sama sekali.
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p-broken', name: 'Rusak'));
    await _addProduct(db, name: 'Sabun', price: 5000);

    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');
    final data = _extractEmbeddedData(result.html);
    final names = (data['products'] as List).map((p) => p['name']).toSet();
    expect(names, {'Sabun'});
    await db.close();
  });

  test(
      'produk PUNYA satuan tapi tidak ada yang ditandai isBaseUnit (data '
      'lama sebelum fix import CSV) tetap muncul via fallback ke satuan '
      'pertama, tidak hilang diam-diam', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p-legacy', name: 'Produk Lama'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u-legacy',
          productId: 'p-legacy',
          unitTypeId: const Value(2),
          isBaseUnit: const Value(false), // simulasi data lama yang rusak
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'u-legacy-t1',
          productUnitId: 'u-legacy',
          minQty: const Value(1),
          price: 7500,
        ));

    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');
    final data = _extractEmbeddedData(result.html);
    final names = (data['products'] as List).map((p) => p['name']).toSet();
    expect(names, contains('Produk Lama'));
    await db.close();
  });

  test(
      'produk hasil Import CSV Griyo POS tampil di katalog HTML (regresi: '
      'importer sempat tidak menandai isBaseUnit sama sekali, katalog HTML '
      'jadi kosong walau tab Produk normal)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    const csv = 'Produk;Harga Pokok;Harga Jual;Stok;Grup Produk;Satuan;'
        'Barcode;Kode Produk;Non Stok\n'
        'Sedap Goreng;2700;2800;26;6;12;8998866200301;Biji;1\n';
    await CsvImportService.importFromBytes(bytes: csv.codeUnits, db: db);

    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');
    final data = _extractEmbeddedData(result.html);
    final names = (data['products'] as List).map((p) => p['name']).toSet();
    expect(names, contains('Sedap Goreng'));
    await db.close();
  });

  test(
      'Item 25a — produk ditandai stok habis tampil badge "Stok Habis" di '
      'katalog HTML, bukan tombol tambah', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final id = await _addProduct(db, name: 'Gula Pasir', price: 15000);
    await db.setMarkedOutOfStock(id, true);

    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');
    final data = _extractEmbeddedData(result.html);
    final products = data['products'] as List;
    final p = products.firstWhere((p) => p['name'] == 'Gula Pasir');
    expect(p['outOfStock'], isTrue);
    // Markup render badge & skip tombol tambah untuk produk outOfStock —
    // dicek lewat keberadaan kelas CSS-nya di template.
    expect(result.html.contains('oos-badge'), isTrue);
    await db.close();
  });

  test(
      'Item 25a — produk TIDAK ditandai stok habis → outOfStock false di '
      'data katalog', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await _addProduct(db, name: 'Teh Celup', price: 8000);

    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');
    final data = _extractEmbeddedData(result.html);
    final products = data['products'] as List;
    final p = products.firstWhere((p) => p['name'] == 'Teh Celup');
    expect(p['outOfStock'], isFalse);
    await db.close();
  });

  test(
      'Item 24c — default TERANG selalu (tidak ikut prefers-color-scheme '
      'HP pelanggan), font Hanken Grotesk/Newsreader ter-embed', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');

    // TIDAK ADA lagi auto-dark ikut OS pelanggan — dulu ada blok CSS
    // `@media (prefers-color-scheme: dark)` + JS `matchMedia(...)` yang
    // bikin katalog gelap tanpa dipilih; sekarang default HARUS selalu
    // terang (cek marker fungsional, bukan sekadar substring bebas — teks
    // "prefers-color-scheme" masih boleh muncul di komentar penjelas).
    expect(result.html.contains('@media (prefers-color-scheme'), isFalse);
    expect(result.html.contains('matchMedia'), isFalse);
    expect(result.html.contains("saved = 'light'"), isTrue);

    // Font disamakan dengan app (Hanken Grotesk = UI, Newsreader = angka),
    // di-embed sebagai @font-face base64 (bukan cuma system-font fallback).
    expect(result.html.contains("--font:'Hanken Grotesk'"), isTrue);
    expect(result.html.contains("--serif:'Newsreader'"), isTrue);
    expect(result.html.contains("font-family:'Hanken Grotesk'"), isTrue);
    expect(result.html.contains("font-family:'Newsreader'"), isTrue);
    expect(result.html.contains('data:font/woff2;base64,'), isTrue);

    await db.close();
  });

  test(
      'Item 26a/14 — catatan per-produk diedit lewat modal tap-item '
      '(bukan lagi input di lembar keranjang), buildOrderText encode '
      'catatan ke segmen ":<catatan>" di kode mesin',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');

    // Item 14 — input catatan yang dulu ada DI DALAM lembar keranjang
    // (ci-note editable) sudah dihapus; catatan sekarang murni tampilan
    // read-only di sana (ci-note-view), diedit lewat modal item.
    expect(result.html.contains("noteInput.className = 'tfield ci-note'"),
        isFalse);
    expect(result.html.contains('ci-note-view'), isTrue);

    // Modal tap-item (pengganti <details>) punya textarea catatan sendiri.
    expect(result.html.contains('id="itemNote"'), isTrue);
    expect(
        result.html
            .contains("if (note) cartNotes[unitId] = note; else delete"),
        isTrue);

    // Encoding ke kode mesin: id=qty:catatan(encodeURIComponent) — TIDAK
    // berubah walau sumber catatan pindah tempat.
    expect(
        result.html.contains(
            "codeParts.push(id + '=' + qty + (itemNote ? ':' + encodeURIComponent(itemNote) : ''))"),
        isTrue);

    await db.close();
  });

  test(
      'Item 14 — modal tap-item menggantikan <details> lama: satu modal '
      'utk semua produk (varian/tidak), harga TIDAK bisa diketik pelanggan',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');

    // <details>/<summary>/chevron lama sudah tidak ada.
    expect(result.html.contains('<details'), isFalse);
    expect(result.html.contains('<summary'), isFalse);
    expect(result.html.contains('class="chev"'), isFalse);

    // Modal tap-item + pemilih satuan/varian.
    expect(result.html.contains('id="itemSheet"'), isTrue);
    expect(result.html.contains('id="itemUnitChips"'), isTrue);
    expect(result.html.contains('function openItemModal('), isTrue);

    // Harga MURNI tampilan (bukan input yang bisa diketik pelanggan) — tidak
    // ada lagi field harga custom sama sekali di modal ini.
    expect(result.html.contains('id="itemPriceDisplay"'), isTrue);
    expect(result.html.contains('id="itemPrice"'), isFalse);
    expect(result.html.contains('(harga custom)'), isFalse);

    // Jumlah bisa diketik langsung (input), bukan cuma label statis.
    expect(
        result.html
            .contains('id="itemQtyVal" type="number" inputmode="decimal"'),
        isTrue);

    expect(
        result.html.contains(
            "codeParts.push(id + '=' + qty + (itemNote ? ':' + encodeURIComponent(itemNote) : ''))"),
        isTrue);

    await db.close();
  });

  test(
      'Item 14 — daftar produk punya kontrol +/− lingkaran (meniru app '
      'kasir), bukan cuma badge angka/chevron', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');

    expect(result.html.contains('prow-circle-add'), isTrue);
    expect(result.html.contains('prow-circle-qty'), isTrue);
    expect(result.html.contains('prow-minus'), isTrue);
    expect(result.html.contains('function prowQuickAdd('), isTrue);
    expect(result.html.contains('prow-badge'), isFalse);
    expect(result.html.contains('prow-chevron'), isFalse);

    await db.close();
  });

  test(
      'produk dengan >1 satuan (mis. Biji dasar + Dus) — SEMUA satuan '
      'ter-embed di field `units`, bukan cuma satuan dasar', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db,
        name: 'Sedap Goreng', price: 2500, unitTypeId: 1 /* Biji */);
    // Satuan KEDUA (Dus) utk produk yang SAMA — bukan varian, bukan produk
    // baru. Sebelum fix, satuan ini tidak pernah ter-embed sama sekali.
    const dusUnitId = 'u-dus';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: dusUnitId,
          productId: productId,
          unitTypeId: const Value(3), // Dus
          isBaseUnit: const Value(false),
          ratioToBase: const Value(40),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'dus-t1',
          productUnitId: dusUnitId,
          minQty: const Value(1),
          price: 90000,
        ));

    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');
    final data = _extractEmbeddedData(result.html);
    final products = data['products'] as List;
    final p = products.firstWhere((p) => p['id'] == productId) as Map;

    final units = p['units'] as List;
    expect(units, hasLength(2),
        reason: 'Biji (dasar) DAN Dus harus sama-sama ter-embed');
    final unitIds = units.map((u) => (u as Map)['unitId']).toSet();
    expect(unitIds, contains(dusUnitId));

    // Satuan dasar (Biji) tetap yang dipakai di field top-level (harga
    // "utama" yg tampil di daftar produk sebelum modal dibuka).
    final baseUnit = await (db.select(db.productUnits)
          ..where((t) =>
              t.productId.equals(productId) & t.isBaseUnit.equals(true)))
        .getSingle();
    expect(p['unitId'], baseUnit.id);

    // JS `unitOptionsFor`/`renderList` harus punya cukup data utk
    // menampilkan chip Dus di modal — dipastikan lewat kehadiran fungsi
    // yang membaca `p.units` (bukti tidak sekadar embed data tanpa dipakai).
    expect(result.html.contains('_ownUnits('), isTrue);

    await db.close();
  });

  test(
      'varian yang PUNYA >1 satuan sendiri (mis. varian "Pedas" py Pcs + '
      'Renceng) — SEMUA satuan varian itu ikut ter-embed di `variants[].units`,'
      ' bukan cuma satuan dasar varian', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final parentId = await _addProduct(db, name: 'Kopi Sachet', price: 2000);

    final variantId = await _addProduct(db,
        name: 'Pedas', price: 2200, parentProductId: parentId);
    // Satuan KEDUA milik VARIAN itu sendiri (bukan induk, bukan varian
    // baru) — kombinasi varian + multi-satuan yang belum pernah
    // diverifikasi sebelum diminta user.
    const vRencengUnitId = 'u-variant-renceng';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: vRencengUnitId,
          productId: variantId,
          unitTypeId: const Value(3),
          isBaseUnit: const Value(false),
          ratioToBase: const Value(10),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'variant-renceng-t1',
          productUnitId: vRencengUnitId,
          minQty: const Value(1),
          price: 20000,
        ));

    final result = await OrderPageService.generateHtml(
        db: db, storeName: 'Toko Berkah');
    final data = _extractEmbeddedData(result.html);
    final products = data['products'] as List;
    final p = products.firstWhere((p) => p['id'] == parentId) as Map;
    final variants = p['variants'] as List;
    expect(variants, hasLength(1));
    final vUnits = (variants.first as Map)['units'] as List;
    expect(vUnits, hasLength(2),
        reason: 'satuan dasar varian DAN Renceng harus sama-sama ter-embed');
    expect(vUnits.map((u) => (u as Map)['unitId']), contains(vRencengUnitId));

    // Regresi totalOptionsFor: harus menjumlahkan satuan TIAP varian
    // (bukan menghitung 1 per varian) — kalau tidak, teks "N pilihan" di
    // daftar produk under-count begitu ada varian bersatuan banyak
    // (dikonfirmasi manual via Playwright: "2 pilihan" padahal chip yang
    // muncul nyatanya 3).
    expect(result.html.contains('n += _ownUnits(v).length;'), isTrue);

    await db.close();
  });
}
