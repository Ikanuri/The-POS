import 'dart:convert';

import '../database/app_database.dart';
import 'catalog_access_service.dart';
import 'catalog_display_service.dart';
import 'catalog_sticker_service.dart';
import 'price_service.dart';

/// Generate halaman HTML self-contained (tanpa server, tanpa CDN) berisi
/// katalog produk aktif yang bisa dibuka pelanggan dari WhatsApp untuk
/// memilih barang, lalu mengirim balik teks pesanan siap dibaca kasir
/// (format manusia + baris kode mesin `#PSN:` untuk tempel-otomatis ke
/// keranjang lewat `PasteOrderSheet`/`OrderParserService`).
///
/// Prinsip desain (selaras keputusan user):
/// - **Tanpa hosting** — file dibagikan mentah lewat `share_plus`, sama
///   seperti struk. Konsekuensinya: setiap harga berubah, file perlu
///   di-generate & dikirim ulang manual — bukan link yang otomatis update.
/// - **Harga tampilan ≠ harga final.** HTML ini murni untuk pelanggan
///   MEMILIH barang; harga final tetap harus di-resolve ulang dari DB lokal
///   toko saat transaksi benar-benar diinput — katalog yang sedikit basi
///   tidak boleh sampai membuat transaksi salah hitung.
/// - **Identitas baris pakai `productUnitId`** (UUID), bukan `kodeProduk` —
///   `kodeProduk` boleh kosong/tidak unik, sedangkan productUnitId selalu ada
///   & selalu unik, sehingga parsing di fase berikutnya bisa 100% andal
///   tanpa syarat data tambahan.
class OrderPageService {
  OrderPageService._();

  /// Marker awal baris kode mesin di teks pesanan — format:
  /// `#PSN:<productUnitId>=<qty>;<productUnitId>=<qty>;...`. Tiap pasangan
  /// bisa punya segmen catatan opsional (Item 26a):
  /// `<productUnitId>=<qty>:<catatan ter-encodeURIComponent>`.
  static const machineCodePrefix = '#PSN:';

  /// Generate HTML katalog dari seluruh produk aktif (induk + varian) yang
  /// punya satuan dasar & harga > 0. `productCount` = jumlah induk yang
  /// masuk katalog (belum termasuk varian) — untuk info ringkas di UI.
  static Future<({String html, int productCount})> generateHtml({
    required AppDatabase db,
    required String storeName,
    String storeWhatsapp = '',
    String storeTelegram = '',
    bool waDirect = true,
    CatalogDisplay? display,
    DateTime? now,
    Map<StickerSlot, String>? stickers,
    String? stickerPlayer,
  }) async {
    final catalog = await _buildCatalogJson(db);
    final disp = display ?? await CatalogDisplayService.load(db);
    final nowTs = now ?? DateTime.now();
    final generatedAt = _formatGeneratedAt(DateTime.now());
    final nameOrDefault = storeName.isEmpty ? 'Toko' : storeName;
    final waDigits = storeWhatsapp.replaceAll(RegExp(r'[^0-9]'), '');

    final dataJson = jsonEncode({
      'store': nameOrDefault,
      'generatedAt': generatedAt,
      'waNumber': waDigits,
      // Tautan Telegram toko (sudah dinormalisasi, lihat [normalizeTelegramUrl]);
      // kosong = tombol "Kirim ke Telegram" tidak muncul.
      'telegramUrl': normalizeTelegramUrl(storeTelegram),
      // Item 12 — toggle dari Pengaturan: true = deep-link langsung ke nomor
      // WA toko (`wa.me/<nomor>`); false = share WA generik (pelanggan
      // pilih sendiri kontak tujuan, mis. lupa nomor toko atau mau simpan
      // draft dulu). Kontrol ada di POS (order_share_screen.dart), bukan
      // hardcoded.
      'waDirect': waDirect,
      'machinePrefix': machineCodePrefix,
      // Toko tutup: jadwal jam (zona = zona HP owner saat Publish) & hash
      // kode akses per pelanggan. null = fitur tidak dipakai.
      'hours': await CatalogAccessService.hoursJson(db),
      'access': await CatalogAccessService.accessJson(db),
      // Halaman awal: kategori (terurut — lihat [categoriesFor]), saran
      // terlaris di kolom cari, pengumuman toko, & toggle "Pesan lagi".
      'showCategories': disp.showCategories,
      'categories': categoriesFor(catalog),
      'topSellers': await _topSellerNames(db, catalog, disp, nowTs),
      'announcement': disp.hasAnnouncement
          ? {'text': disp.effectiveAnnouncement, 'enabled': true}
          : null,
      'reorder': disp.reorderEnabled,
      // Game labirin di bawah halaman awal / toko tutup (bawaan nyala).
      'game': disp.gameEnabled,
      'products': catalog,
    });

    // Stiker animasi: JSON Lottie per slot + pustaka pemutar. Pustaka HANYA
    // disematkan bila ada minimal satu stiker; gagal muat = tanpa stiker.
    final stk = stickers ?? await CatalogStickerService.loadForPublish(db);
    String stickerBlocks = '';
    if (stk.isNotEmpty) {
      final player = stickerPlayer ?? await CatalogStickerService.loadPlayer();
      if (player != null && player.isNotEmpty) {
        final b = StringBuffer();
        for (final e in stk.entries) {
          // Konteks <script type=application/json>: escape "</" & "<!--".
          final j = e.value.replaceAll('</', r'<\/').replaceAll('<!--', r'<\u0021--');
          b.writeln('<script type="application/json" id="stk-${e.key.name}">$j</script>');
        }
        b.writeln('<script>$player</script>');
        stickerBlocks = b.toString();
      }
    }

    var html = _htmlTemplate
        // Konteks HTML biasa (di dalam <title>) — escape &/</> agar nama
        // toko yang mengandung karakter itu tidak merusak markup.
        .replaceAll('__STORE_NAME__', _escapeHtml(nameOrDefault))
        // Konteks di dalam <script> — SELALU escape "</" jadi "<\/" (teknik
        // standar embed-JSON-in-script) supaya nama toko / teks pengumuman
        // yang kebetulan memuat "</script>" tidak menutup blok skrip lebih
        // awal lalu membuat sisanya dieksekusi sebagai HTML/skrip baru
        // (XSS). "<!--" ikut di-escape (state "script data escaped" HTML
        // bisa menelan "</script>" berikutnya). Keduanya tetap JSON/JS
        // valid ("\/" dan "\u0021" di dalam string literal = karakter itu).
        .replaceAll(
            '__DATA_JSON__',
            dataJson.replaceAll('</', r'<\/').replaceAll('<!--', r'<\u0021--'));
    // Terakhir: isi stiker/pustaka tidak boleh ikut ter-replace placeholder lain.
    html = html.replaceFirstMapped('__STICKER_BLOCKS__', (_) => stickerBlocks);
    return (html: html, productCount: catalog.length);
  }

  /// Normalisasi isian kolom Telegram (Informasi Toko) jadi tautan `https://t.me/...`
  /// yang bisa dibuka langsung. Terima: `@Barokah3?direct`, `Barokah3`,
  /// `t.me/Barokah3`, `https://t.me/Barokah3?direct`, `telegram.me/...`,
  /// `telegram.dog/...`, `tg://resolve?domain=Barokah3`, tautan undangan
  /// `t.me/+kode` / `t.me/joinchat/kode`, dengan/ tanpa spasi. '@' dibuang,
  /// skema https ditambahkan, query string (mis. `?direct`) DIPERTAHANKAN apa
  /// adanya (tidak ditambahkan bila tak diisi), segmen path setelah username
  /// dibuang. Username hanya `[A-Za-z0-9_]` 5-32 karakter. Tak valid /
  /// kosong => '' (dianggap tidak diisi).
  static String normalizeTelegramUrl(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), '');
    if (s.isEmpty) return '';
    final hash = s.indexOf('#');
    if (hash >= 0) s = s.substring(0, hash);

    String path;
    var query = '';
    final tg = RegExp(r'^tg://resolve\?(?:.*&)?domain=([^&]+)',
            caseSensitive: false)
        .firstMatch(s);
    if (tg != null) {
      path = tg.group(1)!;
    } else {
      s = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
      final q = s.indexOf('?');
      if (q >= 0) {
        query = s.substring(q);
        s = s.substring(0, q);
      }
      final hostMatch = RegExp(
              r'^(?:www\.)?(?:t\.me|telegram\.me|telegram\.dog)(?:/|$)',
              caseSensitive: false)
          .firstMatch(s);
      if (hostMatch != null) {
        s = s.substring(hostMatch.end);
      } else if (s.contains('.') || s.contains(':')) {
        // Tampak seperti domain lain (bukan Telegram) => tidak valid.
        return '';
      }
      path = s;
    }

    path = path.replaceFirst(RegExp(r'^/+'), '');
    final segments = path.split('/').where((e) => e.isNotEmpty).toList();
    if (segments.isEmpty) return '';

    String target;
    final first = segments.first;
    if (first.startsWith('+')) {
      final code = first.substring(1);
      if (!RegExp(r'^[A-Za-z0-9_-]{5,}$').hasMatch(code)) return '';
      target = '+$code';
    } else if (first.toLowerCase() == 'joinchat') {
      if (segments.length < 2 ||
          !RegExp(r'^[A-Za-z0-9_-]{5,}$').hasMatch(segments[1])) {
        return '';
      }
      target = 'joinchat/${segments[1]}';
    } else {
      final user = first.startsWith('@') ? first.substring(1) : first;
      if (!RegExp(r'^[A-Za-z0-9_]{5,32}$').hasMatch(user)) return '';
      target = user;
    }

    // Query dipertahankan hanya bila aman (huruf/angka/_ - . = & % + ~).
    if (query == '?' ||
        (query.isNotEmpty &&
            !RegExp(r'^\?[A-Za-z0-9_\-.=&%+~]*$').hasMatch(query))) {
      query = '';
    }
    return 'https://t.me/$target$query';
  }

  /// Daftar kategori yang punya produk di katalog, URUT: jumlah produk
  /// terbanyak dulu, seri diurutkan abjad (tanpa pembeda huruf besar/kecil).
  /// Dipilih ketimbang abjad murni karena pelanggan paling sering mencari di
  /// kategori besar (sembako, minuman) — chip terpenting ada di depan — dan
  /// urutannya tetap konsisten antar-Publish selama isi katalog sama.
  /// Produk tanpa kategori tidak masuk daftar (hanya ada di "Semua produk").
  static List<String> categoriesFor(List<Map<String, Object?>> catalog) {
    final counts = <String, int>{};
    for (final p in catalog) {
      final c = ((p['category'] as String?) ?? '').trim();
      if (c.isEmpty) continue;
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final names = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        if (byCount != 0) return byCount;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return names;
  }

  /// Nama produk terlaris (persis `name` di `DATA.products`) — hanya yang
  /// ADA di katalog (aktif, berharga) dan tidak `outOfStock` (manual
  /// maupun stok riil), maksimal [CatalogDisplay.topCount].
  static Future<List<String>> _topSellerNames(AppDatabase db,
      List<Map<String, Object?>> catalog, CatalogDisplay disp, DateTime now) async {
    final range = disp.topRange(now);
    final ranked = await db.getTopSellingParentProducts(range.from, range.to);
    if (ranked.isEmpty) return const [];
    final byId = {for (final p in catalog) p['id'] as String: p};
    final out = <String>[];
    for (final r in ranked) {
      final p = byId[r.productId];
      if (p == null || p['outOfStock'] == true) continue;
      out.add(p['name'] as String);
      if (out.length >= disp.topCount) break;
    }
    return out;
  }

  static Future<List<Map<String, Object?>>> _buildCatalogJson(
      AppDatabase db) async {
    final priceService = PriceService(db);
    final unitTypes = await db.getAllUnitTypes();
    final typeNameById = {for (final u in unitTypes) u.id: u.name};

    // Item 29 — selain flag manual `markedOutOfStock`, katalog JUGA baca
    // stok riil kalau toko TIDAK mengizinkan stok minus (toggle "Izinkan
    // Stok Minus" OFF) — supaya kasir yg lupa tandai manual tidak sampai
    // menampilkan produk yg stok sistemnya sudah 0/minus. 1 query agregat
    // (bukan N+1 per produk); toggle ON = auto-check ini DILEWATI (konsisten
    // dgn kasir yg boleh jual minus saat toggle ON).
    final allowNegativeStock =
        (await db.getSetting('allow_negative_stock')) == '1';
    final realStockByProductId =
        allowNegativeStock ? const <String, double>{} : await db.getBaseUnitRealStock();

    bool isRealOutOfStock(String productId) {
      if (allowNegativeStock) return false;
      final stock = realStockByProductId[productId];
      // Produk non-stok/tanpa satuan dasar dilacak tidak ada di map —
      // tidak berlaku ambang stok riil, hanya flag manual yang dipakai.
      if (stock == null) return false;
      return stock <= 0;
    }

    // Semua satuan berharga valid milik SATU produk (bukan cuma satuan
    // dasar) — mis. "Sedap Goreng" bisa punya Biji (dasar) DAN Dus, dua
    // baris `product_units` berbeda utk produk yang SAMA. Sebelumnya
    // katalog HTML cuma pernah menyertakan satuan dasar, jadi Dus tidak
    // pernah muncul di modal pilih satuan — pelanggan tidak tahu ada
    // opsi beli per-dus. Satuan dasar diurutkan lebih dulu (tampilan chip
    // konsisten: dasar → satuan lain).
    Future<List<Map<String, Object?>>> unitsJsonFor(String productId) async {
      final units = await db.getProductUnits(productId);
      units.sort((a, b) => (b.isBaseUnit ? 1 : 0) - (a.isBaseUnit ? 1 : 0));
      final out = <Map<String, Object?>>[];
      for (final u in units) {
        final resolved =
            await priceService.resolvePrice(productUnitId: u.id, qty: 1);
        if (resolved.price <= 0) continue;
        out.add({
          'unitId': u.id,
          'unit': typeNameById[u.unitTypeId ?? 1] ?? 'Satuan',
          'price': resolved.price,
        });
      }
      return out;
    }

    // Hanya produk induk (bukan varian) yang aktif — varian ditautkan di
    // bawah induknya masing-masing, sama seperti tampilan katalog kasir.
    // `searchProducts` TIDAK menyaring varian (beda dari `watchProducts`
    // yang punya `parentProductId.isNull()`) — filter manual di sini agar
    // varian tidak ikut muncul sebagai baris induk terpisah.
    final parents = (await db.searchProducts(''))
        .where((p) => p.parentProductId == null)
        .toList();

    // Item 79 — kategori produk (SUDAH dikurasi owner lewat "Kelola
    // Kategori", tidak butuh input baru) dikirim ke katalog HTML supaya
    // JS bisa auto-pilih ikon per produk (kata kunci nama -> fallback
    // kategori -> ikon generik), tanpa config manual per produk. Satu
    // query agregat (bukan N+1), pola sama `catalog_share.dart`.
    final categoryByProduct =
        await db.getCategoryNamesForProducts(parents.map((p) => p.id).toList());

    final out = <Map<String, Object?>>[];
    for (final p in parents) {
      final unitsOut = await unitsJsonFor(p.id);
      if (unitsOut.isEmpty) continue;
      final base = unitsOut.first;

      final variantsOut = <Map<String, Object?>>[];
      final variants = await db.getVariants(p.id);
      for (final v in variants) {
        final vUnitsOut = await unitsJsonFor(v.id);
        if (vUnitsOut.isEmpty) continue;
        final vBase = vUnitsOut.first;
        variantsOut.add({
          'unitId': vBase['unitId'],
          'name': v.name,
          'unit': vBase['unit'],
          'price': vBase['price'],
          'units': vUnitsOut,
        });
      }

      // Induk yang HANYA punya varian (tidak dijual satuan dasarnya sendiri)
      // tetap disertakan sebagai header pengelompok tanpa harga tampil —
      // baris "beli langsung" untuk induk tetap tersedia bila harga valid.
      out.add({
        'id': p.id,
        'name': p.name,
        'unitId': base['unitId'],
        'unit': base['unit'],
        'price': base['price'],
        'units': unitsOut,
        'variants': variantsOut,
        // Item 25a (flag manual) ATAU Item 29 (stok riil ≤0 saat toggle
        // "Izinkan Stok Minus" OFF) — Katalog HTML statis: tombol tambah
        // dinonaktifkan + badge kalau salah satu true.
        'outOfStock': p.markedOutOfStock || isRealOutOfStock(p.id),
        // Item 79 — dipakai JS utk fallback ikon per kategori.
        'category': categoryByProduct[p.id] ?? '',
      });
    }
    return out;
  }

  static String _formatGeneratedAt(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Ags',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}, $hh:$mm';
  }

  /// Escape untuk teks di dalam elemen HTML biasa (mis. `<title>`) — bukan
  /// untuk konteks `<script>`, yang punya aturan escape berbeda (lihat
  /// pemakaian `__DATA_JSON__` di [generateHtml]).
  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

/// Template HTML statis. Placeholder `__STORE_NAME__` & `__DATA_JSON__`
/// diganti saat generate. Tanpa dependency eksternal (font sistem, tanpa
/// CDN) agar tetap terbuka sempurna walau HP pelanggan offline.
const String _htmlTemplate = r'''
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0" />
<title>Pesan — __STORE_NAME__</title>
<style>
@font-face {
  font-family:'Hanken Grotesk'; font-weight:400 700; font-style:normal; font-display:swap;
  src:url(data:font/woff2;base64,d09GMgABAAAAAIeQABMAAAABFMgAAIcdAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGo1PG4GjKhyJUj9IVkFShwIGYD9TVEFUgTgAhHIvbBEICoGCBOR5C4QaADCBvhoBNgIkA4gwBCAFhlAHiHYMB1vUAnFHdLK0B3ATRe0mVdm2yQH8my0YxybRncSiNvpeQrMREWwcYBa2xxv/////2QlKZMxPqJe0pQCq6pRtc8KLiBSmttr7HH30rjQzmbCsiqTCRqY2rb1VusM+YThnF1xwSC42tWSUv5atF7Pe7l4r9yjbu9n72Wvlnl8uFJkfLiNUa7hMn0+i4awukypOKJx4lXrbTNNpSidipNazYsEZqJkjwzxFOvVIRYS+h1dnu2E66b1eINj2MAmU+8GPJUx01VEvu5rO8Xt18b6F8DA4OH8GB0PaePufVXsL88H9L5Ee5e7XhnPMsxcneHWfp1vtsJTpmI8Fh1LxvKOvoUQgwILWA/Oib8N0DH0osIF5LwpCs3palDp0qcMO5fT79Nv0VYDdEh+GRcb1yfPP+/d9P+baBxf16jVRTVUDQPgBRA7FyMoA3J/n5/bnvrcqogeMGpEbNaLnGDM2ELEApWTUY+AIceAsLL4fsfh+P9/ASkDEyMBuKv1HXeWTvmTZHnuGF8gLxL66/LIHDoNl2gOARagCVFTYpc5leH5uvRMURsWy//4igwWwkSWj0gbsxjMqwMgz8e6svEqrLrmvlvZFRmRmATcL7bFlmGF9e9gLSEekd3epZ/9xT7uHG8HxIw6zzbJarcaq6i7ITJ7/fgzWue+jNl2mi4biPp0oybRCJjE0SJGUWMk7G8odXqf+/5FkW4BkyyhToHbaR/CRJxrGP1bX+TDsb5nesCDlFjmAtcOFgKfHe+3lUqeA/6X+10vlX9C/kFJqIDL4T5ky/SnTm5zLlGsDBAgAHlqbkJfCYtRWtoqo7cUNuHuGdOv/f2BZ0bsmR56plI1y2fbV8n/RuB2Hw6IJmhCTiUxMSNB553r3puT05E2JP+cmJKmTY+p9IGp6BcKUksKAwHbvOvJtSzyOu0usH/Xo2Z7skcM6gk38Ep/xBY3J8iXoHRBezKtT13ZZlzrgGJHUqzSWD2TRD0i4OTUj7NylmDT/BQLAE5ZaMX6avd39HThwK6YYGMykeorh/RnFeZP9r85KsuyEBxeIu+1LX+ZtWV679RFWsxhwyLJFX7IQvmy+PgZ9v92dA4lTqapTm1A+BMD+/EFt7i8ulHpzqwsVrvAHuZjTpKQ9kOpDxjju6lG3A4Lmm34HRzhCLIB/1RzWbXw7TuL8UsSBoLRUrG3vpwmCdEMxlCaWcpfHAfnA6/+/zbSd+59mvaO/9EYL2irWsRVgBXpZMgSIq1SpZkdLs08yyaQzIdqVWea1A2igMgSnR1wIybwOQwl0euSiTlV16dJ08fvW1O7ef9m57ARQFQMk6x0eBqYcrkIUBkjYWl0l+386y1ayvcuBA+rCUDQA0F9S5aVotP/P3F9rpNVZI1kXy443K/sIZB/BWAf2UbwbdACoqBjLAooqdQ1YVSlqrgJpLTIsNYqFdg0YSw3TBc2jv78v1ez6HwVaTTkBnNR0/Jj46NiT7incHNKe0nXr/tmNZjcA0vpokpoGoNAEFZpNDfcDlMpNeFQWyA0UJ2u9QdKGHB5Ah6acWtzE0SbncFqfNkbNxnS47F5ve7n5uOlkm9gUdScga6iO4tggwBm/Pp6t3/ZZ9Sv3YhBpRIpGnCw1ScRNvanxQgxf93k798+/5yNMoaLi8KioqKiICI8wKiLCiAiXiIxFdJ+/5eznIU1lxVJKxAihWSJ1/S6HuxqEhHN3SR/RwFdmnZUx788ZAaPXMenYdNMNFJByMU2pYsoLMe48XKNf9+5LInC7gfWAv4NsxhDVUqUyJZLy4wihqlRlHr359rgHIcHTiQKx/EyhoA6vHEWv5EVc5PvFxSeCa4SRKdmNQH4ypGmfZxZEDlEgIBo6SKX5MHvsgbnnHswLLyCvvIJ06IDr0g3XZxAeDGGAQzBgK2AJQtXBO0NVv4H3ABBkEAL9e5FBfyDo1wf9CGAXYItGYf+/dKHYX7lAAYkHfKWwLcplmrymBboaxbsnu5W7nQf4kB2eH2fHxcc9x32n9JSdytOKjGR1WT3KEKAU9WKMJQZsccBXuJJQwgmQC9JICQWqaKSVdI49sWf2nyUcc8mBG37F73jKy3md4AKEElYEcSGKRKmolCCtdDLKC/lNJrJEtgLAJ6RQBGVQAbUqUbUatNf5etRcm/+m2JRaZY211tm/ttTWuOh+uEpX5WpdgxtyE974xKfBhySkoSpexP9x5UwFiVXZTVgQJkK+5BKCzjMjezQYcEmfJe0EBUVtFPrE5TY93tbFdJwPmZRW2jHxkQyixu0DKas6ra26hna2I8fDfLPWmpld2Py7SvY4r29v7i4v54NA6lyhljSKnIKqRNny5CvgFNAQMTQsjkihg4iDS8QSI58ZNpfpk52jR3bs5nM62yAukhLGuFmIrm5/vVP/7OP58wf2rKi1e6xtrFSb2m93BwmaTTstLgqnVNR02XBhoTSoZmnHroN0rFbtTDaXpNVpsz9f5smtO3f/g4jYuGhScko6ERPwiY8DARwRIVER0eny56369O1VW1epNre0VtznPft35kyXllfGCV74+nsURpNFyquoGdynQV5YsWodll1uhRWXLMU/iC1aAAwsHAIiBIqEjAKaG21sa5s1Z96iiakly1Zsap9uHl4u33rbjVt3HlydfvWb//hfVOzChI2c/6mcLFvZTqRJnzFTlmQ+S7WtdqFsSWlNY769q9nTNbZo2VY7bCgOI5LIKSjpM5Y0SigSl5CUM7UmI4hwgsXW8w8sWLJizcjEhsWQEeNMMMks5rI2e0HHQuLgSMjRwTb+kpFTUBNJNBQhEQlecOfFycV3/IwIUUJiRIKEELE0GTJlS0rJkUlpLSxYbpW1tSzLsQvb7LZpy77YeRc4xagYuV4x9rzIzyb5ZDWdTb1wdjA/KA6XR9OTq2O2NTsTtY3rwJhvGuZ8m9jhfD548T47gh6YP3L95vpd6dkuJXQdYBAEFrLRR8AHAn3re0Zw0WjDB4+spmY7ceHGTjZw/uwsmAUEvPSl3mi1u73pbL5YrTfb/fmKoBhOUDQniFK2ZEXTLfvg8Oj45DRDmFDGhQSljXU+xLPzi8uroUuyokJNN0xk2Y7r+YwLqUDPPrWsM4Bgn3ED4KgPAQLMuFDBjjthXCJwbrtaSwAHCbAYRU99p7v1+mIC7B82w8B/euvmwBioJvIRuLP6binaZ4cxUPAgDM6r0X8HEAIL1RQThPPjxhIP7v6aO78zew63eI5hHPY+ePk8BZq20c93D6lw9+fk/OCZn+HWTBsG0OLwFGjqpm3cCDSnp+2gDcAI5u8C81eB+Utg/hCY3wTm14D5SfdkLcIAFhJCkLpnLZDRh8yUzSxo8BkEzP55zyckb99o0Dx8thw2O4pFt23crGW2HGWGAIyQgwukMapbxIfd74gniFuI84gBGbAdUY9YGalCdCDqUIYc2IvLEVwEFYFGREf/v/Mz+qfoO4JrOIujkd3RG6NrcrrotlAqEJsX7YvWR0ujOf2x0UnRwIr6gGfekwJY3Hr55yVrPDruHxvHNePysWJsGWvGojFjNI/ikT0Sx7QxEtbwN17hu+I3hkvDkWHvsHGoGxYM5UOtxOYNvkE/SAc6sEgygNV/wLPunvT3+nP94X5LXy/dreyr+qa+qi/oAwI7tBAXZ/foPoFMIg10X7v27k53SXAEe812bIzUdAu6cqi3OqVzdsqOH0vs0roYEuB/j/y2vW1PcAsX0Izv2P3KN7TaVt10raFVtLzma9ambpxGbkkNYH+sj/VIcAPncLS7ndVQK2tRaavO56aVGzBunLy4ha84NJQOeCyBDcDVloNUrTk3fsDSNtbY5bkaLPQDnPYeyBkLnlY8MWSsDSAnhpgFVW1Z2Hm/e/ArNqnDkARCEjwgR0pdVIovRCays3fHDfAhuGb3JXqlhdfmSQOVFHsjRmMSG8nzCwDOwaGjLAL15/0N6IELhDrFp/1Sp/i0DddPF5OpEQpLLoFIJIyEKzAqXkRAOyGA7tP93uRiOurUsXtPXTd/PW2uhOpk8Ng6euXIsUsHXZhJPvDYjR049jkW8vzY3E4WdnKwPPWUGy7AUSfs9VEeKNIgYxpsxq+xAhxzDcBoONOF20fOz6HZrON3pMViv54V5zkb+mLvgnHgR7b4ED61F80Rko1rh5qD8ZuKykWAirpk1cY16EyoHDHhZeowbMNaEg5Saz87tKoTfWqblbzZcSO11k9uktOGHypHDA9GRobB8linBHPj53XyZ88Nx6GZ2yUiJA9LRXktaVgaef2OBCBi+h7yeAiEEVN/fJWgYxrmcJFyOARZnSkjToEiV/CRdUSnUxmZDt2MA7ukHFtOSjJSaEKcYkqhFHklCWNh+IGdtUZMs9ht4XcRH34xucgEBn1L38JMLnJh/iBKgEsZOnUmQgK90ieKiwgMxLeCTyXgDOz9f73x3u/fWyWX77vVij1KMD3hCPT1MT7BUfSdpMdVCUIiqBhUxeTDTijm/mE8iW4Zbekeih3oLGnjJYxe/HLAWFUyI0GVPl4TlKPoFfGL4ITP3hxFrtITJjb5RQWxExOKLf6qkffepBrtXlxSL2bdaUrCg0w4G5UCKcxWfM/Cg9CtycfUhiFLdk/siG5zls5Nb8Zpq21IVw+kg6+ayMf8lokuZCktH/9aafl4QjxWYTxsJWZ0cU2N/IsDMb3Sx8XXsLxMrbYEY5K/M2GYsS4ai4j5tMXEgr3kdFEOgsWRjCNnPZ01Z9m9zog2XhVGNxNXJfUznrI1cV+t9mykLT72K+96mjZh2kca0v8ntFjJD1dkgfOzS6+gG8BQRPft34FABkDeLfirDyqu56KBP6q+7W/XAOcAxwCHQTyAbX/AK22CQTkDaNuryMtzNoI/j078D7btBn1U/O8D/9ev2B11+mD385/pVz/m/8lgMMDQYPtfgwHb+T5SsO+/4gR4CwRw8AWwehDAcY8AjnsJAAedAXDQJcBiYNUSwOoB0E0d9WN3dZfpLb35uPcUKY7Bm8iloxWl4Fy/2Kebm+/uyPWBAmHt08dTgtaO8mPY+00t3+GeqxbtdSTm6kAUJOn27thO77tNnjAILqlgQoQCGIQpdXYNOwMi6KPMNCiEeSV9DiEYAmHV9nyH5+3NbEMb+D/LN/s9B2xwAyz2xV2kLX8ymaz0Zh78LX4WMzP58wwT+IpXWXQPfzd9N6YjN008+GOgej41bzLmTIMpGzixqdQU5pTtV6S+vN8OisR09HMLUREPhaj02AQvAm6wd9+vK4q7ITZxjMO8SPgNPE4kCkYm9lZGfsgD3juaWUvgW7Xv0M04KPLXYwG56YMRdOPNzO7ocMw7iw1Xow0ElfN5uGrtK6ay/WxoiPnMFKQGs3XgfiRwPP97vGJYyNVXW/4+9KtONfLTDdi42PjBvASeOivf3qwTfelPofQ1DrAtQ198471PD31MLkUwXCX2PODPBXlgGUBZc18CCg5pY5RMB020EoI6oBViwJXfHR29S1xcRVItWygghPrmax39zcx5xc6znWcZj4xveIzqabrtsqkG5G+NqtpayBCRLFrOxxzYEMppsGNJZ7I56+DklcmsYyfEeF3tETYcrgWTg2NUe6G/BIfasw9knNPewIXdKlf8t6FeX9e6nQLbHc0jEN4dpEwBlhE0EPlgp61MNyXFz4T6P9odxbWNX5vjQEPkhw9mcGkIuCz11u8KclOoyhvW1nwYqcXKgOKPrFgOLChKHDsaxgOKMI0tF5i4JE77bmBh1sjnMjsV4/Pzgvvgo8eI9y5j5fOP3hiymz9bfOzWlMl2k1J9yaAHAmh+5qY/j8+3qFhlvtgEJ2Q+5hERAtimcXHz3gAbfoOqEB/hanT20DeX1B2OkVc2fd7Pk5+RI6JL953mfQBWB6N5eB5u8SdG7+IOh3ILUzSC1c0d8vE5cxNPCXxOAOve6wqvQa7BtH81BbBUjSYTcrw3d9aLlxYW9DRg1WxwtUenSJC5PQAjH2KvXuuum90CmYNmtg5jFUkLshiZdDHD75ru3GjAq06/pjCdmFyuKETFckez4G31xi9m7vShZECyvYBtzjvszrUpqJZJOq8nw3GBTZbmBtV2GTV/HgawBB2mkTskmqOqs7ZRznIM25L+Vts2XrfuoGC0+mS0b0VNMK30gElcZYIAhYYUBn03T3YUmeGuRC0D6df7KgTkJ0UNCZYIYIa4uC6jp1WJwEew+xjqu7rhRQGy/DD1Eag95riAVvrcFNOimZw4xI6CpIiqRZh5lbwXFdXUSY2SMKYVd0MDAAIkBFlYlKjFkGcBX/OGOkurtXpz79KMOHmXLT+VmmsR1cDXbrW60F8E0cbtfU107OiPNurQnTk6fB1wVHtWd1lL2+bFBrg7ewMbaMQasWpV89C4N2KhNwucEJAnr5Yx2aPJvhg2PfblVOzbo5ZwpyWLJXpzyFWfDuiW0QGE1Y0m6FnbqnHKfH37lZkrhjqwCj2PFrRsJ3TLEFQwW9RvildhVXumM+RbF6pI4FZR5YJmBY9KYvl1llPd8gDiVWvKARdjhIP8gEbUVE4CoENeQmApdIHpMnfEolWGlnqLE35e2p+V6n4iLP61Py6pz0sik//ccjY4mQxtOwlYjj3ZHlim6rP8Crz1i6f5/pd8BTdl6n/mqZnc9RSCbr6qVkTLa8NDk1NI42HyUAETzvOBr2yu5+1KXgtFeTU3eXGapxdfZh1L5YGIW2PtavYo4chcbtnOMJx14QGChn6ueJrmBnxOtzmrEK1txQzzf91lHpPktu9m5jgLX2SPHBRG8gYqoCBHFBDXCQ4X8ub21eDRDh1YCoVGpgUxyQZT2azij+xSx6zKlc9KschMb74MHiEsoTvaKIZ+LEOsIYyr7FX8657HDAL3vGhnPqXHtu6JN+LSW+G2v53jHuArR3ZxoQphZgW0feYct/G2Eif7F26WX043RbtBy/BWt+xugg/MQzd6nXZmKIzJk7sulabjSIDp7Q2CzPuLTv3JeWqiiByEnrg6829T2eJwIzlki540jaDqnaa5Yqt+d9bwIuSyQfguYfD3+6DlH/XnTD8B/8zPM72NkoKoF0PSystxevy17vmXq5sqigJd8eRCq/NvlNRJ96le6IhyfV7RPjBSDT/nLgXakRaEYsO1/ZYmP8vMTQmtISm1+JQ0TT9iQyIJsUb1WQYaCPDiqC5+aE1rseO5kQ31VKeYAtheMFTFhmWs4nfNTrlvlX438AByKytc3kEINtQk8sp17CjBTOQ8gffvU8RTNfpke6jDGhF4UIPCn9EqsqmPHqr1jJsBmw7B8XqJmuorRI+CKNnGbdNlPOHkp0mKEirMLRtjdrSyya4UtgadkdMtTQFjiGWQbuww9tq+clVTF6mdCCSGXLuwud2qryVgu9/Ut7GjvFWykIMUQ8lcsZhfCBIDxasdgisFGwavV8Z3xsdJAMvSXoiJEJ17DkoZaraSeAa6RQ9zEWfv2F/TzkIgrCUnCGDthRyH0NW8MLCN6UV1topZIQ27eY8LHiUC/gADlM8DidIW3bGID2PPAqX2Uh3bJpJDeSP7D28fG94yG6sybNyL+fX3OwBWtPiJRBdiUiSrGrairRNNh42oQNr55fdwDLseZjf6RItJtI4O8rCZootoFE1ZVqSoomZzxmC2DK0/5+k37B+FDzfYHrhaFzsb8na+0+mBOwyObDF8EGMwmQ0KMh3RsN/jEa9cVxZf5C42eRA4ydmRPI4SXDN7HgiacfXQGf806I06qsaTzQkTdOiQY2LO2+PJdJL0OsTNxYvsR+SHFNw3gp+mG4ffuhiRzRXgeAQ4vmTI3Xa4O7k1KRUYC0rgL7TUByIYCKs/LbWqYd77ELp3wlOkFZVe4qFTcXD+lMO/PmNqDjUDnelm6m07iXjtKyP48FNVmQ3tnWDUCUJ1xcFGQrD51U6fimwF8jDSzy51+0Ah5RgMUT5WNzQUVcS8aCjb/JeUUcMiRo0TeCEmIzc4DX1f3Wd+jfjeUY7EJ2sgFV3xEV85jpoPnxU851NGse5YYfQ8I98hl0ca/f0ByULejUa0cCBjDAybQwbezoMd4cMOhGPw2jDt+vpFQfoGwk3QT3uV9fFdDhG55LGAwazVywPyExlZL4+4a/Nyvrxx5jTK4qLoW2ATDtT8hsDoxk5dX7fjikn/4dHYePyvLTjPWbpzTVrDCmewA8TXlkO7yx7dMOjlbUU2UB0qDqkqUSjWd8w880V7+ENmJsYlbIfJkdp2efNwXwpjt9oj6aFVZ7+2rCBkGp71Z9pneF0XBPThM3jcIOME3UI6tXQksxNQyxyl3c4AEehgwMW1yJvSFAjlTyvyAfWbzkNdUQDfV74OuWT+KlNqtm5XlpvcS80YblY0/ICz3huxv8vRWjieb6HhxQnZYUEQqaYtP8IfVkOIn3zWX+Bz3QdsOvKmmYaU0LuXFm+fYIjtX7LxIqVowbH2mHYPCGs4D3rrQrrFuyXAki5VPi8kDgaATj4Y7qyut6Bfn890w5K4mcjf7xJXnuN8FyeBIDzS80wHYKwNw+H2mo7UNQvsC7DD9yOL2OQiIch188NoL+Ag5LGmab49PfYyTF5kEL7jLfZwBDbtMeTHgAVM00Y72ZM1hPCZSmHgTVrXES1T1BmgfIoKXyrCltmAZHFuxx1gdAooFqSjab4rLGhsDxLzPSLkinQo0u89E4PBcDt/G4uiHgPUUJglBrwnhGG/mHTTRCnWb4nHtxCu0b1s+YzxPwsDW6Y3QUeLgDBF1XFmN7Lx8CJ4vbVMrBp5S1KZp8IF8n4MhFXmH58d5vgxGj/OCIz03rC4efL9Y6XZDOHl/q375HX5D3R2W0zbB3qPLdxlcQvNkg+kiJvJZhxypQi6iVOQ933GUE+klAsnqVC0EUlGZCJgtA6Ia/vjolPqY5qqD/MVB6sJOlCTC6LQefvABTy/vhp35Y7vZn9sdbAnuq+L9ye1oNM/NEil3dO3HFxNyZwRMEVaoY0pnwukUzriyMGVQXLwU1Yn958E9nJH8gqWQHmTHGf3ARxxMICbjDGHBr9B+3+tnFIK9EYqPXrcMPHLaklFRXWymJyicLsssVP1s1v3p9dU3m/V1lCtmSjgICbiGfBnRjwz8pmYZyKf+eyBC6lgFdB66AtwHmSg7qceoARMWCV4CEqg74EVHIDlgXfQn5AdTANtYBH0C0BCA+ANrApMgCJ6w2WoAhyFhqHI3sgBETCIR06wHgTBOigFygafgxQgAuOBF6DAbrABhKE60AHiHs5hULBSaDnYBCIeEWOMdIPM2qcaN6liFn47WIo9XrqoBM1syNXBOddUSWOinoCXzIoSi6Cvjwc/jdv6+NWPU6P3xB3/FWmKf+raOlrzHp+N/PDov08J3I6L0c85KT5+7YY1EePwxIirfHTN9VmVTFCI7gK0iYHKQ5+cEqcCakna8cGyIeMaAHbtlhpzJmzaPb0u+ZQ8f7GRhQQhdm5QcWQ/S82MEJcl95w9ttxcgm8nPPrtMoITO0jdrAh25PU3OW68IsGnkBamyPlPbuzQbQMw95dP8tQGG2zt+s9WKna4fThNFkzhqek8sTr0toiDPO4kOgJcrDFOP9i7FZbs4IjPJ+5i/8OU29ukBIMNrDybdVIqtfOo9aQVXzYnbbHsQTK2or2sF0Oqfmgv06hDQZSxcX1qZrTWCqzBm058vDZF8vofqmWncsEudvKc05x1XFw4lUkzBqwwJ2nTozeMJu9uZYHtWt2mnmsc9/y44ookgZma/mV3jXVJ9+vS0JdNwGXnmMZd26t+iXD6M0g8a3I/6eYb/zGFiJ6BfWIdt1SzHEKSeaFhD6eKoGzatlzUgU8rwRO0Dd4ZWp6RNHvSBCbLboWCf9x7MCg3puhscBh7d39nQzQUNQAHabtvMHHG5K4ubUsYO3drMJz7Q/3ZxlqzXvaZ3LnFMlmN0lsSF+paDhp6Ioy9KiA2Rqpjl21Yy4kcysGcwPHaaFue9xhwMsexwqjlbb7q8K66l9t+v0BiR/gxnYBaFG+1muOynJdGS/cUFg4KtijE5YyxX4bI+20EnXIeJm8+gPfBJloi5NMYabMb8GKMirwDugA4qDPBiwfZGMuPjT0uk96LjViy4MeUNRu2BAA7A/tzZQVsTr2t8uXGnQeAvwX7O803vW2YHPI9TNiGBVudkDJud8DE0u7ZOIxxGSExFnZkEsvEZ43Khu3YxvI4ckPhziQe7MSLhbzZkg+ziWJNiAWgCmRnEjYQFOsiWAiGUDYlZbIxfXMlE4tDLo4thQnIlML2VEwTz1YSmC+ZBVJiudKp4XKYLJc95DEun/kK2BrBhgrZnSbWXJESSCnTlbGR8lgvc8xFp2MLlWyvivnmMZee+eYz1wq2sZZt/M82trCbNvF8ifL1mEEaSIFTdmuxueXzy+ZrFpcuDTi+GV9hSTg/OFfMts6EjRNswHT7VDwZmHiMM4eXg6z/ox+HmO6bbk0nbu+M1442o4tW2yLbCOxwEXiGcsv/2Z8FScb25UH63WqLOA+G/Xys31YwW52IQKBQjqTiuT03E0nazyVYgRIhypST0qkkS0nk+bw/ccjCwJoOVGC+CQLMDtAElo9yDFiBm3xffHZHli695r/YQEX2mM9PAejsq745k61f+oI2WenAZo0PyarIocOGMW5t0xgYAvvKaw2luUEYpr+HvGhaJ6jXzPCUSy6wI4hXO1I2oqBpTKqsiXBNFUi0NiSOpacPYXclz2YC0Q11SuvBj3BPKbQjzfxNZbds0dpiZaXZ1co2n1MlXl1Y69pP1Ug4oiWJA2B+hCYw+W9TaVXN02xoEVw7RioQ1AXwjEKwtJVkK25khIvIXTB/AwXSXJwxpMbrkNenCJ1jepaiYlLUA0eEChKsuoiAIz4jP4SmPW3T+Yox7QNl4Q9VmtZuHla0vsAjWRqwI42hduJkWAnlMQW5EBNtO/aB2ceDLjsaddge4kh1uS67dNXYGsD2VY1zB8rv6xFx+rIZ3MSVTJeCxooWsBK9K+Xzlx3TTgVnrz4McloKDpgjsVviSruTP7XSY5xsnX4Ubiy52yaSlDekopM2RQajp5+L22n2f01lSMemI3CQCtPm0AfxpMa3KVSf5WXnCWVHUhqtt/K23Vs6MP2nNMKvbUaQtQOaQGX0DHT3vmJ1MNuPT0dqYjCcRLhm+7lkygaS5gfTLWjq6a15FcoKttRq2rsOg3mkHSUP2PhNFtGZED3bOtDi82wcflX1fJJ3dcyFlVBHWV0NVWeqEf0F3Fl5zGmq0SvqTMX8RWmVl0TQdbO12+cL1Q6U2ea3cu8awoJbfvhhCOlUysoqhs2VOn10Bc69d1P8NuMIn8KJC3HHcSN5PUmUVahoKlAoajpk6BSRjxdvOnD8MFfSCMlXyJt2LbTYmE4Bc+pi03kgrHM1fSdVU/WGHlFKhcLm80BRde1cVjgsV95i82xSM7clIWRKx2UUilt+KzONrMmJnEUE3AwFN1NbDhOTSyxqZG9CL9yZbCFnVsMQyNVT+dXXIbqtRmE91TQt9hBdkkvO5sHIHajQUg65tr2FLkxMlBiRCEGRZEFsZRvM7bE5n+YZ7zT0EWcbZ9E7Eumj23bAAT1zKvgDLc8QTFD7r6UPR+OymcDYAbw0UfFZ70EfcCjUVJNE/m5TozTEJkOsfXuXiTqoFtho/SRpsT4LakUvuNZ6KxT0X6GsqYIGKUEqVBUGw1Xja5fsnsa4gEoUX5eHDCoZVrQBy0Ncm2Yc5/UtaXMlAm3JqT6qBTmwjifJvUfqSR5ySVI5laZYFDFwnCrXFU0GkqbU+GBF6YjJDx3eDNwiGFLLxfw0Z12SHM0J+9TWpgNR9//HETKDyFRxdY2hcUquvRZ3DTZtSz1tqSh+QEsE+g6CmhoQCp8QJsWqhkw04309zB8AdVnydJZxSjAzgxx13tNDOq1WZY0QKjlY0y5DCyt68KBiXpZWYHVE5nOsREEF1EjVWEdojSUvfnPtGPvqpfJ3UNXa0ZUKtl2ttqvsBO2na+qPVSjULMErY20Y5LJ64G38WD1b6niqhp+r9p75DzIMeIqyjAoEqM/RlKRVBNyhrOfUmnom3bGqIZpcJmSEOLrx7Qf5v02Xkg5LQs02eJ3GSVXLWLqU/SfBkCWWwUrkjIJPSFstptLxJErfKUQx0xWPKmUhwYW52puTVQQb1BxJb2Pu2yxgaArqGGXggCQY6IP1w9K8TacLnj6XaHQBrg+1clP+lnd9WR9a/KpF+OXd4lPXFX2veefIazlB2dIRqsoOIirarbCZRpqWGhTVVK9sz3F5Aesquf1q6Avqq9AU1Wtl5DltwKEy0rrVCS1e9pGiZovOkANNIzJRyFNaNNJTxPCe/rbU8aiGKdWs0nNMz7cq7Gv6IK12B9ScS7d7yeNdMNgoTXaDDuC6z4VAjB/GssShKvVybLme9nMjeqJiFfQbWngEvAgcCtw93fW/lQPX0HWQjGMXSaIdkwOKAJOZi8cw8GBpc03QTasc5lxLVF+jQO2UOpKGGiKh3uY1uA9TFmANcMgDfVWnIlWmNIlzazHaWo6/pqllAPjFYRriokZGRkCHsdXm3NFlBV2OGW415xGtsKJY3p6VbXwCPGVFxUWAywrdY8SQppQNTsumWGGpzRmpqW3OC0qwfE8zsymMwaK+88X1Tk0iaKPtcx1oIBwRA6r5fkH56vxU4cFM1ZmjTHR5kbHwgcULBpgZyPbfbTSfd3kK4+hLxgiw92xUYsIbziaEl16NmhYuvR4lr793XTmu6sY4aTjzjnL86Hv3upzh75YwVoBIsBjlAAVHwsRqJ2YkpiemJaYmppjkGg15LGTgWj8oZF97bYEGtmh3vu4xUVgAtf9nzWqg+klOdhronxRm5ENFQ1oiSE3plNx70rOSgmJQAWHQEJMYxCU60YhFVJgXNkaMmRAMpSOhrC7TzHaL2VpLbxxewroY1NNFc9ZEG3noYf8RX8MaZQ3EL0tBd2aeACdg+leU+Xswx3Xsee++IBOyYc4Qy3yYFHqYBJUwSvPglFJUnQ8lQLnjviIDc50WXrQn8kIM+IYY8XJ53hiWX2k94MA3DWkjrrcZWXjLFD5lEdnxbdcyxnA3FMCmLPIXYJzTzvkw1qajMMIQx4iuU6Ym4RgSCVZvr9M+o7lDCrINDYOHCmBa7huxZXtSd5cSpUs4xVaKBV3Y6gRr7LRt6/KqJ5GhzgTYFF3mQl8i7DELO08d5d0YsVbFbBRMbAJb7TExxigQJWD256m9tIP0nfeCGRRqsirONY2BqzWm6kPxv/pk0dxweiJd05DQMxiimoT0CXBDTN3DBr896DLtQedbKb/51IuA0DsiQO0NbODmq9vo8VUc3kE4dyiJX5ne0tNw8iZFDBR67SKGXDE+a8SZw582XoEqGVxytKpojp1JiU9/ZZ7yQ8doV310l7FG37QANy3TqWFOn+Fx2jM3vtc47Zp1UStkJw4JC/PUMCeIsB7lL5E3niUOzwplIbTKOJ/BUUy+iMXLoYRcIJdv98wRgR5kXMYqe5wiEKBz0llZknV1QtEocBENFbx0flpsCUEBELgfpUySNCkkREaigSuxJeBcCNwIKRGXdMVSVaKhJa9lUrkWyLt3msztW0CcfIgrqV4RDCmeDqXadOtMhPxUyNIYyw4LbfJL85vam3W/At1/0V+YOO/n+W9X5X8e/HzMpobNxdsn7HDvPnPAf9h37M4xwUn7yeCptFOcs8yz8HnSF+gvii5mXGZcxZ6D086sAK3jOTxP5sgamxYN6l1NmcSsmXWzYwKWbzc8K0zFgVl/oj8dfHr/q/3P73s9/3r09fGbD77Nvr3nXfH74/XF4kObN1uXW+/Z+sD27to1bnYe721tL/avDo7qsXM23aAlejK9nN5OPzJD3nr2h396dDi/fLqPpwVZ9derTJvBergelVnZq6pZvxmrTPVM4nWui6y/HmSju3t8XB/MT/ZPp2cH5/uP158c3tn46It2C9HvAQMC/RBMgYAP/fmWlmuUHPNb0Gvuyi4LkUG9UlOAU407zxVcwnaz/1PgRuWn+MBOOhejhDMEh2Xkt//3Adov470C0KsB+V21AStwqI4EHhp6B9vDHrxRrUUA/OOmLIq53/h//eIEPEjIJZopX7lFECCBTGBeVHAl15AHNF4hodo76xPcnh514aIBm7Jy5C+a4IL6FF80LqDdTABMqenKG3CmkSNV6sfGfgRIjHkLUmUUIRIluy5Vez1vCCfhdNxhRfIMz/ECL/GWva+vPD5kGgiBPP8PVvgItimgPysPeMNpl4ie5lk3tPQhPw+wQOYe+P/Rmj/CG3433A3wv++//g6An38Tl4trxdTX+71u5e/r5B3EDzjLE0Be5WYur/gs8lJqvO8/6JA7jnrltwfuOuOsVu/tc9xebfY74KvPvmhyH8LAxMZlzIQpM/yPbup27C8IVL35nED81pAIEizUBcdc9NPpkCHMGDJyCkoq8Q8N1vs7P5UZZkqXK18BgkaR0o94YM7/ps555rzvdjvshTdeeuu5RyHBYwvc8MMJT8KAdt/ssDMU+OWhljBhu4VuarTVNs0oMCQ0ZFR0LEZ4DBiyYs6CJQ4HLpwIuXH2kasAvvz4C+GpUJRwEWJEiiYVa4KxxhlvikSTJImTZpYMmdSyfJKtRLHZtCrkmctdjg4DrrnukiuuugwB68Agxuho17NlNMg0l7q1XBcKFAA7K+wrIA3Y7pPpBJX0gL+ywdrSxdHBJ/ITgLYyPlW9cqDFfzkAS3/jahOQXcG6P8HGL0F7G6jLAAq2uGiQcCXT53FE4SlCh03QFlgnS0ge/d77KREExyPCgcZRLiuxE0ZySuoo4yZJB5cR3CMGBcMRdArt6/sLtx+LtM4DtqDnhsOc4Vju0glzGIezpbe8CrmJj6HhttF2Eo7yxwruHlG/s7QMfmwBDkTxYRFE41nRBWCpZBUJKRAskIfv+axB6/Jb45CrIecVizx+UDEAPXgfksPLt/ro8Vsxckm9bnWvLx3jMEvkqKObLzGnAf2MacAedXEWs7fdQVZI3wyyeOCiuKLAVJnhl+n1DgfvXcsWMaSQP35D8dPvLXpkDsknBSVtS/lYWOU5DMtql967pon1I/CqCayBmB2hYpy6uR+b8CJLNc+UwqYw4oTp47t8m6IjlWLJgxPBB+La85K9F7CXwxCAXe2nkuxMqTolEbryk+pBtxypvEYXpLROMXLBEIDDB/+lJCwpW0HEI6eRXpTbRUqHvZeGYnxwFHEzIRvbielZyRcbwmQPmT5DpUe+M2GrIBVNHwojhFmFN/nZVCQC6jozRdDuURTDHvJOj6TomR6Vt8myHrpzdB5m0ZNDNnGK8YTruYJHyX3AUT+nrzUyzHzKDuxgcNkKS6aclzeuXo9L60jbrqSVUCMyREBF3OCYNZYtObvTxfj5gDaypyO+v9nKCe/uBlkV6vDudq1W9hJOBOrqXjTZGNXyaHMdiDtD49/iaFeKuZKRdHp9kawDHKHZH0EBvzDZDRuMd2f7UMCtGQKEjc6DXLDvSm0OdZjVP99embmRDLWFzLKECUg1W/b/AkPSdc12trYW4gyuu9LoLc41LewfBpNpvs4pay9nJUO0OrmFZqKyFIc4SONF8qqgx4uqOZK/yRasBPKyseLnc97MCPPUXlPaj0dfwfr950IZHz0ltf75y5bUKXH5t4QOCcNqcvZoJu2lI9btC3R+6dddQwf96npB/Pwsjh3uJUtr08ljdLCajm41zxNsEnLL7exCdvmmpNNICwIx0H5YE53xTLXaSvgFcBXhW0nLjpJy4Bx+7j1fhIBr8/ZiOFwPQGANl58j3laAu7qgDm+asWXjFsHIdLpKQ2yyIV1uBSYeu9f5j172hAphW6jYivDtrPLDwb2eZs8z4R/TbAH6Sde23rK+eNtfbTt+qaZvheYCMQMnlv2c8KM97lPb7ZtIL8OaKTaXxbc4sGCtoSOe+1g2YG5f/qieMGiu/lZUO6ZdW4WrBaQLZYvSnJCslcQZhKpZCQtIhgNrrmbDoGeOjtSxIyWqwNBRnFh/bsddFVzLt/8P2+tLwXJm1Ge1PbJ+q2ghs3RlZ+n/R8UW1qsW38blpa+x+EUhZW1lF3Atbm4vJwHRNSTdqKBqKk8InYBaQIiS7G1s6ggwPISQ8wBvU6vJqkkK7Chls1RsSbItZ7nN3GK8uY21a3NGlx8bPeCuzvTXYEaRZFrRDKfnM1O4/1JHJIOmqbH7UEbk5iUCneD+9cF3H2g2O/HvgWJaSyx6hwTmicoybVu3dGKay3bVYDsdgVOe0MiN6eNaYedvxg+tVRdW7TluukK0ZMgOx2uT5zNHviYg3lyU+oVwXmihubwKsntLW9SmVkjH4h1LaEu38K4n3EwMfcbKScuw9vqU7UgVKjtPrRWbYacKwYNdUh19hGG/Em8W6xIs6px10lpVtux/WE0mOa1AH95kg4Egbo4wp8ecXqK+m72zrH8V62wtwHfQv6I2/fxd/4xUn7N3xJ612n/vWoA63119F2/v04ecrRikqV3te9Z6GDKB1e01h3W4w8Ug++4h6+n/HBrckxOr/Pt30s3A7e28NJ9EecmRsE5YTUkh+6vfzNWEGeVMYs5oI2vWCUeh0MPGrrkM9y+lk/c3NR2d8TQ3nJnQDLJITFn2X8wGgDsJ9TiG9hzG6e8oUcOCk5/V3pwC1+pIYdYJxUBrrRWZMcvpvj6orRnJ55aSMYisIVjPVdA6mAXQ8iQRVsF6NprwS+eGvTMFu8cTNO8a6siy4ljlIyJzhZkyJVW4WXAMqKymJxwupSyJ2RhxaLW6mGWhjk26+6qHMPOTOp9zfZ7os9LnWp/7mC59zvVe5OTc6zjd5VvanD1AjJyxsmeH1peeUWjAnaDl7VoL7Z23g5dopp3C6UJGBnnK+bVr9rO6yE6AznNVoNSt99ERpBUQKnTo2sq/y+6FgxvdMrGqsrIsSGTf5Pg9v8Obl8mYqAiaunoPvUfZS6XNllpsyV2uqAivB9gaAOolldPcx9/yqyC94UQGdXHzZADny5zjrniU63Zr3fB6SbmveukI1x8psOvWR2eVsQJT/3+m7Mmei8DSWRX+m7AQmpty6F8DR9OxV2KKhuJiBO8PodAyfTn8u3yDQkCO/cUaE5odazCSADrp2vYxaWJQG28rsKRlLFyKykaP0Kz4UJt8nwHMt/3wxs3NsTMmw6SZwadl3wD0kRvlVHF13hOExetnKIb7JwCkfGyMvPAxU3YvAg8TXR16O1SiwdG9lUckPuqKo9WzrQyrQJ5vP3dXmSba5C0hqPHPV9eD5guwGvAYHtvd4IF3RKUbXpyb1s/sKCl76HoqaWVy5WFh39heDLthfVXikq5KmZVz654UrmJFwiICvlr78v+h/Q5nXek2FUo/Isy01SS+svB0HrDCa0sWwX2J52zSNqOkfgpxSTaB4rCckUR006yFBAaZ1nOBqb8mIEObXe1IudWl4TFVNiItH0SG6PviF/Ez6sDVjIDVrhy8XK7nVl/dfym9mBqX911JC/Nx16hENI0Mb+z+imxGddYZTthtZTRLF6+VVeAGikVx2mAszX/sLzOHkL/smrHwR0vqWrezGegz+bVHbctmCkhOlm7X5OpAAGbu8i11UZlPiaUrstcVZV+V6rIlL9nqbCwyBFDWmrDLToyHOAzCw7gzi+0wBbG94l0pJyeDXAKuWgvE7Oz0ScmONV48NpbjSnMEBdgvW2CEyO5L40+u6WcB+k95jnX3Jfgx78sNw3UfzsZPn4STp8VtvR6DDD7ri8E2yxjFlllr9WLc1NnDK601BXLbhvA/OjdyubJ791Ix43EccaeY3vXhbszTERAzJ5VHJ6p2IkqTRJGwkEuZsTGRZcLH7FVSQooPFacgGUGzd6P69RL5IcCU/jzlczQVcAxT+vOtW4w7dQqlUCXCzebsTcxNYUPakVTrQpR4nF6sSibs7xTiR/2PxpIKVxWCZMSA/d6zbEh9XS3ehPX9i/dZP3zk/uafjAHjr83+Kw3Kb+o5m3CBXzKBf/DbypbCLCnPu+SsPt9W0lFTvzbQv2CMyqjX7PYvE1+TiE0KzQzQHlu2MD+wsaEhsMGlLAv3j6YUZhIxlnq31xG2KMeFQsrx8hZzeOs9GHMmgVLQHwb+wXO7Tgzs2Dq4f+/oQFn+BKmxo7TU2DVGEaqNugz527/N9Gc+b/c//VG66m/91ug3agERWzI/35/y4dA9qa+ZORaJ5gv//02+2Bl/kCyaPDxQDubBN5G4Wpgtb6lBMMzl4ztH1eRER3pcDr3DWJzXlOZvOJ8pba/UgdVPWwrqutIH5lrzn3WZtMmHYnh1yuyCyY+YSXe372Vxdtl9ZM4DZFl2JSyusqc5Zu8qrXCkOcfmvA0NjZWKRZ43NmRuWBTLdtVaVOODIROu1eUIm5Xjc3rwWs2gf+/A/q07jg/sko7DulCgFDU6NFZh6CotNXZMkOLfnzdauyrLy7trWsZyx7U4A2q9zqdyt4C+wczKGTVtNUUlE8JNnUNpna6AXm/MNDg7i/qxuUJJiJInxpSY8jNTfyIMVPNFubrcyqqS6O84aQEB/7AqP+aMdfGEZr4FVQlzK6xIXjOgxYSnNSYUhNJibEVOC+upnMbosdO+X5YjEThlMklmMV9vrtb8YePUmjgw1fWUSNZaKK8v5cqEboVGVVgtBf25f/i5/t/rgD12wuRpk0/lHTKQQy5Yq3VzKSHDwdyBqZNnAlb6QPmPXsx33vLUAfDj0EDResna+Cl34/+SoqGB3J1QAglMXhT/WRA+gz+ND7v/Tr0sDl8gnCcAbM37v686nn06u+rtrngge9arji/zf+/uF+w74AdzR6bfUj3Xs23kURcWhLmG8nBlkexVlCSLybXxoeh1C81xjPXGpciP+KvP01hrRJCZwTZzaEFJZoAL3kSFCkMWmD7xSVZSN1L1n4btIN2//WMN22AOiV/NCUgVmgA9ERngxsdi8kfYrAEz9+/Th24cNsdDthJrRgzeXKCXOyEzmWORRLd6TVwmzY1+mBh35oYY4g0QTUAVJXDTxaZrA0uCg8HSiVtJLoZAX63TtPqcivYqc8DLs3KZfqnUBGZ5PAuX4QUFSWAcpQiyVHZCoVQCAeFTKey1FrTNjX94WyR6S8wUCIhZbwZ561EuRjZdawVJUZYqs6Ld6dO0Vuv0Ahedv7ynNDgYXDJwTWLKHkz2trWSl8EnqwA/ylqplFaZDNBot7ucraJUT1tfN6pCPnWyreGz/NGRsyT+AsqkzEz6TEd1vcLkVGRLxLk2zLWIHsiUr+GWKgUMi4mW8nhKRtkUgIpS5zCVNnyBRIIrkjuyIaUqiym1YLJ5kXHYyhEOr98C/3N60+7D5uRQIioxGp04ikmD71NMLAHQ7KoxjzYqacY/WLh+6MyW5QmCXxnGdnP7LpDw7brxXtvIROS4vAu2nIhREexspl7hINLSavf0Sy8FMeUQDdGWhdqPSt3GlX7ITjTihSxrs7OxSZULC71iqdiXA8ukIVjil0sEnmxIaRU3cAX9AuFxHm/1VweujA5tBs7BkMxxN92CZ2cWlhSrQliP3K7UmXNKPwDH8+Bz4Hs7uUvmftcehZ5NlQczdN1g5ab/ykY3/vB74/4j1+RHBkODYGeUZ7cuI6gljE1DZB9yjsoBzuehnuTJPyxMtOJZKLC1480PPLuVLtS55JQCBTeI5qeZLjDpNKxTjgiRHBKbmC7FOeQIhe86LL/7LgYP5ZYCmkYIGD4AcpStwahrd7u1bc632+s8axNG1ZusboGVywjIFRJaYYHQhqxfIRfaE8QODQaXbLzGdZEEa+aSNpdX0/Z9RcFt6SpdkLQik7KHpoVKRgyN9xAhU4GF/8Pb1idtLdBqOB5y/fJ7pYvivZ+RAnIFMfBMILIJaJkSMT3TKgD7h0q7lsEuyqrnbV6Xou03jUXgInGvbVwSHPwxaV2aA/D/0qnBeqnRTqOi+gshz5EoLvr70DpdButX8DVK7Cf0xW5muIVSQTcVT2qPOjrl6RmarsTtVRbx1+aKjUQWy4BPH/s96pe3MyI5fJ4tmwEaokRZ1M+/sBBXQnk0IYeM/eZNw4b/vmWwb/wpenk/HclrJop/YTyDk4fyhvipORJ7OeTTFVNkRj796Z/iHx6h0u//v2/x/7fZrIcMYwr4FkWb/Y/gbUgQD62mxhx+a2ZWvz1o5pvB8yiZl8PO1iuDWBHaSGRA0wl+w/vg82A43V6oAm+uPite0LOwp+jKM7B/0bOCyobOBk9nXVVdweJnvjFdY7oAbv/H/e9qe49PPl5z4N2Bj7W9JyefBGOuFf9w5o7Mf4S4Y4ChVfSI+dYJRlkfpLCBsl055hyOTOLJY8vIp/YLG8moMe4z96pjWSyGcb55/q7QruO7np9wJebVcnagFdsE4Ruk2pJ/WmJKocoyUMjxrRdoUouMmficloIJrnKchVo7Fh7Ctr+K4o7R/oMJo/3rdea6ysqg6tuBYU2+MMWUTJP50HmJJA8yZabrfY3m3XEWdktzzDOsYoe4iA2z1OKMIEMs9aKQ4ycfpEmDavJt8+1dR/bar/ALUXC37m+sK00skTGrzFW7gruyzdkstciTyRRJMtDONDmMsF5w2W3gbqHMqhLJMkSqxoiEkbJjEOP/6NwrJgrX4nKZbvNiBWYjn2JI4Kni69h78dh1YNRV4gwB7BeKYJ9XIBJl8GG/SAT7PXwSg7KTRt9JYbhPOdBpq0TAIkod4Ehc2KKYKqEAUYktFDv9HLXSx5bY8QWx1RJpbDW+UGz3suWZUq0DM96biZ2gc8g4hYSMuEqlPK6C6GkANPHnN6xjib+TZaFBILTDRZYSfyBfVCnTmFxGwR9Ed2LWSBEhR2UOMhWGYqm0xKhkj3YWF2eHXU3F3X6QEuVplusqzNmR5sKMDLGDVM9mvGpwxXIspJ2/76JQXo9j6m2WyKxItSKvQmTUFfFlmXIiMWJ7972xg/1Mg760SQaSt2ZYsr72fdHib9maf68xrno5SI/S1UjMhTuzEqrnm2mw2Mane2AO1Wpmi7gO1rIspLG2xZ95QRjf0ZhDgy01elXYIKblmaz5TKAeOIBf3UTCmGp12tFGiyncoLWYm7SmsJmaZoy9kReh4dhZHBuPC9nsLBi2syD2zW1jAXX2jMZj/ncmVzdARemb+NYim15fvCyL5xRpNJnFsFRZxJNnq0VcW8WyQOptYVIjX++H7cTdPM4EO5nPt7+muRzeSQcRdkvNGqHEqFdQwoAmsWjB4QP41SWC8nij1mxpjGotVH8c2QbbnoMHWZn9kxqHIz278UaEh0ZFuHDGbh635qsYD50R4/465xgJE++A+QkODImMi3PAUJwTBgv8hEkCW6owjaDZCKiCJTaJWQ/bmRQlDceOQUxhkcwPeEqHTQPR3DqTT7H85ydy0BopzXZpNzI0HPgTlW0kiAXoVZ+j8QEyLRS3WOYxqxUOnYisvtpZ101QZznA46rzvMtJsmiL3FJ1bWpw+aUqcDjS6eWMrFW+r1iEOhWadpCDmXGnh/ngB/n1X3GrUustKOiegMliWMwQ6N4c3hq+fDTe5ScfC+ox0yG2hd7DTju2cOL18+jOLiymuxON7uzGYLuqgfFy77sRATzuuU4wECm04LZzaKx4z0oi3bSTTJ1DpRNmuuOZdM5KCy4H09qKoWFYbDYd07cIdY5YhiNkkfC9BHw5aA5vDV86Fu/8zs+Eeix0NmSmT4LStq1v32rXBCuLOjiYPPLXc99U9+R8JN1mSJ+gICnT9bEYdBOmbk2+6CMVul0Z6VJquL8zPPcIWXmeTy9UWCqvnsx4MSO73/eUea0DHNTSXyYxH/L8NBx0V2MzGfsWOvpgA5JC8nNu49A5pmBCPAtWfFkYCga80k1IuF0XNti3aEB3/7gGC371/9rJsDAoFO5aoPoVYvhlDiPPCdEmsPF1uoTbLKLxKKy0GzVshutbl0y6/i0Mrn8PmQlh6AK8lwsdh6it47AU4pcT0LS7ZPqvI87L3TopdRaZgqJ+YC6dM4vA6jLjgayjqgOg+ou4JX1cMKa8s6qzstyqR72xGFfFpf7TdQH/afM7kjryOqY6BeReRbwIqZd1NeLBK6gtb8WHl1XsqdVfNc8myewKg9lp1XuAUZ5fxtdripkyvx6e1X1q4kySJHg59DFp9MfPIh9iUuSX8g3kdtyZXgPV5JtmPr0mgsrZk3JGT6G8nihBTJdGTz/430+mPJ/pfGc76OXeGKObRt3eY5zLOWflfLEa+kKpsbrp9O2TdfO5NyzbM13DuaGKX03ZvhpAt5DZc83Iyrng91smjZsBK9HwyQDMuKWBvXlzRpmWmcD8oStwA2FMwjhFFnazdEmt96RyBXa9V5k4ljxG0PA7mDDk+4vf4EUhld5AROFJ7xjJkiWZpVgWH4hP3r5gzweZwqwbxn63kaKnbvgOM6xXmGQ6BZU2QBnmkZ5F/ZnEBXYDNKoCRH7wuDrwSPoz6hmJNyx1siapH8Z8dyBFn3zwO+xw/HrMQPXh8QXVxPBEFbj84Wa3C0DUn4+rmIwDp9ze8l7cKy7l3TW9WHUeNmUyVpWPBY/W5mPK+zC/JyLaiwH2a1xAaNrWvqj58eyPZwonVU2q/qagWe2p6qkGJwohSrdwn408U1jqMT8I/BK1Azz2bQbiNTgnrtAK+M0DrNM/YT6hBxuH4FZDK9x4HbTU+WYqaqrUMwJZytk1NTOVgUxsrrpKMcOvJeT/IKarT2BJ0fZcsUiSKRTkqDWCXPeJTyJyC3nTo5Wmj7R1RBbVbrTyW7Kz23hWcxs/GBS02y3CllB2K9+U4+NfWlWFVb+lCh4wWQ8FVIrxIZPx0A9SEcZKltKr4NGth50cyXIbfwWDvF7AWwpjS2Pffo/Kal/DEAkd2SxxID9gVqoCedo/uhy8+2yhU6FrmvU5eq47JrmzdN2CwE2UvN7MFpSC2Id2q6p5hlyd3pAjm1SJxY1ikRhYXTbUyvFObtjCgijQEwL9SxvJi8eH9W6aSQgRbLMal6erFYEiWGEerYhxcu0mDo+suk6kfWklerk28m6qScDG21f1TEUqFVlFsFO7msPqtdNuoBZ0EL+8mEJc9fWYP4//BdZExvXKy8rkvS6XvAdar7zUY4Me1iv8u8fRa8zV8aq0argmx2jWF+nHmTB39rLh+VgXBGEdc2Fo9eaPqgKjPsfUIgwGha1Gk7CFAjWTsRW7LdSErYIEkJx2dJis7R6PCe5yONqRQNzO0pYrVOUGowpUtdoK1YwGgXd7spOSK/6TSWbe9fTB9gmciWAdjKNjsXQcDOLH6Z1ZP2T94NDz4kveEEo/JP+XXgL9BhWngzubWEYm08hiqW5ksFg2oplhdE4NCl0dQqOqq/GPxpoaUPbfb8bfwEzXeuN6g6Pf2A+i72rVtmqKG7QN2Hcvw99djZavhyal26lMlL3w2stTZ3w0G/L+yRdDE5BOGhXpmHTt2y/v25B0pg19d2Yy38Xlerg8rst9KPI05+bz/yTlgKHCFm1LxAWoWducduGtmXfLpKiiSSXGTeFq6+reggJNOc7Hsx51YgTmPAd3nDcL7slxmsQZ+BN8W1kleT5Qb8asX8kPewSIfZ7dKCKa1l3lDNVcI6iERQUyvTvsT7Ga0OecEh7rAI6NvzbtK+e5TgqBuXJL2uRPs5zgReMe657cPbaZF+tLj+Qfyy+9UD/NtjN3p3VnIyAmD5hTBsB72s0vLUPZWlsPTLtrGWcBE9mSlSv7V0lM9ktV+FCyaiUwTrXvtUQf7arqqlTfgzRnai3zLHO/0hSgxnH2CPbsYeerIReIHl61XH+6zhex63YEvC/bfs96b6t1a/Ju2I5ZZn1lBU2rKSsOVhxDYs9DVqs5pKQeu1C5Ig0by7O4LIVgRcLl8ZbTMUB4dPZp3fbNVbD9MGbbYWDavjxIZxWlwIIKZI7ij+DzoDfPC4vJDwZuA+3ZAb1QDVGwlQ05BQK2w+kwbOPQPC7baYV34HbOJxDXdBR2x2oSae+Awgfb5oYcfCHUx8k6ebDBwtmBXTUPTwqx2O1ryPOHDgBJ+kDj9UOu29DgJzT4YmuvaieYB4Tm9cBBuG9uwei5QAg3zC2cOfjU5RtuaWyZeYE8sBxFeLwXh9/zJx7/+JR+nJ5+dBo1jEK/QKNfolDDoCcnOhbMSEntool1EjMPx163MiV5LF2qE1uBMEOSKAFJMaVLh3VcBy1RlGgJCmBS314g3BOuCoP5Q0nMl8fPPcYlpd1MTTSy21P0Idnd0CIa+zgQjlQRVUAU9sBhDxC+KEy3B/L8lfttXfnR67YYdGwUxEGztKYMU7b/RH5BAzXbmJjaTRdrJEYe8kZYGUhMHs+QasUWIHo9oHk1MBZH0pqVl/VooRNHs/yJxjwq/YD/BsTsXe98F5LQJ5D44bIAJlpRIh2fJFqU30Ah7v2jFQXYjhAw6vbTDW7yEChVOcNoWUhYB30L2keX/NmCYBetXBDLF6YgMuQyELYyD38rJMPNgd4L161utABqO5Sm0lJ6xkxiYXdunz2L5n12LE6Guha7MvxT46mBbCMtiQVp+9LV3LSjoDSOLTg6Ck+AWyIdMR3TWyClVol7jgo2BkiL5bVeU0xsimmZKaaSTLACvciEcTVnwS0GPadUdtFx7i66jtxF76PS50Oy4NDjGUUKOhNQLHQy0h3nNII6giau1LkMu+he2UXPB6+/46NAGOx6G01bqXMthLu3AUinTJO2XM209R0cSPfdcdqovdDFeBcd1+yi64y6kR3udO47A2AnisxCki6bKdLInEApWOh4Vnec0QjqkMyccGqmOeGOEwDwT34nW2Lnfju1qeMSqkuS+a9ZbOw4pwb4Y0ofV38j4Miv/zHrRRvxiOh9b8aZwzoA2GIPoLlI3TTWPa9ubdMYc7S5KNE0M6/3euJO1l8XkcCHr/CUqNmsTVt4kc1QB7RsP7Dw3PVDtMhB5sMWMvD+u/ht8lo4voly+XxNv6k2tZntq2yd8Ji6ONIEOcQWYPsiPAp5FqgzQlG7tC/bsMpF7ED/ezg5N+lpuqH8zddE2y+iUchHAO/msSCbDizk/AS7uHBWwJUFALz50qD3NWphh5G1y/Q5OcgvSvC74tFG/RevOwjUOB4s4SFNm/ei+2Tj/otb2z69WR/0+jJTUF+FDzHBw2iwTzFnuoFXLi5JCjl+orHHB0CfCgkM1J6JA6BWgY34ixFvhgJzLbPetRinOPXpz46cze28yLf0F6+aa1b9Uzuqpc7X3UbCDZuoWVpmG9v62472sXV1GInXETtup+7Gdju7N71H39Y/7n8PDoNoMAzeoXBoH1YMx4enw6eRSS0fp49rxi3jwfHUeGNSOLkyNZnSphOmEvI8JiumLKYpZkLM7Jgrse2xO2JbYy/H3o39Mfb1/mgQH4eLc8blxHXFbYo7FG8cnxFfEL85/nD8mfiv4p/E/xH/6YiSUJowkGiYmJF4JMmbNDXpTNKXSY+Tfk/6mByfLEjOTm5KnpA8O3lvCjplaioi1ZO6IXU4zZm2Le1yenr6nPQ9yGhkGXIc8iPKj9qMuoiOR9ejF6J/xRgxRZi7WD52CnYz9hnOjWvGXcKT8Br8QUIsAUfgEFQEB2E0YR8Rffn/LjpRRnQRy4jjicuIB4hfkiikTtJ00grSeXIimU5WkG1kH7mU3EKeTD5M/pVipPRT9lEuUh5RPlLTqCKqnVpInULdQT1PfUR9RfuMRqd9Qy+ldzBojFXMNKadOZO5grmTNYLVyfqdbWLvYH/Pfg0lQgTICJVArdA8aAd0iTOSg+RIOE2cYZgKy2ALnAOH4V74KPwaHubCXBW3gzuZu5S7i3uLF81z8EK8cl4Xbw5vM+8pH8/n8TuMyHCGfoCFBWGBvkMYhmH6r1cR709LHOFHEdymWj+7KF2B9h4QgTkzf0shEC/x/5V3mmR1dwleUtV/AjwO/YcmwXx3+Ccj3BvNr/17CsbBof+Me+nozYoUUIFaZXn8hlJjuQnGD0v6ZT680QcyH9/oxQy7qf51ECjnIAWAhBiye+1CG0DGGJopZD69zgXwYB4EKuIljv/jk7OGCfdm82fvNMW2LIOOxFwZrStP3V/Uys4zy6Ax8z4xqcx3hsN/yNevQKCLJHVuxMthCAYtw7erj6w34jfH4rQfDLK8X8FvEAMxSo8gTHW+9GELZ7gkYfoTTFYYNg/8VJUJBlypy6hJS1CvqzT/LbKB5bJ1fRHGK3jSM7ZP9EBvDDsRd5xcfYVDnufIkk2VJzngi9TVS8KlyX0nzf8QWbYU2WO9PGde29ZBNESHEST8ljQl2BoZH4kFaM5gpGMCJsTVHTSFtU4pOYPRZgYnai9bRg0ezKZ1asxGtZxErIkm0FHDyL7+mAsZl/agUw5acOSNSgK96HxEaTRgScrr8ONeDY08cNIYfcvtiOYVsQbXYH2hC3QQgqtSEQRY52KNaztb+Uh2lKkC9oqr/reMyFC5NY+xir9kZTGqz54p7Vc0Zsz3wbEUaOL/EFHGUE4Wy9Ik0qXL8EnCceEauIw7YyoM1b+lsoW9mr66I67SlVe3vyg742Qf2z+Lr9K337f5zcKlwTYoX3gMYsfoMZLfaJm5/6Z+cp23gM3Yk07Z2lC04FcXQ+Wq7NRCj+f7yP4TyHI5D1Ngytc+WrYCAgRY2w7rESlb1o7x/lYQagT0klLytONzeGS3+qyank/2UFmdazukHI42swwbQe3IbPxhs1T1Rn85FHgzB6voKSV/uJY6sUW8P7mQC/UhLkfVEJmua5f3L9fgH/AC+KJ8dueTO5/VD5j9+HsAdKBLLVwlMSBq6LH92RzY4yWDPJiD6xc6YO0YPUbevdF+xrup9da5Qz9U+brEhC91zFW7XVlV3aeDCpRAysq/JzRICUtXRgU5gsthmTdJ9tSCWpoNyFrWNc2jQCmCasY5LV5CWhdv30qZVrM6sgYtGM4pIDsZIAqfM49+5qMNnX6qV8GIaP+4Li58vA/PxW+/5TFlf+vpFdC5oI2/d+L7O88F1lMIGi69vB49uIoLaPxZlb2KMMwBWWN4cwn22lqU7TUfIWMK7JgdgYIg/PCf5NE1bDFDvHb8CKWUifjc21T/cua/i19RTeXH9q/TsFc+m6vHj77/aAXYde3nPIf9/2PF//epZWDBLNZFKAh3SwPtwejyLYYBbe0M//1uKn4nfyo9tj/9GcKPZTuP8xwoNe33i076r7erfhu8B7QLB0ABQtgp0AMCP48hRjsdDFEw13qnpOy3qEbQJBz1vqQ+M+ukwrW3HnP5Pfdry3V+NgYnHFgHumY2hAQij6GGugssghYt5r+1OXrz+LNNTNY3ILSzRuEr4Bd3pwDN9Cjekpj02iipE9gZ3JOktwLbSe8GqjgbgQg+s5OIWjkH617uf56dCbqz6IB/YIzllcyGUD7sF43SldEr/tb4RQ28aX8rO9cIFb73ptK5YhJ0dfVyZ8e+JnSxUFffrmZ+0kuiyoHfS4G+KO0T7ws24TfH4ObNn3oImRDzwE0qB7cxd5bw30M1srqDZ5Og2k7lOIhVs9YbSvBYPbGtkckU/olumtX4PEssCBm7MjrMGROM1cDHdHIlVwsb4EP6AIBmnr8/hJpp1s/eysZBaqSzIZhJirWuQZAaPNS9YqdlnDTfkJ66jO9kuXqavVLbLpxWwHbTFaFzVscaPKxz13bPjmLwimICoMglzySfpTkE3Nrdz60zloSac5GBA/HVyCTi5IW0au8ZJeNlnat4Es0o7fA8IZ9JlD7PNf9qM2qqpIQIiChFPmdKshoqY0evYu/XH4yxxPGqleziOQYsqccdt+cYhgYqwjYJLyKr4PWaf0NfxOxkk2QZ8j6bP1U+luVELhA2CambA/Wr5mZaHEpQAyqH4xj2kAzOLodV21+QnpgeAkx9KnH8lwMtJTUUiTAwGY+QKp3dka9ltNx2H0R9XqIZkYY+zEwIUQY3xk0SSDv3rCBwZMoVegYHp9YcbKYm441nGla0KipWHk452p9+rmuQ2uRAzgqWDwVdcyKx3B17bmvtG6CGF1TTgLYFIBYTzUKyp7NFFmdiJVc5VnbOEityA2O8SY3RVMqaKrOedzjunQPmdiaHP8f4BYLd2scrYFSoj3LyL4o/B1X81b/c4Yv9EXFhY1kNttsIoPTY6MBdmSOo2PMDIWT6mDvJPocCCtdij10iBrBCVujAtfvNJb8hl7dkl1AmkmqEfsJLGwWWSb3AYHCncXdgAINX5NHJr8zixZcicCXifx/XvTz8QQM8L0XAeD71N3Om3whrWK8qh7X+AI+/nHfXJhdnViuZTKB/od8+puLXg1PZ0n/KPvo8evLFxsHBYBHE1fBf/rv4y+v474dVkxsbcpb0C/vqVy8ubt+/AjQGqcAj+4r7roaZ4f+Y+fQ7Tu3u9beBD40hw70BmesazGDWrS+K/C/jU/dxHKhbo99oLdJf9efB4keNNj8/HIJkwqAYisVTmMhegdu1IQhbLAUGqLXF99i7xLOT0QhQ1uiVD6QKwaUHtZoJZX4nWK8fanxL22qBlBpdfsYN9r34yfEYwCyY5c94SVEiOLk0LoXr2eIu+lq6MU1IO+wHAb1WeBInUHNhbNBMm9RgjScvXtz25Y3ocqVoUwNCjEnmY9sLYKexofBwAXFKyB2TR2k4c52G0kFhFk4L0oq20T/OV3M6r1YTxPOx3koaPQILq3VpstUUwF7Bk++VJph8oN7yCA0kMPxrhOO1RDaEXcOK5Rt3Oxff/QBd1RvqErfVAvqSuOnCKKkX2BrcadI7AUqqA+s416pAA/wbxLAfB4ImWuTFGxGuPBOeEVVCqM49QxU5Rnk3HekHp9J8zAma44mVoGOy5To6HceVEww7fFVDP3ZZZIEhXNrgSdFKVKZHoqiaZOcbfV6PLucq6dNX/LuTaiU5TjWM9w3y7fEcqMvZ8dhBXu6Mk55cmfuodBxn/2L/YIIOuROxQDXrj30z+kK27GnMKWNWeGYaXv7cSFcTPgVKsY9xNi/YZXbs7iqd3vKDZGhqW/rx9sfdn+zMU8ChWC0l7oVh4JPlh00+YjcY6aeXogrBtSdDC8KNx0CteJY2irr2+jW7vNwPr0UOyt1xd/qKYlbu4UyI9z6FBEggeKjxD/Ve75jrzarmN4AQkV76Ru+rSGJQGhJp4ApahSZyu7Y66RgJdqZIqCpgMD3fmIQQpQskpyx0LBuV4U7cbjY7nalrrJlVfYkhJZL8CWz/P7qEERo1xYDhG32BmmXhdqWjf7JNkglCwMivenqpykDHos5hRABRbYmoIANZ1HO1ySSAZoRKxui9Vkl5TJ+0jLfklr/nZFCJiGDoF3gJhuGI77b6KGXhz6rdayClhoY9WIUThQ4rJNrKK3mKXJwTjzl4JfOXIuFcEaklu580FDU1vZ74lIkPcXXo11J3MYyiwSmY5RKAdgZ8ZlhUJAfiohY2Wl81j4B7C1yPNLSb2JWmjJZCrxKEHDpFSIQMBr4Uv4bVEYcq5b4tEwFnDKyC92joShk82a6+evHp0+fQYzu72yfZqP9G1EeZ5XUqHqosVJQGUSa7uGJ+NSkfHmU+8jUW/swvJ0MIq5ALuUM8a0Xrs2FLibuDvNFN5p8mMFwjUTGk3lKSVm/Qcli8NyIN536yK7EgKGaIYPjHcNtlM7XafuN3TfMorrQqBWnTyx2MQVGYrZDYky88qnN2sWlP5jJbU0gBocLhr54fNl7j0w2Xh9WCRavFfD3lu7WJcAyDwDONVvneKxEC1YxaAiEw+JGzGWEv3EraU9QjTxK36nitHh/0UpVdjF7xajpmKU4HB6VSchZSIXV2Yj6IhV70JtzEbHGiSW4fM1eOYB15cf1wo07vmker6PpwcA2ujD3Z+4GuERFmE12hOoZx0rR3ZzyvDVVz1aAUcwUCObYqE7j2bNerOF6GiB22EvJ+TPKYk3Eh3hyMWJsUQqLPdDo7oFiMYW+QNXOCWG4qCMLNfXErnoVrJRrc7CnBcvJlV8bhl43DMNd4/nKgxjaNbtq0E0AgBCpCloumTpGkcfHEAsvP5d0RUlF6V+BisZ8X2Q6qMGRgv1uNpaKiropjq9x0LJmwspdIAMaDzSbSsrIClC+0V7rBOEckhhh7tVulrXLFTsLQCI0Bx9yLi11nKrZ1CZxUsUXWWSl4XmLvECMsWCy5ugoNHrgsaCEStWsrxU785CKzWWPVTgpIi26wQ2CLCSGhiVlMuJaYDuPNg5bDnhuEoadJfAn7AuU0bI+Q7UXKkU1DYT0JChpZQUs1tvVDM9zsQBt4WZ2ft5cnNwMwLuZ8Em3pJcX/xmIYYzCCu8wb6FgV6LamypyGdYNQ4GIWdBGPGhr9ozvrpNnOttfjSyBM43/BSiFGepUa5489N6ggq7Us8Cwn6+4sVE4aMjeKv18qEHoJkS8tImlYc2oY5OClQuNCbHGEFKBysJPs4gm8wZts5rgvcZGbkDTVl53q0FzHFSBL3FtpMqK6mqWOu9uPhnpx3xzr1bydt+KsJTvwVoE3KsBenc2XDkFEUeoUYvP4jC/UBiV8vNACgSMzDRPF+0OgDUzcG/HGSjPgLQ3GRkY3upGJtqjPvWXLm7ipy+tIEIKQKhwlhohbbtQudp/UgMYnQrg6fGAjQ7YsZzOayDZDaVBn5XLy7pXc3ZT8CPKfujHKH5NWXMgEUxV/ZNzOTpw26ajfP/7R/kNoNwZILB/hf2yB/384Onq0PfuufhHBCmjVsq87Xz/eUNMB/3zdKnaPnIiKjpCVwAiBKz/1bo4aQbMFigYF29SyTxNV39NlmXXB5IaulpLzdxvLfi1LC/OgDd4Af7zwp8EHSIaU0uSrp+BYekLR5KDbiWcTC8oMGewSCUgWXB+wMw7PHK53VWBISoyZgIFKloDhVl1O3zXheQ7XpJRSI06lUUbN7iftT+HaQa2ZuWGnh9lbseHEWbJtZOWOEDTYfmMRqQmRmT6spBmvIFTPbcaJRDSi3SpctqSbzT1eK5tKSlm/wKtABKJSi0OHCCxD00Q0HQBHtxzcZoZM5Yx7SmZC62t5sU6r275TSeBjF/YW84X0FTg4BvKFHWCDNB4TANCDyCApREuCwTdUMaRVW0A1HimEfk8hBauQRHigdBDJgwKjF1tUAGEy8MiUgT+rVqXS6XarMJ44f/417XwMJ1FpXHdCNhqku382z0NyvXm1ZkiUBk8kzGLSbFJhmAwtH3SAesoVWMtifdY9CqPMqZt6BNeWy2bp+TZUfprEuoCPNSa2ckflGC/g+i2jHZ5zOrPGPFzTQwXqT2UIQ/eaergcd25J+o5oGPu6ZkBgKvJ3agrwk8h8dXFxsaqtmmaJaG40WrHEV2ZVYjp+NWu6nLYg6dvY2fBSBQ8GsdVWorILvrZcE+DuQ33PyBCibHny+hrPx3hecdJiVao2dTFRecaxPdkiVHCzJqOhr+GqOUoKmNkmUdhu/f2EiYy3R5CQNc2kLXmof7RmGirFkJlUmwUjOqZ9GEzF1nPRhexlSRjwn8DdzJtB6rF1TFuFrZ/dJGz90jCmWM6k1gMBswFM7JvY9lUzvxFqIr/tSYpw7mssx5tVLvZqNkXmpYBR/V0ubtLmuzmPZ5jFX/60s1dtk7xxeFpIk/Xney+XqzU3cfHoEi51qK6BJZBH926+yD2znLHQsUj5MGmPi2rgC76lVhpIkqCJdJEZRYt8OeH7g1lgUr5EdmiFrPLDhpVqW8wcy7VXWyv/xEE7tB0/yajQs6NTrTxGNszLl1QRoFDnX93Zz+/Zw0iSFPFevqPmmbDca3ygw0SsY8xklk9B9+NIP/LYWuuDWeQGU6RhO4PCBHEZ3qUxWp7amu04li4wQsGbchB1ElS0sjSoQt32c036dTRtyq1WqtEgZviwadp4qYywMNl3MhTrYk9kgyAWEygGeDGhltA8bdZb0Da2NiRBlDQ7rAjO7bvMJG9kQjTmVYEjiS1gFayi430vyrJvVQeqvW4WiQT03iHuhKVmLZUts6OeQHRPxCQudLr1mr/48Orpo9M+e7/fHk223p8IugMMA8UYljeZAWYqKUVe1WSeTUSeduyo77aX6NVvxq5ddOwoJOL/zeF2Vb+etz0eWdq26y9mK4M0jDus5/k/rKkpInQocmLtcAoXaJuMQXacqN7p9tgURzrUksVb3OryZeduNNNtGLSqlYtVXxeBXQyoJaL2bnZlzSFUOynteq7thHk+1QW8FmSzNxHEcsd1I9HIxgwgnR92cd5dBpIicWxCMB24jg71ML8XCCnYPZ0kGS4QzDJNegNOgQj+HD66wHCQ0AMbyH4B0STfZWob9ikiq9XiMPTMguwJwqKglsieWi9dTt2PzHMwV90ybj4a/MAvbEXdME52Z26i+aUjGERPAcoYvKWI0IpSt9DH7Xg9Q9Uf0o5N0rC19iyeowQCr8Bj5afbGWqKCx5vc7UUpBXY9w2G4X8rN8uvjRbesj97y81l+wfHjoxudJAJb2pznQVwgfuLc3n+99neGwEEEuyuu4voWeraBxOgFgmmyKdgBVaJWby1hm62ztt7yQPzv8FiOHP8a7EhRWqVqYMnjf2nh8Nb7unmJUBOMTVTr/7/ZneH+2l05mGD+OBJDWjCRtgDNgJu3WF8Rdj6zEpn53QMImGIuTDU3w5GYLrHi007phlf7PZ410wohenfI0wBRod+2anBnAffiNlYx2hr6TiQpFHrB29Qfqqfby0VcCj68HG3W9CFzW6XdZrFV06mK4R/QlUWMHLQz7+s1/e9996lJQAZomOAQCgdT0O1i5AisBQ1aj8w1Hjw7F7JHwb6fxpVzSgMo4mhM/NJ0G1oDpV9aWqNVpoLX05r09RjX3h+L2m08zTazFA0i3S8SSEFRfOCuJrmS8tJvd35eiFS0NbH6CsyXRGpaKDH80kwapQOlZczVkUkHgC01mmZmnrLu97SIAeRNiWF+IWNpHq82r1+fsLT+zfPn9mzcv6u/YMnj26vYM6c69cnloPub868+PBnBK6/NacRGgZFQmnqzqgp4NNRUDQOP8OXWNaJLmpLdrgzN9trz8BX7e6WywuPiU2+fn4O/Dda++w/jC72PPy4EHyGfvubuzdgEkwKTA4MXq+hcuicXd6pU/lKREQfw+1Df3vy4MbZ4Tk5c8mqdZutfe878Ou3QmNfTItC7rHd0/tIt5BFMNng/6P829tXClocsT4EJZ3F8cjKpJQp6QGnPKRM76xnteaHNMNYF81g87WW3PrujLfUVhYX5waCMDUpJsFMaWBFgvf4nu36fNJHkIFhFkZC8K8dT129FGB4OEX0G/fu3vRL/3PQjGvCDVjqg/L46uFdV4Zu3b+lf+Hu3X7Yixd794KLnSFfioKIQNRjxoHSTAQBSzp8hsqXq5ILIIG+JBfuh6WkBIMgo0Mk1z9txkCovAdvQWYmeCEr4H726uPij25dv3ZW3rzZY9OTXj2+cXrbKu++fef+w4cHz4Lm4r+Ds1AjaRQi0sIq/XiFxmsAb1OSjQoGp/OkcrMUibo+LJ2qmpApshXU2p6fm+nzZZiBr0ifm+Q9mUkajg68J4s3O3fRSR1iDvwW/HYMKu0PsUdR0bFUzvlOK8QORA29P3Fn8VgROVbVNDETOIZDsJdGkFeC93Z0tQSqFzbOXb76xIVEdqrFy+stVxmtNEmpSCYcOmc4vn38+n958/T6+UNagf1yLzIqJLfUZAC1Ru8YzlDYng9POLacT0im5EZrzPlh8V7ANJrVzs8G3WDSqBqAHybhtU8HZqqNYq2ISRMmfUQpI+YTpEZoViLzzJQlA2I3ZTNFTs+2q4JDsZEr5VPAUEYz0mXcU2tvK/0y/yI9v5EH9YHsLAbNHi+EULJEDEykfViLorF7xQUw9kitwcHANo0iLFsjDVtIio5BlWGcOVs1bGJGr1kymTPzWY2Q6ZQOhSNRcdrcC20lm9iT79Rwc93pf43lPgXZ525tS4m8UhUtCFU1Ehw7vmNgcFyT1jAnsJphdxDWqqGKoT0S27Wxhu4b6tHIVpMgpoUeUxZAX2s77lXziC4fgx90R+UIeAssPYBWIBCbQXnKZTfb7qs/6Lh1uRgBkHkt+HcgTgphfK8/YTPp90tTXpd9IRZiYz1M2POzTtfeClLIBHmpiIyEkS62VEfccMg242zI0fuinRgnqY41LKQqL3GopjkZOdD/fAxrtfueO+FUofpdkyyw67WaB7Yb1QzxYjZg1Hp5dZmNhhxd9FWaF+5wt1h1aLiWXzFfUSWzAiymZ/YPggYImheEn/B3+8bS9VoafarJSxUGnYSQMnQwPBUobKaLKQYJe/Vivyc5CWEFJu0T6XR+Qtc4XQ+GkOiWtYeskHgrXPVEZFPWjYEkGn+a1kYIFa00TeaNDSWZUIGWLJ5G3seyYFOmm8AEpstr7ltBzSpBhGFQXf6qvu0IJCOG83qFRNRORyR3TMZQqCiXikQ1roJVQZwd5ArfoLGpsV1bsGrOGQc1omCKTQHwcYZlrHO/TZ1L9PnjdPEu8/kaTu+Ahyi8GPwsgPh99MGhF+wmvyd21SfB8hXYW7732hwkssQkDMF2W5Uf0WhO9LlhpkoFAkfiJT/z8vf6yExMFc9JWK70sEKkp8WI7bwF9WBqu3UykPE0d2XkbXKSz08lWxerGmgypNOxYX0ikWDVfpOKcqd12991TwX0ga6mMUChY3szLg0raskJr5suBiTUsZUwNKSsNM19TfN3kbcgKTu+tGCqcQ0qYugVKcCljyJzmBUrZlxH1UwhchMlrhIMv0bJfQAV3P/xkLdATpg3iFCsTsr5BHwgUsCWOf4veYQS6EaTgZ8PZVhgN6xmMSwyZFYYxMxF8uCrSO7L+FI3xvaE+/fagTwjcZRIngnCD2IRPN+ggt9vjT2spZJsxFgORmD0sIw7rsGolu9VWO6MRgVcV+WtKlmWQjz8mr1RrY4/xDWU9pUGS27PSr13SxIig2K1JerYa0xBKAVLi5BJQvcpy42cMac5wxpHTo6Gy0TGpgyDoZREkyIV2BxWA2sOM0Pfq+OSX/kaJFX5N/C6521242WoXqRVphVeWiEFvfPikkNqbGTP39n/qjSu+v0XjEhNwLMSrlV0eJ2HhrfdGjVc9g3hGg34mR0qcgMGvIyD3n9XmPCNUdflK/31ZCh5tzsShAuLrvotthl91gp1fPHmQscgoo7sMFbAwOMxcm1w4DeRT0PXwXBCjEF1rxkuzImsJ3RoenpW2AIvtgjsK41hnqFCwrdttr/wqjlA6WJilU0PZGNypyopd2XCRBDQRjTk/o/72LnYFGX70uGelZSNAz4YK/Nsk24UB5jqxZbDL8IvRvGpz0VLW6WKrQRJLSxJRmxyH/EV2wmTRMEGuj7MtHOJBBoShWMZAw5/xCgRCnZiaAOHYsVUBkgluMTApSsSXZexpjKkxQ7FSfgD9/QaCU7alwxJwRoXMMM4nTmOMA9jh2bZnHIepsjdem3YgK1UBc+dG9IBvUsAAlvejn0t2fEP9Ky1UlaWz/RVHYipIJsrG07JgAXgR+BHVHdueNBWpUtrKjNsKWc1yJpUKk2JI88DLt5aWrEj7kbKgkBjPF86HnLdiWaI3UfOAdXVoKfE6bnOOXSJpE/YdXwzndHAU966KpK8gRUlpmEgucFepavUr9JK09WkDL9JZWcdZu+RRoI6gdAFh37Xh/L2P0oxK2Vjyek2Llg9fDQ2jFmjJZlJa5pa4jFXyO3EcodyuEmLUnUukTEBD4dTpdRNm8FsDgIbBNMDKkrBtnUqHRYufLsWa1RNDIff1Q8GsaSEFdQ9nPpYbBk4irTFv2ZtMScTkC3MbPjqg0iXyt/+6A7m0TRoWPFamO3h24AJo9HmU33gHi0WuwOH2Nhbu/oe6F6jgTwL0V3Hfzl6eiUfLBb0kRDq8JWrJaUrqYS/ieB8ohtewqlTkRuiiTb80Fk+Z+RyYEfbpEzLNHsulmfISdGMTYx4OIgbEOqGhhqzEUiThBT2T83El9s+z2MoXJ/eDgdKSzFmlh1seTTgyvlC0ohsyXxAWaeqhFOyBgmupqXRxem9zmCsOkgnQr7sEGGOmNXiBIlO7IdJN7xGI7y3UYxIhqCLOAmUdVqivkqbji8ZTgsji4L+JH1UTzyO8MLkUZLCa4RIK+L2HKSS1DQ65c2RTAfyLU/jQRzj24QBWX7wQLx04qS53/LrzvsCxYuGB3Sh+7Dx6IxyFYz5BrLyNrbjuAB3q/gRIc9djJfBqpI9oahxiFX4O/i72sI0idQg0fhKISgaS2b14QPGIcl0w9jXV1SbcMnyDdFXjc3WTCB+NBIamwlQfd9CYxqA46ZRgZVH7CNGcqdZRA9YUYlJFAn6VNLKUj5b6DNPBCveCANpZHldS691ajqSaAvXTA/9lstV0tJcT5a7eXoWwnQhRkQSasRKoaWwNFBBIFD5HoF+GDsiiVN7FMZtJ6Z8JdZ0c9LAT1BepDmajCpE9KCsawsxNIw0jFqI0EAlakJytenLtkqj7Li6toGWFI4PR5cRskqXYlISlpuMf2VELfXWQCKLyAoSzLEJ0rTrOW9B3L5jHkjsDKjWrFQmYI1YYzSABmMMo8fqPMCUwKSwH8trfeIBfbTIYfJLJbp+n6UBS1wX4HtiNYlnOHwVwljM4vejyaL074XKv1q+qvLvGyRI1X1rPBvMvdpQY08igRpaWzRyAANDyU5GsEj6CZKJDQIbfGK+HGW78rrHA1XA3FyXxJCDnlK+LeOrQ3mQbUqJGObeMKVn5smCfcWe3G21LPOiYzTGioUpGIc81Vq7pFRJpSxMB7ZUXqDLXDGQSBlsI1Na7CecdaLKhOvubQLNbblNdjDqwEAlkoJLH5YlTeW7NjexzkzctvYaOFWI7Wg3jQekw9pssYnl+Bv8zSbDaexNVtJfyiSHeVOZNkuNVFjIyFWmUFvMhvF6SbKUkKN5w8RhpcETVIIN7IG9SsIdGqNk0bxUIm2yvT2KpZLx7GB7dieEAfjeT77UmJXNJbO3OiC2fZWf/fMmvwxb2VPTu/+Av0o/uwiL33Dx5Z1r/vUg55HlEOnjN+BfwxR/2ZlD53CPGJXJvePMeFH/jcEIS6srX0HAB+qGZBoGrTBdzOCkFqy2qOiqrphWLn3uB760Ue1SENZGGSX2uMZHU5d0XWAwtvW1Qzw2AxsCYTlcx7EwVjWmoqg0niZwvIqT2dz3H4m8xHSJ5ps3PPkqoIkuusjYHJp2oQglGhz+kRqHpBOrtp3RpM7BxvhVRAn2xXwtJY9TUsudIK4iKMUoSKGoieIGIaCpMcxAdUBV6cDEnucWoJEXbZNnHYmaxrwGG5KgJjFmpBSrHfvlhg+sR1rbmg+tJE58K5FaE4EGbUHE1cIO0MhE5Jml5P6kjaVSA9sygs1jwp2KwtcM2uWORKg9TA5G6ArIQI4sdtnqGPWj8zMMDyDxe8He8zUOVeJ779xBm+cDJy0LADTxmT0ZFAoq/Vk5JPzgA/XJV3GiyJnncBHgeXLv+c9ha4Y2t8vTyeTtR+66Le88AozBeMCQqT/Z3FArqlzpcrOA5cSo0dN0XXlkHXOHMefOvfowR7CL8+IHti4fu6VDoMIu+GM/pydfqJY2AVYWtAfevxHn66//eoO+9BEnLX6hKdDP7x0BCCJEMUcfm35IAnxhIvj1C6L/x5NHBNjJiyVgQ+dns70PTdm0X4NfED0AYry4F8aiTM/vXXuor6KudaTycJYmx8M0J/xvGoDT2xwOoAST5FYXlOg6g2oNjyzbDRNBFCyWAwu5LDATgnZLJ9XazI1ij9sRPBYV3RBnk+9MoMvg+Fhj27WhXHZFnKZ5C/L7xY0Gydvadk6ALcNY1dwfyp89fnjvDr31AxNlX9k67A77BAvnRQXqyt8++JfDf0olJ1w1yHJtVq0wEa3rUSQGDqUB3rhWgGR8Kpc1y/VpfLnCsZ0BL5lsDLiuSjynnIkvWPCbpJqjoTFgkrXVM4oMgy95wIgdxw9jURIntDPViVEWXv9Ar4rPv8PlBPDa9r/F6RKd/+pf6RZXN+Aqu9yHNzcV2GN7/2kE3OYGapgtPtXDlSSsGLpJ965H/UNdVlbtZUJfkifcwUkAeFVfEODH0ikGTPWoqKp3BqljR4dJNkLjv/0Sr+rsho1P+ldsb/QBrWkKoaqCcMzdHzQ2Lz4BkjilnY/ZDyUfdAlVtkS7WIqjYHeYOlGCs8KJvzXDOpt5wGrvfd47+UJALWeA2WH0CXtrxtvkBVsnWSv9IHpK7QxSIWVqUizFUemDI57WT+As+zWBA5wurMrWALQAu3eb6Dv2nQRKBUbFvgpYwDrX9M/89QvgDYH4j/oZkl8CbiFMysCqDdo7T/cms30f7nsf3g0wwNxqLRe+EOeTZvG+Am6LTQNuHSp4v2bAEJwHN4t75wAeAbTtDHTJQ/0P4jEAjf7WCOqm469tgDt40PLzQg+zTV59620bq7Pvtt6+ATVsmLAFdN1nqVHZ2gjBzJncFTlWQS3pTz02U7vF5vaBZIUjEF5HWWBqyLZYlWtcfV6/p1r5XVHPVkUMLw2+2G7UKvXGqWqN+SIwJlMqay8GgbWWYeWnEnh1GmKLyjM/7fZuexkurZdBnVcMtSl1OsZ3rtMKOLyj+ilXV8lKepztF0ezHzESUdcG1uthhyQh7XuAyPatk3tXIsfGM3/qmCfkrLtXtC/sRXXq8qA7FViGbQyHeorYQkjfl+5+cTQ7GLSXv8uGxWSyHJLq9n468B2xXnnCbpjPJiesG/anMQb7kObtC5IbXKej8yBhafHb9HJe54xDA5fSOSShfL/6CUexZTwYDgfj/TEOEDyij6UF94LmaWsdjU79CHZ1ph6/63j+9JiNRXWW0GTokiQZrJG8tG1pZLSZ1V5viJabX9ONv2bQxnqv756ProG0l9ZsnnvdA/7oFl0nc68YN0qmfr44OiV1+eUzHqGfdDiypD/8tAgkdv9rom9Ewu999BrcxHm1/5nU8YMPX+sS3Bl+i9cffVyEctf6wOsJEBCjCduyxoUNLlAyWyJT0QrvxfZXXuPKwWfWWFdT3mfKv1YQ//ZTQ/DXK+Ydlr3L2utW9U/Cvv5fOAMDcUViwLVbxKV/e2ddfAW4F6DEieOCAujXu19/9/nxizF4btGPVuas/9ext/flW586Nz7IFMfFl9ewc+O/8RKe+6PVS3R+CzALXIWuP/KSAJz1nLJ+xrGUCnZg9wugH5z89XdXzPU/+AUQ8//8Bfy1zWyBjRJ4vO8XUqE/VP97tRFUu38IXX+09j0I/Dfy9rr93npEsU33WwfhSdT+0p//n/e/r/UFVlp/6zH4yAZQDffin764oiAGHy5af+OrSmApc/uj8//v5sA2C4ZgOG7e7nyC9irGGvbdE0eFfhXggWFkISjk5WPq4YHpSCe/1Ztg3HQetwzGHmnmZ/d/3jEJIAPS6cfKV9q3qQRliE4p81PzD0IAdvpxdzF6PvAZ/wOG4Feg3qo13r9v1F5gl/UfoY4vr9NiLzJLw+AKGP1VzwS3e0JPNlAg3gg7ewXP+5BWF9bBYdasgmVnGtmQyqCdpKbMs0jxkm7QS65gg5AdLGAE2eIsaQMd+XFooIrVSCL7ASGaTlNJxgjCqSsSr9kCf7MAVwEjzljNek0NiLyqm74czmrT29CK6876YGigsPC/NGuIQ37y2mlZ2zhRCczFc4Zcc/vb1b6ZD+5r08vDyu2gWuEfslKAxLzQIuHHgghXRnwnPN2aGuE6GhGy1QmLUbs6No1qQGHAFPTstVRWsB7C+gLa9E8qtLcY7NZNdDAw9qYxLmbktjUTbFmmxro+jjqacDn0kedYgtDQUreGj9ATi2MUqix03WwwWAOnN4JUTtMMUtkPrnRUdMUPDr0rs5TOSvChAir42p4zNWozqxrijdDRJdfATZzYZUxwnWQTHgkiTzWepfgZ5T7y0kA0PeM/9kHNCoc2Ni+y5SKrJOd26K6gbIWEjNOOYFp6cU5QbddVy4VSe1vHjBoqyY0LrrJG0COqv1jMxvxQXZvFKU48bcNEOvemlY4RE8Zy3EuhIXPR/IDNcLW53ABasaJAIFDHC7jduDLe3cyM0w8wNV2XBoVUnmvKoqhnttXnVxmrFKlldWdzLyokD5i7Zj7Bz7Zwwn4rhj7rsjPBN+1AdlS4CnbCTrL43pmr77ZJNPW1IGUSRn71wXqTlzX08lCRRoM9XEKy+l/Uts77AzCE+oAgxjpnbLaNpYV/q/fQqj1LPsQYMRDgtnjLlNkTTeCnYBfCQZi12q1GGjm6qnLMKPSQ4w8MFn23NRRCh2PDMC0vzBqgitsyzEdq7nCG58ed0Vc1mS2UmqyY3awUO2IJr/RiBVtqkE5ugEEH62RLAR1sOH6rfbZwzOrKd8EmWd5qtnK9mWV1PdIvbGOEHB8vDMffSDb0qwG1BvtFfAdaQccNwPKc69Sg1zokaRHqaK6gi8jr6dud+jtyaKbEK6qmKwJjI4P+txMNftzGquMDmedGb58fEaI9I9RpuYhAZPP8bnAdCcJjka3Ew29eJixBu/NM52WtjS4il+vsyaheH7ngnXoXQXP9b3W2u2uiBBJVSpari9+0S6WDzv/SdEYh3ZzVTwW+/R7oruVGa82mrmOZ/7XHu2C4iAqm21f/9xeKQOfGvTCOWd0JFUedRK5C+NC3MwNNpqD/TofbiKz/N7q0wXn/276Iz0O+RFiWypWhagzFuxm+RSJWrSE08PfxfwAsXoaYvFgH7yx3Pgs6iMYG9hDbac5XUqGdmp1c7rKzIlxTVDuQlR4hwWESrjXvLk5HZuARhf0oMc2MpM36QCAcUJjkOEaox9ztycni1BquI758CTrrIMUvcxTZibrCE4tyZ+XBocJbfYrzbLGTe6E0h7sWQ7DuqdZ01NnahisafMWqNAQBUTiADKV8jBazlcYBOjawKbgPD8KDbyVqbD/7xf/440+4joDjZdP4SlcU8EoCWoV2OM4poC1TP/NVpRBP2vDlviynUhQdMYCRG0Vwfo3d6rc8T/Ruq8AW/nDxNT/jgbYAcUaMCIl0FsiwdY3Mf7YLV8JQu+LfCEIKuxPEpLw/zQ8UsLedphYBt1bglAdIyBi/h2Q41niiAXaXguMhy+rF5/VKcvCITL3CE5vIv0/AHnMWOsGUgt7og/6AxVLcD0HPoZ5ScC5j9vnbcNzw7Cu23AAlJEYjF/MXmnpD0P3lNj07FEiss6E1of/8Fb81t78XtBX9AafBP9vGxN5o6GP2mFMbc+1Z6hre1Fix+FyITab9L7KANlJgzjh0yHRlBH6i+xuzfK0c5EO+Mv+aarDFykzCEj45MXzhYnGLlU2SVFYpxQCM6jCw0wGIUXw9bqUZa0AxezRNwGd2GPVOaE6iqqOLbGCj0UCPVYFATGLPGZhgf7cq7dBUVUxl/nhm+AqXSh6Trna83R6cUpYjUEc+t4E4KyWZkCMxDION7s8UODRltzklHaZN224OTyo1skgfB9xF7HitmeElytr4qFq4/reYcLfvbfT3wJ+n/hvAguMc2FfqJsxIFK/1YZL1gkICZEaBS4tGNap0JVXWa9kb1EE9TqRo4Qeo6gFL49cg0cI945Glt8+lBj9S5aBsJE6kxMWR9sMnK7AE+ZUc6DDOCwWK5tjab5siNlTVlxc+V8uT314oZInxHtOOLEgkjdBTxEE3DdGbPTYiFnfTwbJmeqj1cKsiH2oAfpzrHJcCzdhJ/+kbS4HqUnlBPPxUWt0NQd1968I8CrYmA82yzLMIi0Git8x45ddayRnbJHeFImcMT+wNOnE2ktSyLkuFCJFafKf6NtHImUf1G69xuX+1VtaFvA/fiWQ5SGNpCqzvRInp5lCEYfTAY2o6MdzHUqlAZBvcarHsmzZ7Nv1Gk2zqOgjw+Nv9AatMe1l2lqyyYt3EDpWOrYbSqey56xWxliyfKQxBTKhW636ySI9VmFEG2Ut+E12Uxk2I96UIfK8pbrVMc9A0NpP2Ol6L4yY8/nA7Cx1sNB7ve67r2LYD5zhVhqqU26Tleflq0M5u0mxU0+EwpoEdE01ybD+WpfWhH/0Iuxn/lf7ivf9OeHt7fS59j4S+M3++UcYJS8/P39lOc+H1fngt1/jN1U/DcfUjiOj3o7T6ZPmZ5QIypWfKD3+Q7Z+WVd0ZgM7l4nIb9IH3YFNP9qSFsIFvbGdVoTfYnlbXOovCjVR+A27xzfLdG2xjazrlLL73olBdQx9/EFrtbEFshlxcrenHpH3A2GfIMNM/RPHuxDwGs8vpnpu8xNEpNL2uabOCYiWEJldVNcT6K0NWXhVFi8dPP/xUvHwVZOfdEgTzw48++OOWY+/y61NEBZe5tkQsw0UayLvb5hkyP/gcevDD4J1GbF8n6Ksw9lSveFBIzZlpOmy9VO8m6Jz1JK+262boR+dkUX+gc2/dMXG10fvDPbQ2I2xucKd4Qa8UWVYUVfbwezL4TPQ+HXdaglOY5dzbBq2N+cZ2oVozi7+lD0vt+hY9LFa319dg3a9f6s2Lw8FmHp5iT71ZgA5Jz3c5yyv9RidZA0oHHGzoO0Yy0484QTXt4hLuwEyvka6Gdgo4viRxfQ+M3DIfqSXY6o9UWb7Sbg0qRzXm7MjiWzLxVKadNRp/P07D0+LVnTT7dHUC370h5QBKrOwe/1X9vPN/W6gmblKormzb8mTF2PmvicrBt+2gkn39FkdIltFUG2uazWUM8hcYqqycDA9HKNEduQmP07UXW6nZERCire6ZFrgslpmgbta9PG7mOSRY5lp+7t/4umPbv+Usa9ed7oEGy2FFfJDsH4j+7MQWuf5svsjQYjZrYhvxl/4t7A2NyRvEDtoZcSFtkCSK424j4UsrNlpPnkImHSPiBMM/CnMaGExDCnzHTF3TxKDvjCoiEQwZXtOkPOL7EyVhRth7OqlkulJKYCIRiDBd0ktkEHNhgIQIwrCDQubE9Xw0cWwbGchyHLH9Al2Kdh6aC9kKjKWxgKxSCWFNEIxdrNqEAYW0CU7BNqvhrGIlQTDXTDUkoedkEgHMGO4qExlgrfVsLzgKzkQflb9V9NJWFL1u3ds/GFK4amNl59X2NPyuoi9u07TORufHy5XJc9n8yD//B9kFMsKenH7gtjwGFq2MjFdhAo0W8k5H8iH0+eSP3UqHc0hCLU++0F+y1Wqr9XkkoZ+HV7zkJHxvQQxxUjnB2WP49Yp2iqFzP75Akyl69f32YcW4gP/SK2G7/bIHAh8ZEZuZNr11mO8lVFE5U2QZw9jE0Tt17UbTZc5LecQyRsSYWmK5dhZpSUvDjiGizpHMijksmunJtqWChLSpdgMviYhNq4wfxrQoqXvC44wj8LDv+1ehNywd85qXFnc0jWLZWtSJeQl5yURlgrXSFy3hATpLTUQ133DcBqmewtrR+UlwSdPCmC2Cjov6tWR1BQjoFJMPPDHB5X9wDs6HHJMYUQxovIZUFPGHrlN0udvxob8ooXADb5hn1GTAhue63qIvIT9U9cgysOdk60BbEC6Heq4g0YlQwHxCaqzv+glUF3HQSGMaRVX7ky0sojUpuoUfn1GZzdiJTYxh7agXCXem1bGkbsi2mkhipAVVle05WRehHXnZTjrzgv6AaNeWnAuecKjjPKfpa4XN6RM/D/UPwANvXSRJiHx2m0XRczShpuPHU8zaM4w956P4zef22vstOK2eBgBoLym5CS8lnep0ysIaSiKWqvkXjX4JEQ3DnBJ3Jpl/xbCFtxezKiQZ3ed/Ma6AmkBWh42KLHYnPAXniVIj4eJKhnbLCoJAS3zN52u5fnVxCREOWxnnbas2didTQVWOUVOVC26nYKOeRxvut0SloolzI0kkWf/fPyoNmjz5jj5bMgvd97Dlgx0dyCaN7AS8Qp8+AZwpCs5VJtgBKGBu3AkugE4515Dg7BH8Dji1kQfzPXjz/QaYKMDuN3/SA2GA1kMpgA81U3hSlHDwuBjD49sxXAKC8S1HkSfqqiWAMC0/VxUr7G/YHTe01ftrAZqX0nPWVNjjkjJcljuId7kDNwmwyXmxrQDykPrDAIeNvpRDgYPNpOjQ0SWJPtJdzcozhls+tAsunyjoEHzPRjbdaOqduJ4XSg4xH3axtqUnTM1XGSVSNmw7umx4iozrHN4JNNYRsuOuhxRSoIkvn0xHFHk2CKdi/7zaaCFAa4mPBA5dlkbav0Xj+GfAz74+lTn00/+e5JqFkWFy3L4HBhhAwH+ykv2xq9qw90TI9m/iLKFh4pnIQNdW79Umn3LOEud2Un7mpIqjBFnxccy27tCTiIHFB/h5Sfu44PNxlHmpTbW2HI+dzc/XM2Jt/VMZDvLd5i9KMcf/RkkJx4NbteS0tsE6xWz6mEwBVvPZJSMYPFFlVYJ7yGeUBfCcsl6kb934MQoD16GReysCmdiBykVHIQLASwPIMVYlCJBlO55pacmH9nyZiKbWFrlaO7VYl6wgzz22M859zwswykG06oUAs3mGP9FgZY6iSx5wmhBG4wmL0DKsldOwdEqehJyQPxSAN1gCDxzBAPggfMs4pYpz4sE0xezSRpAOFmlkn2q2yWeaVo4o23huJgUp6gL2cthcY7pwp0sEt2wUnDWCEglAhu4c5n6TOcZ5tNpo4W0ykeCeIJv4FKRcdOZznRP8s3HB54yYOLg0fDXzDdQrZRnwUxYXI7+QhoJBcDpyBMSZgp5m9jnKOVHgICMw3oXnPpaeEWBOEvja724A4rvjtOqEzV6Bo+M5JuKlETptJHOKQzaKzghIwwIjJJtqUbl6FEDcjqeWjXquwHTEIQoJcIY5BJDmrYfNZo/LnxJ3uDmwD1npAR0cLAQfm9FqwD8TBLIEenQZyNUinSUb5LQg6ugAPpd6M4rwMyGK4YSI4iLDj5J4ZESUzNLnKIWbUwM5AizdBgJYoosioNFGMTA2M4oDQ5KQBBoRJQOLIkoBnuAoFWjEURoYEkTpwGDqMWAy+sIEBnCOQgXSEOJo57gt5suRIRpp7XnGKA+84k0uWuFxRCaefaIsBXKwN75Aplei3jjmsqk/aVG6pD2XSO0nEybLgtS1M2xeY7Zg3g1u7gzFcmho1fPSXI58rq5QsWzelGTGkXfjteXJQohVrJBWltnyeEqQJVtJt3LFkjIpluy6EEHAlxcfInfpk8UJUCJBi8T3lhByUjGUQnK6NHfF8/BiOEVjjuLhahcQ8zFfRDCcNyaLoB+isiFXMpT8KCXDLoXDct0CLlPgZ8txLyyRzkvGOhHvtSLFnJdvyPZKlq/pTZ3Lvj1lrydyhbm4ocUSLv5TZgnA9q4Gg8vS7ZNhv1pOhDI5+8JFliuuuc6VG3cebrjplts8EwFevBMJPkRmEbvjrmz3rXLAQb5+8OMvQCCJBx5SeyRIsBChvgkjlSNPvlyEApuMIVMo1ldyGsVmKxJHYaxxHtMqVZaRUGJ8RiEqTKBMNKjEK5dgjrl0KmxW6ZCJfko0SZJlJpuiit5880w1zXTJvjsmJQjEQEw446z/NPjvn376OPbJ3f4Et9eBYgELWcRiPIFIIlOoNDqDyWJzuG2RFhTwBZGzIgoZ4LJmYw+Srextcd4SbBSGIvDCcFiTaEwsqWYKF+mCi5q1OKLVLrudchoZI0IO6JaqtsJyNRaa4bNFTqLG2WLr4oLjl9+OErBja7U0jaICocUtcLjhhR9BhBFFHEmkkUUeRZRRRR1NtFaK8ZcnXniq3ctNK9lU0VbdVR3b2RQWCqUmoUQoisyoau5AhPkNzZUNwSxPlFdRLFF4Z+R6w6KImtKakSZLw4bbgPjNSOHjdlaim5uqz72Obl7E/BwDaJiIX2mAm/1wl2Bqe3gM/iil2MDfmBQbU5vCTUwPPpYnAN4EQOAApwhoRkAAwDoHPEVAQECziOq0b1YxXeKM5GkmYWrt2P+I2C79U47gM4VyP9ea9MMTWKXOeGZG/r5RcFYVi0Uy2VFZTHlbxe1uKwNPShKhkhmvQPyvB63VfzLBEkR5ZWeHwf1sMXoFE6Ij3FB1sqk0vra5ub68olkmiqtq7vgJC7apDYoVvkSGfWVcG/CnFvCWM8nTJidBF06534BEGR/4bLSWF/kXAAAA) format('woff2');
}
@font-face {
  font-family:'Newsreader'; font-weight:400 700; font-style:normal; font-display:swap;
  src:url(data:font/woff2;base64,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) format('woff2');
}
:root{
  --accent:#c96442; --accent-2:#d97757;
  --canvas:#ebe8e0; --panel:#fbfaf7; --card:#ffffff;
  --ink:#2a2824; --ink-2:#6c685f; --ink-3:#9d988b;
  --line:#e7e2d7; --field:#f1eee7;
  --ok:#4f7b5e; --warn:#b9702b; --danger:#c03a3a; --danger-bg:#fbeaea;
  --r-card:14px; --r-btn:11px;
  --font:'Hanken Grotesk',-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;
  --serif:'Newsreader',Georgia,"Iowan Old Style","Palatino Linotype",serif;
}
/* Default SELALU terang, terlepas dari prefers-color-scheme HP pelanggan —
   demografi pelanggan (30an+) lebih terbiasa tampilan terang; gelap cuma
   lewat toggle manual (tombol matahari/bulan) di bawah, bukan otomatis. */
:root[data-theme="dark"]{
  --canvas:#161412; --panel:#211e1c; --card:#2a2623;
  --ink:#ece7dd; --ink-2:#a8a298; --ink-3:#726c63;
  --line:#383330; --field:#1c1917;
  --ok:#6fa380; --warn:#d39a52; --danger:#e0685f; --danger-bg:#3a2320;
}
:root[data-theme="light"]{
  --canvas:#ebe8e0; --panel:#fbfaf7; --card:#ffffff;
  --ink:#2a2824; --ink-2:#6c685f; --ink-3:#9d988b;
  --line:#e7e2d7; --field:#f1eee7;
  --ok:#4f7b5e; --warn:#b9702b; --danger:#c03a3a; --danger-bg:#fbeaea;
}
*,*::before,*::after{box-sizing:border-box;}
html,body{margin:0;height:100%;}
body{
  font-family:var(--font); background:var(--canvas); color:var(--ink);
  -webkit-font-smoothing:antialiased; display:flex; justify-content:center;
}
/* Blueprint §2 — SATU halaman, DUA mode. Kedua <section> ada di DOM sejak
   awal (BUKAN lazy-render), yang berubah cuma class `order-mode` di #app,
   dianimasikan murni CSS. Tidak ada navigasi/reload, jadi state keranjang,
   isian nama/HP, dan posisi scroll daftar tidak pernah hilang saat pindah
   mode — sekaligus bikin transisinya bebas flicker. */
#app{width:100%;max-width:480px;height:100vh;background:var(--panel);
  position:relative;overflow:hidden;}
@supports (height:100dvh){ #app{height:100dvh;} }
.page{position:absolute;inset:0;display:flex;flex-direction:column;
  background:var(--panel);
  transition:transform .34s cubic-bezier(.22,.61,.36,1),opacity .24s ease,
             visibility 0s linear .34s;}
/* Halaman yang TERLIHAT selalu dapat `visibility 0s` (tanpa delay), yang
   TERSEMBUNYI dapat delay .34s — kalau delay ini ikut terpasang di state
   terlihat, halaman tujuan baru muncul setelah animasi selesai (terasa
   patah). Makanya keempat state ditulis eksplisit, bukan diwarisi. */
.page-menu{transform:translateX(0);opacity:1;visibility:visible;
  transition:transform .34s cubic-bezier(.22,.61,.36,1),opacity .24s ease,visibility 0s;}
.page-order{transform:translateX(100%);opacity:0;visibility:hidden;}
#app.order-mode .page-menu{transform:translateX(-12%);opacity:0;visibility:hidden;
  transition:transform .34s cubic-bezier(.22,.61,.36,1),opacity .24s ease,
             visibility 0s linear .34s;}
#app.order-mode .page-order{transform:translateX(0);opacity:1;visibility:visible;
  transition:transform .34s cubic-bezier(.22,.61,.36,1),opacity .24s ease,visibility 0s;}
/* Blueprint §6 — state "tutup": katalog tanpa produk sama sekali tampil
   grayscale + redup, bukan layar kosong/error generik. */
#app.closed .list{filter:grayscale(1);opacity:.45;pointer-events:none;}
.topbar{padding:16px 16px 12px;border-bottom:1px solid var(--line);
  background:var(--panel);flex-shrink:0;
  display:flex;align-items:flex-start;justify-content:space-between;gap:10px;}
.tb-store{font-family:var(--serif);font-size:22px;font-weight:600;}
.tb-sub{font-size:13px;color:var(--ink-3);margin-top:3px;}
.theme-btn{flex-shrink:0;width:38px;height:38px;border:1px solid var(--line);
  background:var(--field);color:var(--ink-2);border-radius:999px;cursor:pointer;
  display:flex;align-items:center;justify-content:center;}
.theme-btn svg{width:19px;height:19px;}
.topbar-btns{display:flex;gap:8px;flex-shrink:0;}
/* Angka amount besar berputar seperti roll mesin slot (lihat rollSet()):
   tiap digit yang BERUBAH memutar strip digit acak lalu mendarat di nilai
   baru; arah naik/turun acak. Hanya transform (GPU), hanya digit yang
   berubah, ditiadakan saat prefers-reduced-motion. */
.roll{display:flex;white-space:pre;line-height:1.15;}
/* Tiap karakter jadi sel flex sendiri: SPASI di sel flex dgn white-space bawaan
   (mis. .mb-total{nowrap}) runtuh ke lebar 0 -> "Rp" melonjak 4-6px saat roll
   dimulai/selesai. Paksa pre di semua sel supaya lebar spasi tetap utuh. */
.roll>span{white-space:pre;}
.rd{display:inline-block;height:1.15em;overflow:hidden;}
.rs{display:block;will-change:transform;}
.rs i{display:block;font-style:normal;height:1.15em;line-height:1.15;}
.mb-total.roll{justify-content:flex-end;}
#app:not(.order-mode) .mb-total.roll{justify-content:flex-start;}
.grand .gv.roll{justify-content:flex-end;}
.code-err{min-height:18px;margin:6px 0 10px;font-size:12.5px;color:var(--danger);}
.btn-ok{background:var(--accent);color:#fff;}
/* Item 79 M2 — toggle List/Tile, gaya sama persis .theme-btn (lingkaran
   38px, sebelahan di topbar). */
.layout-btn{flex-shrink:0;width:38px;height:38px;border:1px solid var(--line);
  background:var(--field);color:var(--ink-2);border-radius:999px;cursor:pointer;
  display:flex;align-items:center;justify-content:center;}
.layout-btn svg{width:18px;height:18px;}
/* ── Halaman awal (landing) + mode daftar ─────────────────────────────
   Satu section #pageMenu, dua keadaan lewat atribut data-view:
   "landing" (hero + kolom cari besar + chip kategori) dan "list" (header
   kecil, kolom cari menempel, daftar produk). Seluruh isi menu ada di SATU
   scroller (#menuScroll) supaya kolom cari bisa `position:sticky`, dan
   input TIDAK pernah dipindah DOM-nya (fokus & kursor aman saat mengetik).
   Transisi antar-keadaan memakai teknik FLIP (lihat applyState di JS):
   layout berganti sekali, lalu elemen yang bergeser dianimasikan HANYA
   dengan transform/opacity — tidak ada animasi height/top/margin. */
:root{
  --blob1:rgba(242,184,160,.55); --blob2:rgba(246,217,168,.5);
  --shadow-s:0 6px 24px rgba(90,60,30,.12); --accsoft:rgba(201,100,66,.13);
  --ease:cubic-bezier(.22,.61,.36,1);
}
:root[data-theme="dark"]{
  --blob1:rgba(150,72,46,.42); --blob2:rgba(130,100,44,.30);
  --shadow-s:0 6px 24px rgba(0,0,0,.4); --accsoft:rgba(224,133,95,.16);
}
:root[data-theme="light"]{
  --blob1:rgba(242,184,160,.55); --blob2:rgba(246,217,168,.5);
  --shadow-s:0 6px 24px rgba(90,60,30,.12); --accsoft:rgba(201,100,66,.13);
}
[hidden]{display:none !important;}
.blobs{position:absolute;left:0;right:0;top:0;height:440px;pointer-events:none;z-index:0;
  background:radial-gradient(260px 260px at 0% 0%,var(--blob1),transparent 70%),
             radial-gradient(240px 240px at 100% 6%,var(--blob2),transparent 70%);
  transition:opacity .3s var(--ease);}
#pageMenu[data-view="list"] .blobs{opacity:.5;}
.menu-top{position:relative;z-index:5;flex-shrink:0;display:flex;align-items:center;
  justify-content:space-between;gap:8px;padding:12px 16px 6px;}
.tb-id{display:flex;align-items:center;gap:10px;min-width:0;flex:1;border:none;background:none;
  padding:4px 0;margin:-4px 0;text-align:left;color:inherit;font-family:inherit;cursor:default;}
.tb-id.clickable{cursor:pointer;}
/* Mode daftar: header mengecil (logo 42->35px, nama 22->18.5px, setara scale .84
   dulu) lewat ukuran sebenarnya, BUKAN transform: scale() menyisakan lebar
   tata letak penuh sehingga nama toko membungkus lebih banyak & keterangan
   status mengecil di bawah 11.5px. */
#pageMenu[data-view="list"] .tb-logo{width:35px;height:35px;border-radius:12px;font-size:17px;}
#pageMenu[data-view="list"] .menu-top .tb-store{font-size:18.5px;}
.tb-logo{width:42px;height:42px;border-radius:14px;background:var(--accent);color:#fff;
  font-family:var(--serif);font-weight:700;font-size:20px;display:flex;align-items:center;
  justify-content:center;flex-shrink:0;box-shadow:0 4px 12px rgba(201,100,66,.35);
  transition:width .28s var(--ease),height .28s var(--ease),font-size .28s var(--ease),border-radius .28s var(--ease);}
.tb-logo svg{width:72%;height:72%;display:block;}
.tb-txt{min-width:0;display:block;}
/* Nama toko boleh membungkus maks. 2 baris (bukan satu baris + "..."),
   status di bawahnya juga boleh membungkus: semua info header terbaca utuh
   di 320/360 walau tiga tombol ikon memakan ~130px. */
.menu-top .tb-store{display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;
  line-clamp:2;font-size:22px;line-height:1.12;letter-spacing:-.3px;
  white-space:normal;overflow:hidden;overflow-wrap:anywhere;transition:font-size .28s var(--ease);}
.tb-status{display:flex;align-items:flex-start;gap:8px;margin-top:4px;font-size:12px;
  line-height:1.3;color:var(--ink-2);white-space:normal;}
.tb-status .st-txt{min-width:0;overflow-wrap:anywhere;}
.tb-status .st-upd{display:block;}
.tb-status .nb{white-space:nowrap;}
/* Titik status: inti 10px + halo 4px. TIDAK boleh ada overflow:hidden di
   induknya (halo dulu terpotong di kiri); margin kiri/atas memberi ruang
   halo di dalam kotak teks, sejajar dgn baris pertama teks. */
.st-dot{width:10px;height:10px;border-radius:50%;background:var(--ok);flex-shrink:0;
  margin:4px 0 0 4px;box-shadow:0 0 0 4px rgba(79,123,94,.22);}
.st-dot.closed{background:var(--danger);box-shadow:0 0 0 4px rgba(192,58,58,.2);}
.menu-top .topbar-btns{gap:6px;}
.menu-top .theme-btn,.menu-top .layout-btn,.menu-top .ann-btn{width:40px;height:40px;
  background:var(--card);box-shadow:0 2px 8px rgba(0,0,0,.06);}
.ann-btn{position:relative;flex-shrink:0;border:1px solid var(--line);color:var(--ink-2);
  border-radius:999px;cursor:pointer;display:flex;align-items:center;justify-content:center;padding:0;}
.ann-btn svg{width:19px;height:19px;}
.ann-dot{position:absolute;top:8px;right:9px;width:9px;height:9px;border-radius:50%;
  background:var(--accent);border:2px solid var(--card);}
.ann-btn.seen .ann-dot{display:none;}
.menu-scroll{position:relative;z-index:1;flex:1;overflow-y:auto;overflow-x:hidden;
  -webkit-overflow-scrolling:touch;}
.hero-block{display:none;text-align:center;padding:clamp(30px,13vh,120px) 20px 16px;}
@supports (height:100dvh){ .hero-block{padding-top:clamp(30px,13dvh,120px);} }
#pageMenu[data-view="landing"] .hero-block{display:block;}
.hero-block h2{margin:0 0 6px;font-family:var(--serif);font-size:27px;font-weight:600;
  line-height:1.15;letter-spacing:-.4px;}
.hero-block p{margin:0;font-size:13.5px;color:var(--ink-2);}
.sticky-head{position:sticky;top:0;z-index:3;}
.sticky-head::before{content:'';position:absolute;left:0;right:0;top:0;bottom:0;
  background:var(--panel);border-bottom:1px solid var(--line);opacity:0;pointer-events:none;
  transition:opacity .28s var(--ease);}
#pageMenu[data-view="list"] .sticky-head::before{opacity:1;}
.sticky-head>*{position:relative;}
.search-wrap{padding:8px 16px 10px;}
.search{display:flex;align-items:center;gap:8px;height:52px;background:var(--card);
  border:1.5px solid var(--line);border-radius:999px;padding:5px 5px 5px 16px;
  box-shadow:var(--shadow-s);position:relative;}
.search:focus-within{border-color:var(--accent);}
.search svg.mag{width:19px;height:19px;flex-shrink:0;opacity:.55;}
.q-box{position:relative;flex:1;min-width:0;height:100%;display:flex;align-items:center;}
.search input{width:100%;height:100%;border:none;background:transparent;font-size:16px;
  color:var(--ink);outline:none;font-family:var(--font);padding:0;min-width:0;}
.ph{position:absolute;left:0;right:0;top:0;bottom:0;pointer-events:none;overflow:hidden;
  font-size:16px;color:var(--ink-3);white-space:nowrap;}
.ph.off{display:none;}
.ph span{position:absolute;left:0;right:0;top:0;bottom:0;display:flex;align-items:center;
  overflow:hidden;white-space:nowrap;transition:transform .32s var(--ease),opacity .28s ease;}
.ph span i{display:flex;align-items:center;min-width:0;max-width:100%;font-style:normal;white-space:pre;}
/* Hanya NAMA produk yang boleh terpotong (...); "Cari" dan "? Tekan →" tetap utuh. */
.ph span i>em{flex-shrink:0;font-style:normal;}
.ph span b{flex-shrink:1;min-width:0;overflow:hidden;text-overflow:ellipsis;color:var(--ink-2);font-weight:600;}
.ph .ph-arr{width:15px;height:15px;margin-left:3px;color:var(--accent);}
.ph .cur{transform:none;opacity:1;}
.ph .up{transform:translateY(-70%);opacity:0;}
.ph .down{transform:translateY(70%);opacity:0;}
.ph .noanim{transition:none;}
.go{width:40px;height:40px;border-radius:50%;border:none;background:var(--accent);color:#fff;
  flex-shrink:0;display:flex;align-items:center;justify-content:center;cursor:pointer;padding:0;
  box-shadow:0 4px 12px rgba(201,100,66,.4);}
.go svg{width:19px;height:19px;}
.go .x{display:none;}
.search.has-text .go .arr{display:none;}
.search.has-text .go .x{display:block;}
.search.has-text .go{background:transparent;border:1.5px solid var(--ink-3);color:var(--ink-2);box-shadow:none;}
.landing-below{display:none;padding:2px 16px 150px;}
#pageMenu[data-view="landing"] .landing-below{display:block;}
.cats-hero{display:flex;flex-wrap:wrap;justify-content:center;gap:8px;margin-top:8px;}
.cat-chip{min-height:40px;font-family:var(--font);font-size:13.5px;font-weight:600;border-radius:999px;
  padding:8px 15px;background:var(--card);border:1px solid var(--line);color:var(--ink);
  cursor:pointer;max-width:100%;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.cat-chip:active{transform:scale(.97);}
.cats-hero .cat-chip.all{background:var(--accent);border-color:var(--accent);color:#fff;
  box-shadow:0 4px 12px rgba(201,100,66,.35);}
.cat-chip.sel{background:var(--accsoft);border-color:var(--accent);color:var(--accent);}
.cat-row{display:none;gap:8px;overflow-x:auto;padding:0 16px 8px;scrollbar-width:none;
  -webkit-overflow-scrolling:touch;}
.cat-row::-webkit-scrollbar{display:none;}
.cat-row .cat-chip{flex:0 0 auto;}
#pageMenu[data-catrow="1"] .cat-row{display:flex;}
.extras-slot-b{display:none;padding:2px 16px 0;}
#pageMenu[data-extras="1"] .extras-slot-b{display:block;}
#app.closed .extras{display:none;}
.sect{font-size:11.5px;letter-spacing:.1em;text-transform:uppercase;color:var(--ink-3);
  font-weight:700;margin:16px 0 8px;text-align:left;}
.again{background:var(--card);border:1px solid var(--line);border-radius:18px;padding:12px 14px;
  display:flex;align-items:center;gap:12px;text-align:left;box-shadow:0 2px 10px rgba(0,0,0,.05);}
.again-t{flex:1;min-width:0;}
.again .t{font-weight:700;font-size:14px;}
.again .s{font-size:12px;color:var(--ink-2);margin-top:2px;line-height:1.35;overflow-wrap:anywhere;}
.btn{flex-shrink:0;min-height:40px;border:none;border-radius:999px;padding:0 16px;background:var(--accent);
  color:#fff;font-family:var(--font);font-weight:700;font-size:13px;white-space:nowrap;cursor:pointer;}
.btn.o{background:transparent;color:var(--accent);border:1.5px solid var(--accent);}
.link-row{text-align:right;}
.link{border:none;background:none;min-height:40px;padding:0 2px;font-family:var(--font);font-size:12.5px;
  color:var(--accent);font-weight:700;cursor:pointer;}
.nohist{border:1.5px dashed var(--line);border-radius:16px;padding:11px 14px;text-align:left;}
.nohist b{display:block;font-size:13.5px;}
.nohist span{font-size:12px;color:var(--ink-2);}
.paste{margin-top:10px;display:flex;gap:8px;align-items:center;}
.paste .inp{flex:1;min-width:0;height:40px;border-radius:12px;border:1.5px dashed var(--line);
  background:transparent;color:var(--ink);font-family:var(--font);font-size:13px;padding:0 12px;outline:none;}
.paste .inp:focus{border-color:var(--accent);border-style:solid;}
.paste .inp::placeholder{color:var(--ink-3);}
.paste .btn2{flex:0 0 72px;height:40px;border:none;border-radius:12px;background:var(--field);
  color:var(--ink-2);font-family:var(--font);font-weight:700;font-size:13px;cursor:pointer;}
.paste-msg{min-height:0;margin-top:6px;font-size:12.5px;color:var(--danger);text-align:left;}
.paste-msg:empty{display:none;}
.list-info{text-align:center;font-size:12.5px;line-height:1.45;color:var(--ink-3);margin:2px 20px 8px;}
#listWrap{display:none;}
#pageMenu[data-view="list"] #listWrap{display:block;}
.list{padding:0 16px 100px;transition:opacity .12s ease;}
.ghost{position:absolute;pointer-events:none;z-index:2;margin:0;overflow:hidden;}
.prow-cat{display:inline-block;max-width:100%;margin-top:5px;font-size:10.5px;font-weight:600;
  border-radius:999px;padding:2px 8px;background:var(--field);color:var(--ink-2);
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis;vertical-align:top;}
/* Pengumuman: popup kecil di bawah tombol megafon. Ada DI DALAM #pageMenu
   (konteks susun sendiri) sehingga otomatis di BAWAH scrim/modal/toast. */
.ann-pop{position:absolute;right:12px;top:64px;width:min(300px,calc(100% - 24px));z-index:6;
  background:var(--card);border:1px solid var(--line);border-radius:20px;padding:14px 16px 22px;
  box-shadow:0 14px 40px rgba(60,40,20,.28);text-align:left;
  opacity:0;visibility:hidden;transform:scale(.5);transform-origin:var(--ax,90%) 0;
  transition:opacity .22s ease,transform .26s var(--ease),visibility 0s linear .26s;}
.ann-pop.show{opacity:1;visibility:visible;transform:scale(1);
  transition:opacity .22s ease,transform .26s var(--ease),visibility 0s;}
.ann-pop::before{content:'';position:absolute;top:-7px;left:calc(var(--ax,90%) - 7px);width:14px;height:14px;
  background:var(--card);border-left:1px solid var(--line);border-top:1px solid var(--line);
  transform:rotate(45deg);}
.ann-pop h4{margin:0 0 6px;font-size:12px;letter-spacing:.1em;text-transform:uppercase;color:var(--accent);
  display:flex;align-items:center;gap:6px;}
.ann-pop h4 svg{width:15px;height:15px;}
.ann-pop p{margin:0;font-size:14px;line-height:1.45;white-space:pre-wrap;overflow-wrap:anywhere;
  max-height:40vh;overflow-y:auto;}
.ann-prog{position:absolute;left:16px;right:16px;bottom:8px;height:3px;border-radius:3px;
  background:var(--field);overflow:hidden;}
.ann-prog i{display:block;height:100%;background:var(--accent);transform-origin:left center;
  transform:scaleX(1);}
.ann-pop.manual{padding-bottom:16px;}
.ann-pop.manual .ann-prog{display:none;}
/* Riwayat pesanan (bottom sheet) — pola sama dgn modal produk. */
.hist-body{padding:0 16px 18px;}
.hist-it{border:1px solid var(--line);border-radius:14px;padding:10px 12px;margin-bottom:8px;
  display:flex;align-items:center;gap:10px;}
.hist-it .hi-t{flex:1;min-width:0;}
.hist-it .t{font-weight:700;font-size:13.5px;}
.hist-it .s{font-size:12px;color:var(--ink-2);margin-top:2px;line-height:1.35;overflow-wrap:anywhere;}
.hist-msg{margin:0 16px 16px;padding:9px 12px;border-radius:12px;background:var(--accsoft);color:var(--accent);
  font-size:12.5px;font-weight:600;text-align:left;}
.hist-msg:empty{display:none;}
@media (prefers-reduced-motion: reduce){
  .tb-logo,.menu-top .tb-store,.blobs,.sticky-head::before,.ph span,.ann-pop,.ann-pop.show{transition:none;}
}
/* Tombol tampilan daftar/kotak hanya berfungsi di mode daftar — di halaman
   awal (landing) tidak ada daftar yang bisa diubah, jadi disembunyikan. */
#pageMenu[data-view="landing"] #layoutBtn{display:none;}
@media (max-width:380px){
  .tb-id{gap:8px;}
}
@media (max-width:340px){
  .menu-top{padding-left:12px;padding-right:12px;}
  .search-wrap{padding-left:12px;padding-right:12px;}
  .menu-top .topbar-btns{gap:4px;}
  .hero-block h2{font-size:24px;}
}
.prow{background:var(--card);border:1px solid var(--line);border-radius:var(--r-card);
  margin-bottom:9px;overflow:hidden;contain:layout style;}
.prow-main{display:flex;align-items:center;gap:12px;padding:13px;cursor:pointer;}
.prow-icon{width:40px;height:40px;flex-shrink:0;border-radius:999px;background:var(--field);
  display:flex;align-items:center;justify-content:center;font-size:19px;line-height:1;}
.prow-info{flex:1;min-width:0;}
.prow-name{font-size:17px;font-weight:600;}
.prow-meta{font-size:14px;color:var(--ink-2);margin-top:3px;font-family:var(--serif);}
.oos-badge{background:var(--warn);color:#fff;border-radius:999px;
  padding:8px 13px;font-size:13px;font-weight:700;flex-shrink:0;}
.empty{text-align:center;color:var(--ink-3);padding:50px 20px;font-size:15px;}
.more-bar{padding:6px 0 4px;text-align:center;}
.more-info:empty{display:none;}
.more-info{font-size:13.5px;line-height:1.45;color:var(--ink-2);margin:4px 4px 10px;}
.more-btn{display:block;width:100%;min-height:48px;padding:10px 16px;box-sizing:border-box;
  border:1px solid var(--line);background:var(--card);color:var(--accent);border-radius:999px;
  font-family:var(--font);font-size:15px;font-weight:700;cursor:pointer;}
.more-btn:active{background:var(--field);}
/* Blueprint §4 — "expanded pill" yang MEMECAH. Satu pill lebar bertuliskan
   "Tambah" (84px) menyusut jadi lingkaran angka (40px) begitu qty >= 1,
   sementara tombol minus merah tumbuh keluar dari width 0 + scale(.7).
   Supaya transisi `width` ini benar-benar jalan, node kontrol WAJIB
   dipertahankan & di-mutate di tempat (lihat syncProwControls) — kalau
   node-nya diganti baru tiap qty berubah, browser tidak punya nilai awal
   untuk ditransisikan dan efek "memecah"-nya hilang total. */
.prow-controls{display:flex;align-items:center;flex-shrink:0;}
.pc-minus{width:0;height:40px;padding:0;border:none;border-radius:999px;
  background:#D64545;color:#fff;font-size:19px;font-weight:700;cursor:pointer;
  flex-shrink:0;overflow:hidden;opacity:0;transform:scale(.7);
  display:flex;align-items:center;justify-content:center;
  box-shadow:0 2px 6px rgba(0,0,0,.15);
  transition:width .26s cubic-bezier(.3,1.25,.45,1),opacity .18s ease,
             transform .26s cubic-bezier(.3,1.25,.45,1),margin-right .26s ease;}
.prow-controls.selected .pc-minus{width:40px;opacity:1;transform:scale(1);margin-right:7px;}
.pc-add{position:relative;width:84px;height:40px;border:none;border-radius:999px;
  background:var(--accent);color:#fff;font-size:14.5px;font-weight:700;cursor:pointer;
  flex-shrink:0;overflow:hidden;font-family:var(--font);
  box-shadow:0 2px 6px rgba(0,0,0,.15);
  transition:width .26s cubic-bezier(.3,1.25,.45,1),background-color .22s ease;}
.prow-controls.selected .pc-add{width:40px;background:var(--ok);}
.pc-label,.pc-qty{position:absolute;inset:0;display:flex;align-items:center;
  justify-content:center;white-space:nowrap;transition:opacity .16s ease;}
.pc-qty{opacity:0;font-family:var(--serif);font-size:16px;}
.prow-controls.selected .pc-label{opacity:0;}
.prow-controls.selected .pc-qty{opacity:1;}
/* Blueprint §4 — badge di-retrigger tiap qty berubah dgn trik nama animasi
   BERGANTIAN: node-nya persisten (tidak diganti), jadi menambahkan kembali
   nama animasi yang SAMA tidak akan memutar ulang apa pun. Dua nama identik
   yang dipakai selang-seling memaksa browser mendeteksi perubahan. */
@keyframes badge-incr{0%{transform:scale(1);}40%{transform:scale(1.34);}100%{transform:scale(1);}}
@keyframes badge-incr2{0%{transform:scale(1);}40%{transform:scale(1.34);}100%{transform:scale(1);}}
.pc-qty.badge-incr,.mb-badge.badge-incr{animation:badge-incr .3s cubic-bezier(.3,1.4,.5,1);}
.pc-qty.badge-incr2,.mb-badge.badge-incr2{animation:badge-incr2 .3s cubic-bezier(.3,1.4,.5,1);}
/* Blueprint §3/§6 — micro-interaction ikon: memantul sekali saat qty
   produknya berubah. Murni delight, tidak fungsional (Lottie di blueprint
   diganti animasi CSS sederhana, sesuai saran blueprint sendiri untuk
   project tanpa infrastruktur Lottie — di sini juga wajib, karena katalog
   ini self-contained tanpa CDN). */
@keyframes icon-pop{0%{transform:scale(1);}35%{transform:scale(1.18) rotate(-6deg);}100%{transform:scale(1);}}
.prow-icon.icon-pop{animation:icon-pop .34s cubic-bezier(.3,1.4,.5,1);}
@media (prefers-reduced-motion: reduce){
  .pc-qty.badge-incr,.pc-qty.badge-incr2,.mb-badge.badge-incr,.mb-badge.badge-incr2,
  .prow-icon.icon-pop{animation:none;}
  .pc-minus,.pc-add,.page,.mb-clear,.mb-clear span,.mb-clear svg,.mainbtn,.mainbtn>*{transition:none;}
}

/* Item 79 M2 — mode Tile: grid 2 kolom, kartu vertikal. Murni CSS di
   atas markup .prow yang SAMA PERSIS (icon/info/controls) — renderList()
   JS TIDAK berubah sama sekali, jadi tidak ada logic baru yang bisa
   regresi, cuma re-flow tampilan lewat class `tile-mode` di #list. */
.list.tile-mode{display:grid;grid-template-columns:1fr 1fr;gap:9px;
  padding:0 16px 130px;align-content:start;
  /* WAJIB min-content, JANGAN dikembalikan ke `auto` (default). `.prow`
     punya overflow:hidden sehingga jadi scroll container, dan scroll
     container automatic-minimum-size-nya NOL. Dengan grid-auto-rows:auto,
     track lalu tidak punya tinggi minimum dari isi, sementara container
     (#list) tingginya DEFINITE karena `flex:1` — sisa ruang dibagi rata ke
     semua track, tiap kartu kolaps jadi ~6px dan isinya dipotong
     overflow:hidden. Gejalanya: kartu tampil sebagai GARIS TIPIS saja
     (bug nyata, dilaporkan user dari HP). */
  grid-auto-rows:min-content;}
.list.tile-mode .prow{margin-bottom:0;}
.list.tile-mode .prow-main{flex-direction:column;align-items:stretch;gap:8px;}
.list.tile-mode .prow-icon{width:44px;height:44px;font-size:21px;align-self:flex-start;}
.list.tile-mode .prow-name{font-size:14.5px;}
.list.tile-mode .prow-meta{font-size:12.5px;}
.list.tile-mode .prow-controls{width:100%;justify-content:flex-end;}
.list.tile-mode .oos-badge{align-self:flex-start;}
.list.tile-mode .empty,.list.tile-mode .more-bar{grid-column:1/-1;}
/* Blueprint §5 — pengganti Telegram MainButton. Katalog ini dibuka di
   browser biasa (bukan Mini App), jadi tombol native Telegram TIDAK ada
   dan harus disediakan sendiri: satu tombol mengambang, sembunyi total
   saat keranjang kosong, dan — sesuai permintaan user — nominal totalnya
   menyatu DI DALAM tombol yang sama (bukan bar terpisah seperti dulu). */
.mainbtn-wrap{position:fixed;left:0;right:0;bottom:0;max-width:480px;margin:0 auto;
  padding:14px 16px calc(14px + env(safe-area-inset-bottom));z-index:15;
  pointer-events:none;
  background:linear-gradient(to top,var(--panel) 58%,rgba(0,0,0,0));
  transition:opacity .26s ease,transform .3s cubic-bezier(.22,.61,.36,1);}
.mainbtn-wrap>*{pointer-events:auto;}
.mainbtn-wrap.hidden{opacity:0;transform:translateY(130%);pointer-events:none;}
.mb-row{display:flex;align-items:stretch;}
.mainbtn{flex:1 1 0;min-width:0;border:none;border-radius:999px;background:var(--accent);
  color:#fff;padding:15px 16px;font-size:16px;font-weight:700;cursor:pointer;
  font-family:var(--font);display:grid;grid-template-columns:auto 1fr auto;
  align-items:center;column-gap:10px;min-height:56px;text-align:left;
  box-shadow:0 8px 22px rgba(0,0,0,.22);
  transition:background-color .24s ease,transform .14s ease,padding .32s ease,
             margin-left .32s cubic-bezier(.3,1.25,.45,1);}
.mainbtn:active{transform:scale(.985);}
/* Halaman awal: tombol dipecah (Lihat Pesanan ~3/4 + Kosongkan ~1/4 merah).
   Pindah ke halaman Pesanan: tombol Kosongkan MENYUSUT ke lebar 0 sambil
   tombol utama melebar & berganti warna hijau — satu gerak yang sama dgn
   pil +/- produk (cubic-bezier memantul yg sama), dan sebaliknya. */
.mb-clear{flex:0 0 auto;width:27%;margin-right:8px;padding:0 7px;border:none;
  border-radius:999px;background:#D64545;color:#fff;cursor:pointer;
  font-family:var(--font);font-size:9.5px;font-weight:700;line-height:1.15;
  display:flex;align-items:center;justify-content:center;gap:4px;overflow:hidden;
  text-align:left;box-shadow:0 8px 22px rgba(0,0,0,.22);
  transition:width .32s cubic-bezier(.3,1.25,.45,1),margin-right .32s cubic-bezier(.3,1.25,.45,1),
             padding .32s ease,gap .32s ease,opacity .2s ease,transform .14s ease,font-size .32s ease;}
.mb-clear:active{transform:scale(.96);}
.mb-clear svg{width:20px;height:20px;flex-shrink:0;transition:width .32s ease,height .32s ease;}
.mb-clear span{min-width:0;max-width:90px;overflow:hidden;white-space:normal;
  transition:max-width .32s cubic-bezier(.3,1.25,.45,1),opacity .22s ease;}
/* Scroll ke bawah: keterangan menyusut (sisa ikon, tombol jadi bulatan dan
   tombol utama melebar); scroll ke atas: keterangan muncul lagi. */
#mainBtnWrap.mb-collapsed .mb-clear{width:56px;padding:0;gap:0;}
#mainBtnWrap.mb-collapsed .mb-clear span{max-width:0;opacity:0;}
/* Konfirmasi hapus INLINE (halaman awal): Ya merah 1/4 di kiri, Tidak
   netral 3/4 di kanan, di baris tombol yang sama. Bertahan walau scroll /
   mengetik; hanya berakhir saat Ya/Tidak ditekan atau pesanan kosong. */
#mainBtnWrap.mb-confirm .mb-clear{width:25%;padding:0 8px;gap:6px;font-size:15px;}
#mainBtnWrap.mb-confirm .mb-clear svg{width:20px;height:20px;}
#mainBtnWrap.mb-confirm .mb-clear span{max-width:90px;opacity:1;}
.mb-q,.mb-no{display:none;}
#mainBtnWrap.mb-confirm .mainbtn{background:var(--field);color:var(--ink);
  box-shadow:0 8px 22px rgba(0,0,0,.14);outline:1px solid var(--line);outline-offset:-1px;}
#mainBtnWrap.mb-confirm .mb-badge,#mainBtnWrap.mb-confirm .mb-label,
#mainBtnWrap.mb-confirm .mb-total{display:none;}
#mainBtnWrap.mb-confirm .mb-q,#mainBtnWrap.mb-confirm .mb-no{display:block;
  grid-column:1 / -1;grid-row:auto;text-align:center;}
.mb-q{font-size:11px;font-weight:600;opacity:.75;line-height:1.2;}
.mb-no{font-size:17px;font-weight:700;line-height:1.2;}
#app.order-mode .mb-clear{width:0;margin-right:0;padding:0;opacity:0;pointer-events:none;}
/* Halaman awal (terpecah): isi tombol utama ditumpuk — label kecil di atas,
   total besar di bawahnya — supaya total jutaan tetap utuh di lebar 1/4
   yang tersisa. Halaman Pesanan: satu baris (badge | label | total). Saat
   mode berganti isi tombol disamarkan sesaat (.swapping, tanpa transisi
   saat sembunyi, fade-in saat tampil) supaya perubahan susunan tidak
   terlihat melompat. */
#app:not(.order-mode) .mainbtn{grid-template-columns:auto 1fr;column-gap:9px;padding:8px 12px;}
#app:not(.order-mode) .mb-badge{grid-row:1 / span 2;min-width:24px;height:24px;padding:0 6px;font-size:13px;}
#app:not(.order-mode) .mb-label{grid-column:2;grid-row:1;font-size:12.5px;font-weight:600;opacity:.92;}
#app:not(.order-mode) .mb-total{grid-column:2;grid-row:2;font-size:17px;text-align:left;line-height:1.15;}
#app.order-mode .mainbtn{padding:8px 14px;column-gap:8px;font-size:15px;}
#app.order-mode .mb-total{font-size:17px;}
.mainbtn>*{transition:opacity .2s ease;}
.mainbtn.swapping>*{opacity:0;transition:none;}
.mb-clear.swapping>*{opacity:0;transition:none;}
@media (max-width:340px){ .mb-clear{width:30%;font-size:9px;padding:0 5px;}
  /* "Kirim via WhatsApp" dulu terpotong "..." di 320px */
  #app.order-mode .mb-label{font-size:13px;} }
.mainbtn.wa{background:#25D366;}
.mb-ic{display:none;width:20px;height:20px;flex-shrink:0;}
/* Tombol Telegram (khas biru Telegram). Tersembunyi/mengecil di luar halaman
   Pesanan; di halaman Pesanan melebar jadi 50% dan tombol WhatsApp menyusut
   ke 50% (gerak sama dgn tombol Kosongkan). Teks tetap putih di mode gelap. */
.mainbtn-tg{flex:0 1 0px;margin-left:0;opacity:0;visibility:hidden;pointer-events:none;
  background:#26A5E4;color:#fff;overflow:hidden;
  transition:flex-grow .32s cubic-bezier(.3,1.25,.45,1),margin-left .32s cubic-bezier(.3,1.25,.45,1),
             padding .32s ease,opacity .2s ease,visibility 0s linear .32s,
             background-color .24s ease,transform .14s ease;}
#app .mainbtn.mainbtn-tg{padding-left:0;padding-right:0;}
#app.order-mode .mainbtn.mainbtn-tg{flex:1 1 0px;margin-left:0;opacity:1;visibility:visible;
  pointer-events:auto;padding-left:8px;padding-right:8px;
  transition-delay:0s,0s,0s,0s,0s,0s,0s;}
@media (hover:hover){ .mainbtn-tg:hover{background:#1d90c8;} }
/* Urutan baris: Kosongkan | Telegram | WhatsApp — WhatsApp (hijau) SELALU di
   kanan. Urutan visual lewat `order` (DOM tetap WA lalu TG); jarak antar dua
   tombol di halaman Pesanan dipasang di tombol WhatsApp (margin-kiri). */
#mbClear{order:0;}
#mainBtnTg{order:1;}
#mainBtn{order:2;}
#app.order-mode.has-tg #mainBtn{margin-left:8px;}
#mainBtnWrap.mb-confirm .mainbtn-tg{display:none;}
/* Dua tombol (WhatsApp + Telegram) di halaman Pesanan: tiap tombol 2 baris —
   baris 1 logo + teks, baris 2 total (roll, rata tengah). */
#app.order-mode.has-tg .mainbtn{grid-template-columns:auto auto;justify-content:center;
  align-content:center;column-gap:6px;row-gap:1px;padding:7px 8px;font-size:13px;text-align:center;}
#app.order-mode.has-tg .mb-badge{display:none;}
#app.order-mode.has-tg .mb-ic{display:block;grid-row:1;grid-column:1;}
#app.order-mode.has-tg .mb-label{grid-row:1;grid-column:2;font-size:13px;font-weight:700;
  overflow:visible;text-overflow:clip;opacity:1;}
#app.order-mode.has-tg .mb-total{grid-column:1 / -1;grid-row:2;font-size:16px;text-align:center;line-height:1.15;}
#app.order-mode.has-tg .mb-total.roll{justify-content:center;}
#app.order-mode.has-tg .mb-total.tt{font-size:14px;}
.mainbtn:disabled{opacity:.6;cursor:default;}
.mb-badge{min-width:26px;height:26px;padding:0 8px;border-radius:999px;
  background:rgba(255,255,255,.24);display:flex;align-items:center;
  justify-content:center;font-size:14px;flex-shrink:0;line-height:1;}
.mb-label{text-align:left;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0;}
.mb-total{font-family:var(--serif);font-size:18px;white-space:nowrap;text-align:right;}
/* Halaman 2 (Pesanan) — header sendiri dgn tombol kembali ("Edit" di
   blueprint §6), body scroll sendiri. */
.order-top{align-items:center;gap:12px;}
.back-btn{width:38px;height:38px;flex-shrink:0;border:1px solid var(--line);
  background:var(--field);color:var(--ink);border-radius:999px;cursor:pointer;
  display:flex;align-items:center;justify-content:center;}
.back-btn svg{width:19px;height:19px;}
.order-title{flex:1;min-width:0;}
.order-body{flex:1;overflow-y:auto;padding:4px 18px 150px;}
/* Item 79 M4 — scrim & overlay dulu instan display:none/block (pop
   tiba-tiba), sekarang fade konsisten dgn timing .sheet (.22s) yang sudah
   ada. `visibility` dipakai supaya tetap tidak menangkap klik/tab-focus
   saat tersembunyi, TANPA display:none yang mencegah transisi opacity. */
.scrim{position:fixed;inset:0;background:rgba(20,16,10,.42);z-index:20;
  opacity:0;visibility:hidden;transition:opacity .2s ease,visibility 0s linear .2s;}
.scrim.show{opacity:1;visibility:visible;transition:opacity .2s ease;}
.sheet{position:fixed;left:0;right:0;bottom:0;max-width:480px;margin:0 auto;
  background:var(--card);border-radius:30px 30px 0 0;z-index:21;
  max-height:86vh;display:flex;flex-direction:column;
  transform:translateY(100%);transition:transform .22s ease-out;}
.sheet.show{transform:translateY(0);}
.sheet-grip{width:38px;height:4px;background:var(--line);border-radius:2px;
  margin:10px auto 4px;flex-shrink:0;}
.sheet-head{display:flex;align-items:center;padding:6px 56px 10px 16px;flex-shrink:0;}
.sheet-head b{font-size:18px;}
/* Halaman Pesanan (Mockup B): latar sedikit lebih gelap dari panel, header
   transparan, daftar barang di atas KERTAS STRUK bergerigi. */
.page-order{background:var(--canvas);}
.order-top{background:transparent;border-bottom:none;padding:16px 16px 6px;}
.order-title{text-align:center;}
.order-title .tb-store{font-family:var(--font);font-size:13px;font-weight:700;letter-spacing:.08em;
  text-transform:uppercase;color:var(--ink-2);}
.clear-cart-btn{width:40px;height:40px;flex-shrink:0;border:none;background:var(--card);color:var(--danger);
  border-radius:50%;cursor:pointer;display:flex;align-items:center;justify-content:center;
  box-shadow:0 1px 4px rgba(60,40,20,.12);}
.clear-cart-btn svg{width:19px;height:19px;}
.paper-wrap{margin-top:12px;filter:drop-shadow(0 6px 14px rgba(80,60,30,.12));}
.paper{background:var(--card);padding:22px 20px 34px;border-radius:6px 6px 0 0;
  -webkit-mask:linear-gradient(#000 0 0) top/100% calc(100% - 9px) no-repeat,conic-gradient(from -45deg at bottom,#0000,#000 1deg 89deg,#0000 90deg) bottom/18px 9px repeat-x;
  mask:linear-gradient(#000 0 0) top/100% calc(100% - 9px) no-repeat,conic-gradient(from -45deg at bottom,#0000,#000 1deg 89deg,#0000 90deg) bottom/18px 9px repeat-x;}
.paper-store{text-align:center;font-family:var(--serif);font-size:22px;font-weight:600;}
.paper-sub{text-align:center;font-size:12px;color:var(--ink-3);margin-top:2px;}
.dash{border-top:1.5px dashed rgba(130,115,90,.35);margin:14px 0;}
.ln{margin-bottom:12px;overflow:hidden;}
.ln.gone{transition:height .25s ease,margin .25s ease,opacity .2s ease;opacity:0;margin-bottom:0;}
.l1{display:flex;align-items:baseline;gap:6px;font-size:15px;cursor:pointer;}
.l1 .q{font-family:var(--serif);font-weight:700;color:var(--accent);min-width:26px;flex-shrink:0;margin-right:2px;}
.l1 .nm{font-weight:600;}
.l1 .dots{flex:1;border-bottom:1.5px dotted rgba(130,115,90,.4);transform:translateY(-4px);min-width:10px;}
.l1 .s{font-family:var(--serif);font-weight:600;}
.l2{margin-left:32px;display:flex;align-items:center;justify-content:space-between;
  font-size:12px;color:var(--ink-3);margin-top:1px;min-height:36px;}
.ln .nn{margin-left:32px;font-size:12px;color:var(--ink-2);font-style:italic;cursor:pointer;}
/* "Tambah?" -> stepper: kata kecil berubah mulus jadi pil (-, angka, +) yang
   membuka ke kiri, gerak memecah yang sama dgn tombol Tambah di daftar produk. */
.tbx{display:flex;align-items:center;justify-content:flex-end;height:36px;}
.tb{border:none;background:transparent;font-family:var(--font);font-size:12.5px;font-weight:700;
  color:var(--accent);padding:8px 2px 4px;margin:0;border-bottom:1.5px dotted var(--accent);
  cursor:pointer;max-width:90px;overflow:hidden;white-space:nowrap;
  transition:max-width .3s cubic-bezier(.3,1.25,.45,1),opacity .16s ease,padding .3s ease,border-width .2s ease;}
.tbx.open .tb{max-width:0;opacity:0;padding:8px 0 4px;border-bottom-width:0;pointer-events:none;}
.stp{display:flex;align-items:center;background:var(--field);border-radius:999px;overflow:hidden;
  max-width:0;opacity:0;padding:0;transform:scale(.7);transform-origin:right center;
  transition:max-width .3s cubic-bezier(.3,1.25,.45,1),opacity .2s ease,padding .3s ease,transform .3s cubic-bezier(.3,1.25,.45,1);}
.tbx.open .stp{max-width:140px;opacity:1;padding:3px;transform:scale(1);}
.stp button{width:28px;height:28px;flex-shrink:0;border:none;border-radius:50%;background:var(--card);
  color:var(--accent);font-size:17px;font-weight:600;cursor:pointer;display:flex;align-items:center;
  justify-content:center;padding:0;box-shadow:0 1px 3px rgba(60,40,20,.15);}
.stp button.p{background:var(--accent);color:#fff;}
.stp .qn{min-width:30px;text-align:center;font-family:var(--serif);font-weight:700;font-size:15px;color:var(--ink);flex-shrink:0;}
.paper-total{display:flex;justify-content:space-between;align-items:baseline;gap:10px;}
.paper-total > span{font-size:12px;letter-spacing:.1em;text-transform:uppercase;font-weight:700;color:var(--ink-2);}
.paper-total b{font-family:var(--serif);font-size:clamp(24px,8.2vw,32px);font-weight:600;white-space:nowrap;}
.paper-total .roll{justify-content:flex-end;}
.paper-hint{text-align:center;font-size:11.5px;color:var(--ink-3);margin-top:6px;}
.ofield{margin:18px 4px 0;border-bottom:1.5px solid var(--line);padding:6px 2px 9px;}
.ofield label{display:block;font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--ink-3);}
.ofield input,.ofield textarea{width:100%;border:none;background:transparent;outline:none;resize:none;
  font-family:var(--font);font-size:16px;color:var(--ink);padding:5px 0 0;}
.ofield textarea{min-height:28px;}
.ofield input::placeholder,.ofield textarea::placeholder{color:var(--ink-3);opacity:.7;}
.copy-link{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;border:none;
  background:transparent;color:var(--accent);font-family:var(--font);font-weight:700;font-size:14px;
  padding:16px 0 4px;cursor:pointer;}
.copy-link svg{width:16px;height:16px;}
#app.order-mode .mainbtn-wrap{background:linear-gradient(to top,var(--canvas) 58%,rgba(0,0,0,0));}
/* Tombol tutup: lingkaran merah di POJOK KANAN ATAS modal (bukan lagi di
   samping nama produk). */
.sheet-x{position:absolute;top:10px;right:14px;width:34px;height:34px;border:none;
  border-radius:50%;background:#D64545;color:#fff;font-size:22px;line-height:1;
  cursor:pointer;padding:0;display:flex;align-items:center;justify-content:center;
  box-shadow:0 2px 6px rgba(0,0,0,.18);z-index:2;}
.sheet-x:active{transform:scale(.92);}
/* Geser-ke-bawah menutup modal: cegah gulir/refresh bawaan browser (pull-to-
   refresh) selagi modal terbuka — gestur ditangani JS (lihat blok swipe). */
.sheet-body{overscroll-behavior-y:contain;}
.sheet{touch-action:pan-y;}
html.modal-open,html.modal-open body{overscroll-behavior-y:none;}
.sheet-body{overflow-y:auto;padding:0 20px 12px;flex:1;}
.confirm-overlay{position:fixed;inset:0;background:rgba(20,16,10,.42);z-index:40;
  display:flex;align-items:center;justify-content:center;
  opacity:0;visibility:hidden;pointer-events:none;
  transition:opacity .2s ease,visibility 0s linear .2s;}
.confirm-overlay.show{opacity:1;visibility:visible;pointer-events:auto;
  transition:opacity .2s ease;}
.confirm-box{background:var(--card);border-radius:16px;padding:20px;width:280px;
  max-width:calc(100vw - 40px);box-shadow:0 12px 30px rgba(0,0,0,.25);
  transform:scale(.94);transition:transform .18s cubic-bezier(.3,1.4,.5,1);}
.confirm-overlay.show .confirm-box{transform:scale(1);}
.confirm-title{font-size:16px;font-weight:700;color:var(--ink);margin-bottom:8px;}
.confirm-body{font-size:14px;color:var(--ink-2);line-height:1.5;margin-bottom:18px;}
.confirm-actions{display:flex;gap:10px;}
.confirm-actions button{flex:1;border-radius:999px;padding:11px;font-size:14.5px;
  font-weight:700;cursor:pointer;border:none;}
.btn-cancel{background:var(--field);color:var(--ink);}
.btn-danger{background:var(--danger);color:#fff;}
.field-label{font-size:13px;color:var(--ink-3);font-weight:600;margin:16px 0 6px;}
.tfield{width:100%;border:1px solid var(--line);background:var(--field);
  border-radius:var(--r-btn);padding:11px 13px;font-size:16px;color:var(--ink);
  font-family:var(--font);outline:none;}
textarea.tfield{resize:none;min-height:64px;}
.im-hero{text-align:center;padding:14px 8px 0;}
.im-emoji{font-size:54px;line-height:1;}
.im-name{margin:8px 0 0;font-family:var(--serif);font-size:26px;font-weight:600;line-height:1.15;}
.im-cat{display:inline-block;margin-top:7px;font-size:11.5px;font-weight:700;letter-spacing:.06em;
  text-transform:uppercase;color:var(--accent);background:rgba(201,100,66,.13);border-radius:999px;padding:4px 11px;}
.im-cat:empty{display:none;}
.im-price{text-align:center;margin-top:12px;font-family:var(--serif);font-size:38px;font-weight:600;
  letter-spacing:-.5px;display:flex;align-items:baseline;justify-content:center;gap:6px;}
.im-price .roll{justify-content:center;}
.im-price small{font-family:var(--font);font-size:14px;color:var(--ink-3);font-weight:500;letter-spacing:0;}
/* Satuan/varian: segmented control yang bisa DIGESER bila banyak. */
.im-seg-wrap{margin-top:14px;position:relative;}
.im-seg-lbl{font-size:11px;font-weight:700;letter-spacing:.8px;text-transform:uppercase;
  color:var(--ink-3);margin:0 0 6px 6px;}
.im-seg{display:flex;gap:4px;background:var(--field);border-radius:24px;padding:4px;
  overflow-x:auto;scroll-snap-type:x proximity;-webkit-overflow-scrolling:touch;scrollbar-width:none;}
.im-seg::-webkit-scrollbar{display:none;}
.unit-chip{flex:1 0 auto;min-width:88px;border:none;background:transparent;color:var(--ink-2);
  border-radius:20px;padding:8px 14px;font-family:var(--font);font-size:14px;font-weight:700;
  cursor:pointer;text-align:center;scroll-snap-align:center;line-height:1.2;
  transition:background-color .2s ease,color .2s ease,box-shadow .2s ease;}
.unit-chip small{display:block;font-size:11.5px;font-weight:600;color:var(--ink-3);margin-top:1px;}
.unit-chip.sel{background:var(--card);color:var(--ink);box-shadow:0 2px 8px rgba(60,40,20,.16);}
.unit-chip.sel small{color:var(--accent);}
/* Walk-through kecil (permanen tiap modal dibuka) bila pilihan melebihi lebar. */
.im-seg-hint{display:none;align-items:center;justify-content:center;gap:6px;margin-top:8px;
  font-size:12px;font-weight:600;color:var(--ink-3);}
.im-seg-hint.show{display:flex;}
.im-seg-hint .arr{display:inline-block;font-size:20px;line-height:1;color:var(--accent);
  animation:arr-pulse 1.1s ease-in-out infinite;}
@keyframes arr-pulse{0%,100%{transform:translateX(0);opacity:.55;}50%{transform:translateX(6px);opacity:1;}}
.im-qty{display:flex;align-items:center;justify-content:center;gap:22px;margin-top:20px;}
.im-qty button{width:54px;height:54px;border:1.5px solid var(--line);background:transparent;
  color:var(--accent);font-size:26px;font-weight:500;border-radius:50%;cursor:pointer;flex-shrink:0;
  display:flex;align-items:center;justify-content:center;padding:0;transition:transform .12s ease;}
.im-qty button:active{transform:scale(.92);}
.im-qty button.p{background:var(--accent);border-color:var(--accent);color:#fff;}
.im-qty-input{width:96px;text-align:center;border:none;background:transparent;padding:0;
  font-size:54px;line-height:1;font-weight:600;font-family:var(--serif);color:var(--ink);outline:none;
  -moz-appearance:textfield;appearance:textfield;}
.im-qty-input::-webkit-outer-spin-button,.im-qty-input::-webkit-inner-spin-button{-webkit-appearance:none;margin:0;}
.im-eq{text-align:center;margin-top:8px;font-size:13px;color:var(--ink-3);min-height:18px;}
.im-note{margin-top:18px;border-bottom:1.5px solid var(--line);padding:6px 2px 8px;}
.im-note label{display:block;font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--ink-3);}
.im-note textarea{width:100%;border:none;background:transparent;resize:none;outline:none;
  font-family:var(--font);font-size:15px;color:var(--ink);padding:5px 0 0;min-height:28px;}
.im-note textarea::placeholder{color:var(--ink-3);opacity:.7;}
.im-actions{display:flex;align-items:stretch;}
/* Pola SAMA dgn tombol bawah halaman awal (Lihat Pesanan + Kosongkan): aksi
   utama ~3/4, Hapus merah ~1/4. Belum ada di pesanan -> Hapus menyusut ke
   lebar 0 (Tambah selebar penuh), dgn animasi yang sama. */
.im-actions.nodel .mb-clear{width:0;margin-right:0;padding:0;opacity:0;pointer-events:none;}
.add-cta{flex:1 1 0;min-width:0;border:none;background:var(--accent);color:#fff;border-radius:999px;
  padding:15px;font-size:16.5px;font-weight:700;cursor:pointer;}
.add-cta:disabled{opacity:.4;}
.sheet-foot{background:var(--card);padding:14px 16px calc(16px + env(safe-area-inset-bottom));
  border-top:1px solid var(--line);flex-shrink:0;}
.grand{display:flex;justify-content:space-between;align-items:baseline;
  margin-bottom:12px;}
.grand .gl{font-size:15px;color:var(--ink-2);}
.grand .gv{font-size:30px;font-weight:700;font-family:var(--serif);}
.copy-btn{width:100%;border:1px solid var(--line);background:transparent;
  color:var(--ink);border-radius:var(--r-btn);padding:12px;font-size:15px;
  font-weight:600;cursor:pointer;margin-top:9px;}
/* Blueprint §7 — toast fixed di bawah viewport (di ATAS tombol utama),
   muncul dgn slide-up, auto-hilang 2,5 detik, bisa juga ditutup manual
   dgn tap. Beda dari blueprint: warna merah HANYA untuk pesan error.
   Blueprint memakai merah untuk semua status karena di sana toast memang
   cuma dipakai untuk error; katalog ini juga memakai toast untuk pesan
   informatif ("teks pesanan disalin"), dan mewarnainya merah akan terbaca
   sebagai kegagalan oleh pelanggan. */
.toast{position:fixed;left:50%;bottom:104px;
  transform:translateX(-50%) translateY(14px);
  background:var(--ink);color:var(--panel);padding:11px 18px;border-radius:22px;
  font-size:14.5px;font-weight:600;z-index:30;opacity:0;pointer-events:none;
  max-width:calc(100% - 40px);text-align:center;cursor:pointer;
  box-shadow:0 6px 18px rgba(0,0,0,.22);
  transition:opacity .22s ease,transform .22s cubic-bezier(.22,.61,.36,1);}
.toast.show{opacity:1;transform:translateX(-50%) translateY(0);pointer-events:auto;}
.toast.err{background:#e64d44;color:#fff;}
/* ── Stiker animasi (Lottie). Kotak dipesan ukurannya dulu supaya tata letak
   tidak melompat saat animasi siap; tanpa stiker -> [hidden] (display:none). */
.stk{width:128px;height:128px;margin:0 auto;}
.stk[hidden]{display:none;}
.stk svg{display:block;}
.hero-block .stk{margin-bottom:8px;}
.nf{text-align:center;color:var(--ink-3);padding:30px 20px 50px;font-size:15px;}
.nf .stk{width:120px;height:120px;margin-bottom:6px;}
.nf p{margin:0;overflow-wrap:anywhere;}
.list.tile-mode .nf{grid-column:1/-1;}
/* Halaman TOKO TUTUP: hanya stiker + judul + jam buka + pengumuman + tautan kode.
   Pencarian, kategori, daftar, Pesan lagi & tombol pengumuman header disembunyikan. */
.closed-page{display:none;text-align:center;padding:clamp(24px,9vh,80px) 24px 32px;}
#app.shop-closed .closed-page{display:block;}
#app.shop-closed .sticky-head,#app.shop-closed .hero-block,#app.shop-closed .landing-below,
#app.shop-closed .extras-slot-b,#app.shop-closed #listWrap,#app.shop-closed #annBtn,
#app.shop-closed #annPop,#app.shop-closed .layout-btn{display:none !important;}
.closed-page .stk{width:160px;height:160px;margin-bottom:10px;}
.closed-page h2{margin:0 0 6px;font-family:var(--serif);font-size:26px;font-weight:600;letter-spacing:-.2px;}
.cp-when{margin:0;font-size:15px;color:var(--ink-2);font-weight:600;}
.cp-ann{margin:18px auto 0;max-width:340px;padding:12px 14px;border-radius:14px;background:var(--card);
  border:1px solid var(--line);font-size:13.5px;line-height:1.45;color:var(--ink-2);text-align:left;
  white-space:pre-line;overflow-wrap:anywhere;}
.cp-code{margin-top:22px;border:none;background:transparent;color:var(--ink-3);font-family:var(--font);
  font-size:12.5px;font-weight:600;text-decoration:underline;padding:8px;cursor:pointer;}
.st-dot.warn{background:#E8912D;box-shadow:0 0 0 4px rgba(232,145,45,.24);}
/* Halaman PESANAN TERKIRIM: menutupi semuanya, muncul langsung saat Kirim ditekan. */
.page-sent{display:none;align-items:center;justify-content:center;text-align:center;z-index:25;}
#app.sent-mode .page-sent{display:flex;animation:sentIn .3s cubic-bezier(.22,.61,.36,1);}
@keyframes sentIn{from{opacity:0;transform:translateY(14px);}to{opacity:1;transform:none;}}
#app.sent-mode .mainbtn-wrap{visibility:hidden;pointer-events:none;}
.sent-body{padding:0 28px;display:flex;flex-direction:column;align-items:center;}
.sent-body .stk{width:180px;height:180px;margin-bottom:14px;}
.sent-body h2{margin:0 0 26px;font-family:var(--serif);font-size:28px;font-weight:600;letter-spacing:-.3px;}
.sent-btn{border:none;background:var(--accent);color:#fff;border-radius:var(--r-btn);padding:14px 26px;
  font-family:var(--font);font-size:16px;font-weight:700;cursor:pointer;min-height:48px;
  transition:transform .14s ease,background-color .24s ease;}
.sent-btn:active{transform:scale(.97);}
@media (prefers-reduced-motion:reduce){ #app.sent-mode .page-sent{animation:none;} }
/* ── Game labirin (DATA.game): di bawah halaman awal & halaman toko tutup. */
.game-slot{padding:0 0 8px;}
.closed-page .game-slot{margin-top:18px;}
.maze-card{margin:26px auto 0;max-width:380px;background:var(--card);border:1px solid var(--line);border-radius:22px;padding:14px 14px 12px;box-shadow:0 6px 22px rgba(60,40,20,.08);text-align:left}
:root[data-theme="dark"] .maze-card{box-shadow:0 6px 22px rgba(0,0,0,.35)}
.mz-head{display:flex;align-items:center;gap:10px}
.mz-title{flex:1;min-width:0}
.mz-title b{display:block;font-family:var(--serif);font-size:18px;font-weight:600;letter-spacing:-.2px}
.mz-title small{display:block;font-size:12px;color:var(--ink-2);margin-top:1px}
.mz-ibtn{width:40px;height:40px;border-radius:50%;border:1px solid var(--line);background:var(--field);color:var(--ink-2);display:flex;align-items:center;justify-content:center;cursor:pointer;padding:0;flex-shrink:0;transition:background-color .2s ease,color .2s ease,border-color .2s ease,transform .12s ease}
.mz-ibtn:active{transform:scale(.92)}
.mz-ibtn svg{width:19px;height:19px;stroke:currentColor;fill:none;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.mz-ibtn[aria-pressed="true"]{background:var(--accent);border-color:var(--accent);color:#fff}
.mz-seg{display:flex;gap:4px;background:var(--field);border-radius:999px;padding:4px;margin:12px 0 10px}
.mz-seg button{flex:1;border:none;background:transparent;color:var(--ink-2);font:700 13px var(--font);border-radius:999px;padding:9px 0;min-height:36px;cursor:pointer;transition:background-color .2s ease,color .2s ease,box-shadow .2s ease}
.mz-seg button[aria-selected="true"]{background:var(--card);color:var(--ink);box-shadow:0 2px 8px rgba(60,40,20,.16)}
:root[data-theme="dark"] .mz-seg button[aria-selected="true"]{box-shadow:0 2px 8px rgba(0,0,0,.4)}
.mz-stage{position:relative;width:100%;aspect-ratio:1/1;border-radius:18px;overflow:hidden;touch-action:none;-webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent;background:var(--field);outline:none}
.mz-stage canvas{position:absolute;inset:0;width:100%;height:100%;display:block;touch-action:none}
.mz-win{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;background:rgba(20,15,10,.38);color:#fff;text-align:center;opacity:0;pointer-events:none;transition:opacity .28s ease;backdrop-filter:blur(2px);-webkit-backdrop-filter:blur(2px)}
.mz-win.show{opacity:1;pointer-events:auto}
.mz-win b{font-family:var(--serif);font-size:26px;font-weight:600}
.mz-win span{font-size:14px;font-weight:600}
.mz-win em{font-style:normal;font-size:12px;font-weight:700;background:var(--accent);border-radius:999px;padding:3px 10px;margin-top:4px}
.mz-foot{display:flex;justify-content:space-between;align-items:center;margin-top:10px;font-size:13px;color:var(--ink-2)}
.mz-foot b{font-family:var(--serif);font-size:17px;color:var(--ink);font-weight:600}
.mz-hint{margin:6px 0 0;font-size:11.5px;color:var(--ink-3);text-align:center}
</style>
</head>
<body>
<div id="app">
  <!-- Halaman 1 — menu: landing (hero + kolom cari + kategori) atau daftar
       produk. Semua isi ada di SATU scroller (#menuScroll); atribut
       data-view/data-catrow/data-extras diatur JS (applyState). -->
  <section class="page page-menu" id="pageMenu" data-view="list" data-catrow="0" data-extras="0">
    <div class="blobs" aria-hidden="true"></div>
    <div class="menu-top" id="menuTop">
      <button class="tb-id" id="tbId" type="button">
        <span class="tb-logo" id="storeLogo" aria-hidden="true"><svg viewBox="0 0 512 512" fill="none" stroke="currentColor" stroke-width="22" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M120.0 79.0 C107.2 84.2 93.0 92.5 82.0 100.0 C71.0 107.5 61.8 115.7 54.0 124.0 C46.2 132.3 40.3 140.3 35.0 150.0 C29.7 159.7 25.2 171.3 22.0 182.0 C18.8 192.7 17.0 201.5 16.0 214.0 C15.0 226.5 14.8 243.3 16.0 257.0 C17.2 270.7 19.5 283.3 23.0 296.0 C26.5 308.7 30.3 320.3 37.0 333.0 C43.7 345.7 53.2 359.8 63.0 372.0 C72.8 384.2 84.8 395.8 96.0 406.0 C107.2 416.2 117.7 424.3 130.0 433.0 C142.3 441.7 156.2 450.5 170.0 458.0 C183.8 465.5 199.0 472.5 213.0 478.0 C227.0 483.5 244.2 489.2 254.0 491.0 C263.8 492.8 264.0 491.2 272.0 489.0 C280.0 486.8 289.3 484.0 302.0 478.0 C314.7 472.0 332.2 463.0 348.0 453.0 C363.8 443.0 382.3 429.8 397.0 418.0 C411.7 406.2 424.7 394.5 436.0 382.0 C447.3 369.5 456.8 357.2 465.0 343.0 C473.2 328.8 480.2 312.0 485.0 297.0 C489.8 282.0 492.5 267.7 494.0 253.0 C495.5 238.3 496.2 224.3 494.0 209.0 C491.8 193.7 486.3 174.3 481.0 161.0 C475.7 147.7 470.0 139.2 462.0 129.0 C454.0 118.8 442.2 107.5 433.0 100.0 C423.8 92.5 416.7 88.5 407.0 84.0 C397.3 79.5 384.5 75.2 375.0 73.0 C365.5 70.8 358.5 70.8 350.0 71.0 C341.5 71.2 331.5 72.5 324.0 74.0 C316.5 75.5 313.3 76.0 305.0 80.0 C296.7 84.0 284.8 98.0 274.0 98.0 C263.2 98.0 252.7 84.8 240.0 80.0 C227.3 75.2 211.5 70.8 198.0 69.0 C184.5 67.2 172.0 67.3 159.0 69.0 C146.0 70.7 132.8 73.8 120.0 79.0Z"/><path d="M466.0 28.0 C466.0 25.2 464.8 25.0 463.0 24.0 C461.2 23.0 464.3 22.5 455.0 22.0 C445.7 21.5 421.7 20.7 407.0 21.0 C392.3 21.3 378.7 22.5 367.0 24.0 C355.3 25.5 345.8 27.5 337.0 30.0 C328.2 32.5 320.2 36.0 314.0 39.0 C307.8 42.0 305.2 43.7 300.0 48.0 C294.8 52.3 288.3 58.3 283.0 65.0 C277.7 71.7 273.7 87.8 268.0 88.0 C262.3 88.2 254.8 71.8 249.0 66.0 C243.2 60.2 240.7 57.8 233.0 53.0 C225.3 48.2 212.3 41.0 203.0 37.0 C193.7 33.0 189.0 31.3 177.0 29.0 C165.0 26.7 146.2 24.0 131.0 23.0 C115.8 22.0 97.3 22.2 86.0 23.0 C74.7 23.8 66.8 25.7 63.0 28.0 C59.2 30.3 60.2 31.2 63.0 37.0 C65.8 42.8 72.8 55.2 80.0 63.0 C87.2 70.8 95.7 82.7 106.0 84.0 C116.3 85.3 128.3 73.8 142.0 71.0 C155.7 68.2 176.0 67.0 188.0 67.0 C200.0 67.0 205.3 69.0 214.0 71.0 C222.7 73.0 230.7 74.7 240.0 79.0 C249.3 83.3 264.3 94.0 270.0 97.0 C275.7 100.0 267.3 100.3 274.0 97.0 C280.7 93.7 297.3 81.5 310.0 77.0 C322.7 72.5 337.2 70.3 350.0 70.0 C362.8 69.7 375.7 72.0 387.0 75.0 C398.3 78.0 406.7 91.5 418.0 88.0 C429.3 84.5 447.5 61.8 455.0 54.0 C462.5 46.2 461.2 45.3 463.0 41.0 C464.8 36.7 466.0 30.8 466.0 28.0Z"/><path d="M281 101 C352 128 392 214 376 306 C363 386 322 446 266 486"/><path d="M92 146 C104 120 128 104 154 98"/></svg></span>
        <span class="tb-txt">
          <span class="tb-store" id="storeName"></span>
          <span class="tb-status" id="storeSub"></span>
        </span>
      </button>
      <div class="topbar-btns">
        <button class="ann-btn" id="annBtn" type="button" hidden aria-label="Pengumuman toko" aria-expanded="false"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 5L6 9H3a1 1 0 00-1 1v4a1 1 0 001 1h3l5 4V5z"/><path d="M15.5 8.5a5 5 0 010 7"/><path d="M18.5 5.5a9 9 0 010 13"/></svg><i class="ann-dot" id="annDot"></i></button>
        <button class="layout-btn" id="layoutBtn" type="button" aria-label="Ganti tampilan daftar/kotak"></button>
        <button class="theme-btn" id="themeBtn" type="button" aria-label="Ganti tampilan terang/gelap"></button>
      </div>
    </div>
    <div class="ann-pop" id="annPop" role="dialog" aria-label="Pengumuman toko">
      <h4><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11 5L6 9H3a1 1 0 00-1 1v4a1 1 0 001 1h3l5 4V5z"/><path d="M15.5 8.5a5 5 0 010 7"/></svg>Pengumuman</h4>
      <p id="annText"></p>
      <div class="ann-prog" aria-hidden="true"><i id="annProg"></i></div>
    </div>
    <div class="menu-scroll" id="menuScroll">
      <div class="closed-page" id="closedPage">
        <div class="stk" data-stk="closed" hidden></div>
        <h2>Toko sedang tutup</h2>
        <p class="cp-when" id="cpWhen"></p>
        <p class="cp-ann" id="cpAnn" hidden></p>
        <button class="cp-code" id="codeLink" type="button">Pelanggan langganan? Masukkan kode</button>
      </div>
      <div class="hero-block" id="heroBlock">
        <div class="stk" data-stk="home" hidden></div>
        <h2>Mau pesan apa hari ini?</h2>
        <p>Ketik nama barang atau pilih kategori</p>
      </div>
      <div class="sticky-head" id="stickyHead">
        <div class="search-wrap" id="searchWrap">
          <div class="search" id="searchBox">
            <svg class="mag" width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
            <div class="q-box">
              <input id="q" type="text" placeholder="Cari barang…" autocomplete="off" autocapitalize="off" spellcheck="false" enterkeyhint="search" aria-label="Cari barang" />
              <div class="ph off" id="phLayer" aria-hidden="true"><span class="cur" id="phA"></span><span class="down" id="phB"></span></div>
            </div>
            <button class="go" id="goBtn" type="button" aria-label="Cari" hidden><svg class="arr" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14"/><path d="M13 6l6 6-6 6"/></svg><svg class="x" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button>
          </div>
        </div>
        <div class="cat-row" id="catRow" role="group" aria-label="Kategori"></div>
      </div>
      <div class="landing-below" id="landingBelow">
        <div class="cats-hero" id="catsHero" role="group" aria-label="Kategori"></div>
        <div id="extrasSlotL"></div>
        <div class="game-slot" id="gameSlot">
<section class="maze-card" id="mazeCard" aria-label="Permainan labirin bola">
  <div class="mz-head">
    <div class="mz-title"><b>Lagi bosan? Main dulu</b><small id="mzSub">🎱 Bawa bola ke lubang tujuan</small></div>
    <button class="mz-ibtn" id="mzGyro" type="button" aria-pressed="false" aria-label="Kontrol dengan memiringkan HP (gyro)" title="Gyro">
      <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="7" y="3" width="10" height="18" rx="2.5"/><path d="M11 18h2"/><path d="M3.5 9a9 9 0 000 6M20.5 9a9 9 0 010 6"/></svg>
    </button>
    <button class="mz-ibtn" id="mzNew" type="button" aria-label="Labirin baru" title="Labirin baru">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 12a8 8 0 11-2.6-5.9"/><path d="M20 4v5h-5"/></svg>
    </button>
  </div>
  <div class="mz-seg" id="mzSeg" role="tablist" aria-label="Tingkat kesulitan">
    <button type="button" role="tab" data-lv="mudah" aria-selected="true">Mudah</button>
    <button type="button" role="tab" data-lv="sedang" aria-selected="false">Sedang</button>
    <button type="button" role="tab" data-lv="sulit" aria-selected="false">Sulit</button>
  </div>
  <div class="mz-stage" id="mzStage" tabindex="0" aria-label="Papan labirin. Geser untuk menggerakkan bola, atau gunakan tombol panah.">
    <canvas id="mzCanvas"></canvas>
    <div class="mz-win" id="mzWin" aria-live="polite"><b id="mzWinT">Selesai!</b><span id="mzWinS"></span><em id="mzWinR" hidden>Rekor baru!</em></div>
  </div>
  <div class="mz-foot"><span>Waktu <b id="mzTime">0,0</b> dtk</span><span id="mzBest">Rekor —</span></div>
  <p class="mz-hint" id="mzHint">Geser jari di papan untuk menggerakkan bola</p>
</section>
        </div>
      </div>
      <div class="extras-slot-b" id="extrasSlotB"></div>
      <div id="listWrap">
        <div class="list-info" id="listInfo" hidden></div>
        <div class="list" id="list"></div>
      </div>
    </div>
  </section>

  <!-- Halaman 2 — ringkasan pesanan. Ada di DOM sejak awal (blueprint §2). -->
  <section class="page page-order" id="pageOrder">
    <div class="topbar order-top">
      <button class="back-btn" id="backBtn" type="button" aria-label="Kembali ke daftar produk"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 18l-6-6 6-6"/></svg></button>
      <div class="order-title"><div class="tb-store">Pesanan Anda</div></div>
      <button class="clear-cart-btn" id="clearCartBtn" type="button" aria-label="Kosongkan pesanan"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></button>
    </div>
    <div class="order-body">
      <div class="paper-wrap"><div class="paper">
        <div class="paper-store" id="paperStore"></div>
        <div class="paper-sub" id="orderSub">0 produk dipilih</div>
        <div class="dash"></div>
        <div id="cartItems"></div>
        <div class="dash"></div>
        <div class="paper-total"><span>Total</span><b class="roll" id="sheetTotal">Rp 0</b></div>
        <div class="paper-hint">Ketuk &ldquo;Tambah?&rdquo; untuk ubah jumlah &middot; harga final di kasir</div>
      </div></div>
      <div class="ofield"><label for="custName">Nama</label><input id="custName" placeholder="Nama Anda" /></div>
      <div class="ofield"><label for="custPhone">No. HP</label><input id="custPhone" type="tel" placeholder="08xxxxxxxxxx" /></div>
      <div class="ofield"><label for="custNote">Catatan (opsional)</label><textarea id="custNote" rows="1" placeholder="mis. antar sore ya"></textarea></div>
      <button class="copy-link" id="copyBtn" type="button"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>Salin teks pesanan</button>
    </div>
  </section>

  <!-- Halaman pesanan terkirim: tampil seketika saat Kirim (WhatsApp/Telegram) ditekan. -->
  <section class="page page-sent" id="pageSent" aria-live="polite">
    <div class="sent-body">
      <div class="stk" data-stk="sent" hidden></div>
      <h2>Pesanan dikirim!</h2>
      <button class="sent-btn" id="sentBack" type="button">Kembali ke halaman awal</button>
    </div>
  </section>

  <!-- Blueprint §5 — tombol aksi utama tunggal, total menyatu di dalamnya. -->
  <div class="mainbtn-wrap hidden" id="mainBtnWrap">
    <div class="mb-row" id="mbRow">
      <button class="mb-clear" id="mbClear" type="button" aria-label="Kosongkan pesanan"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/></svg><span>Kosongkan pesanan</span></button>
      <button class="mainbtn" id="mainBtn" type="button">
        <span class="mb-q">Kosongkan pesanan?</span>
        <span class="mb-no">Tidak</span>
        <span class="mb-badge" id="mbBadge">0</span>
        <svg class="mb-ic" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413Z"/></svg>
        <span class="mb-label" id="mbLabel">Lihat Pesanan</span>
        <span class="mb-total roll" id="mbTotal">Rp 0</span>
      </button>
      <!-- Tombol Telegram: hanya bila toko mengisi kolom Telegram (DATA.telegramUrl);
           muncul di halaman Pesanan, berdampingan 50/50 dgn tombol WhatsApp. -->
      <button class="mainbtn mainbtn-tg" id="mainBtnTg" type="button" hidden aria-label="Kirim pesanan ke Telegram">
        <svg class="mb-ic" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/></svg>
        <span class="mb-label" id="mbLabelTg">Kirim ke Telegram</span>
        <span class="mb-total roll" id="mbTotalTg">Rp 0</span>
      </button>
    </div>
  </div>
</div>

<div class="scrim" id="itemScrim"></div>
<div class="sheet" id="itemSheet">
  <div class="sheet-grip"></div>
  <button class="sheet-x" id="itemSheetClose" type="button" aria-label="Tutup">&times;</button>
  <div class="sheet-body">
    <div class="im-hero">
      <div class="im-emoji" id="itemEmoji" aria-hidden="true"></div>
      <h1 class="im-name" id="itemTitle">Produk</h1>
      <span class="im-cat" id="itemCat"></span>
    </div>
    <div class="im-price" id="itemPriceDisplay"><span class="roll" id="itemPriceVal">Rp 0</span><small id="itemPriceUnit"></small></div>
    <div class="im-seg-wrap" id="itemSegWrap">
      <div class="im-seg-lbl">Satuan</div>
      <div class="im-seg" id="itemUnitChips"></div>
      <div class="im-seg-hint" id="itemSegHint"><span class="arr" aria-hidden="true">&rsaquo;</span> Geser untuk satuan lainnya</div>
    </div>
    <div class="im-seg-wrap" id="itemVarWrap">
      <div class="im-seg-lbl">Varian</div>
      <div class="im-seg" id="itemVarChips"></div>
      <div class="im-seg-hint" id="itemVarHint"><span class="arr" aria-hidden="true">&rsaquo;</span> Geser untuk varian lainnya</div>
    </div>
    <div class="im-qty">
      <button type="button" id="itemQtyDec" aria-label="Kurangi">&minus;</button>
      <input class="im-qty-input" id="itemQtyVal" type="number" inputmode="decimal" min="0" step="any" value="1" />
      <button type="button" class="p" id="itemQtyInc" aria-label="Tambah">+</button>
    </div>
    <div class="im-eq" id="itemEq"></div>
    <div class="im-note">
      <label for="itemNote">Catatan</label>
      <textarea id="itemNote" rows="1" placeholder="mis. yang matang, ukuran besar"></textarea>
    </div>
  </div>
  <div class="sheet-foot">
    <div class="grand"><span class="gl">Subtotal</span><span class="gv roll" id="itemSubtotal">Rp 0</span></div>
    <div class="im-actions nodel" id="itemActions">
      <button class="mb-clear" id="itemRemoveBtn" type="button" aria-label="Hapus dari pesanan"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/></svg><span>Hapus dari pesanan</span></button>
      <button class="add-cta" id="itemAddBtn" type="button">Tambah ke Pesanan</button>
    </div>
  </div>
</div>


<div class="extras" id="extras" hidden>
  <div id="againWrap" hidden>
    <div class="sect">Pesan lagi</div>
    <div class="again">
      <div class="again-t"><div class="t" id="againTitle"></div><div class="s" id="againSub"></div></div>
      <button class="btn" id="againBtn" type="button">Pesan lagi</button>
    </div>
    <div class="link-row"><button class="link" id="histOpen" type="button">Lihat semua pesanan (<span id="histN">0</span>)</button></div>
  </div>
  <div id="noHist" hidden>
    <div class="sect">Pesan lagi</div>
    <div class="nohist"><b>Belum ada riwayat di HP ini</b><span>Punya pesanan lama di WhatsApp? Tempel di bawah.</span></div>
  </div>
  <div class="paste">
    <input class="inp" id="pasteIn" type="text" placeholder="Tempel pesanan lama…" autocomplete="off" autocapitalize="off" spellcheck="false" aria-label="Tempel pesanan lama dari WhatsApp" />
    <button class="btn2" id="pasteBtn" type="button">Muat</button>
  </div>
  <div class="paste-msg" id="pasteMsg" role="status"></div>
</div>

<div class="scrim" id="histScrim"></div>
<div class="sheet" id="histSheet" role="dialog" aria-label="Pesanan sebelumnya">
  <div class="sheet-grip"></div>
  <button class="sheet-x" id="histClose" type="button" aria-label="Tutup">&times;</button>
  <div class="sheet-head"><b>Pesanan sebelumnya <span id="histCount"></span></b></div>
  <div class="sheet-body hist-body" id="histList"></div>
  <div class="hist-msg" id="histMsg" role="status"></div>
</div>

<div class="confirm-overlay" id="confirmOverlay">
  <div class="confirm-box">
    <div class="confirm-title" id="confirmTitle"></div>
    <div class="confirm-body" id="confirmBody"></div>
    <div class="confirm-actions">
      <button class="btn-cancel" id="confirmCancel" type="button">Batal</button>
      <button class="btn-danger" id="confirmOk" type="button">Hapus</button>
    </div>
  </div>
</div>

<div class="confirm-overlay" id="codeOverlay">
  <div class="confirm-box">
    <div class="confirm-title">Kode pelanggan</div>
    <div class="confirm-body">Masukkan kode yang diberikan toko untuk memesan saat toko tutup.</div>
    <input class="tfield" id="codeInput" type="text" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="XXXX-XXXX" />
    <div class="code-err" id="codeErr"></div>
    <div class="confirm-actions">
      <button class="btn-cancel" id="codeCancel" type="button">Batal</button>
      <button class="btn-ok" id="codeOk" type="button">Masuk</button>
    </div>
  </div>
</div>

<div class="toast" id="toast"></div>

__STICKER_BLOCKS__<script>
var DATA = __DATA_JSON__;
var cart = {}; // unitId -> qty
var cartNotes = {}; // unitId -> catatan per-produk (Item 26a)
var byUnit = {}; // unitId -> {name, unit, price, parentName}
var unitProduct = {}; // unitId -> indeks produk induk (utk hitung badge per PRODUK)
var sheetOpen = false; // hindari renderCartSheet() sia-sia saat sheet tertutup
var itemModalProduct = null; // produk aktif di modal tap-item (Item 14)
var itemModalUnitId = null; // satuan/varian aktif di modal
var itemModalQty = 1;
var _mbOrderMode = null; // mode terakhir yg dirender tombol utama (utk samarkan saat susunan berganti)
var _mbBadgeCount = 0; // qty terakhir dirender di badge tombol utama — dipakai
                        // renderCartBar() utk tahu kapan HARUS retrigger animasi
                        // (badge per-baris sudah begini, tombol utama belum, Item 79 lanjutan).

// ── Toggle terang/gelap manual — menimpa prefers-color-scheme, disimpan
// per-browser lewat localStorage supaya pilihan bertahan saat file dibuka lagi.
var ICON_SUN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>';
var ICON_MOON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.8A9 9 0 1111.2 3a7 7 0 009.8 9.8z"/></svg>';

function applyTheme(mode){
  document.documentElement.setAttribute('data-theme', mode);
  document.getElementById('themeBtn').innerHTML = mode === 'dark' ? ICON_SUN : ICON_MOON;
}
function initTheme(){
  // Default SELALU terang kalau belum pernah dipilih manual — TIDAK ikut
  // prefers-color-scheme HP pelanggan (lihat komentar CSS di atas).
  var saved = null;
  try { saved = localStorage.getItem('posOrderTheme'); } catch (e) {}
  if (saved !== 'light' && saved !== 'dark') saved = 'light';
  applyTheme(saved);
}
document.getElementById('themeBtn').addEventListener('click', function(){
  var cur = document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
  var next = cur === 'dark' ? 'light' : 'dark';
  applyTheme(next);
  try { localStorage.setItem('posOrderTheme', next); } catch (e) {}
});
initTheme();

// ── Item 79 M2 — toggle List/Tile, pola sama persis toggle tema di atas
// (localStorage per-browser, default 'list' kalau belum pernah dipilih).
// Murni CSS (class `tile-mode` di #list) -- renderList()/setQty()/dst
// TIDAK disentuh sama sekali, jadi tidak ada logic keranjang baru yang
// bisa regresi lewat perubahan ini.
var ICON_LIST = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>';
var ICON_TILE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></svg>';
function applyLayout(mode){
  var list = document.getElementById('list');
  list.classList.toggle('tile-mode', mode === 'tile');
  // Ikon tombol menunjukkan mode TUJUAN (apa yang akan terjadi kalau
  // ditekan), sama konvensi ikon matahari/bulan di atas.
  document.getElementById('layoutBtn').innerHTML = mode === 'tile' ? ICON_LIST : ICON_TILE;
}
function initLayout(){
  var saved = null;
  try { saved = localStorage.getItem('posOrderLayout'); } catch (e) {}
  if (saved !== 'list' && saved !== 'tile') saved = 'list';
  applyLayout(saved);
}
document.getElementById('layoutBtn').addEventListener('click', function(){
  var list = document.getElementById('list');
  var cur = list.classList.contains('tile-mode') ? 'tile' : 'list';
  var next = cur === 'tile' ? 'list' : 'tile';
  // Item 79 M4 — fade singkat sebelum reflow grid<->list, supaya baris
  // tidak "melompat" instan. Cuma di jalur klik (bukan initLayout() saat
  // load) supaya tidak ada flash kosong yang tidak perlu di render pertama.
  list.style.opacity = '0';
  setTimeout(function(){
    applyLayout(next);
    list.style.opacity = '1';
  }, 120);
  try { localStorage.setItem('posOrderLayout', next); } catch (e) {}
});
initLayout();

// ── Persist keranjang lewat localStorage — permintaan user: katalog HTML
// ini statis (bukan app), refresh/reload browser HILANGKAN state JS murni
// (var cart di memori) tanpa ini. Di-keyed per DATA.generatedAt (versi
// katalog) supaya kalau toko generate katalog baru (harga/stok beda), cache
// lama dari katalog SEBELUMNYA otomatis dianggap basi & tidak dipakai —
// PLUS kedaluwarsa 1 hari sbg jaga-jaga tambahan (pelanggan buka lagi jauh
// hari kemudian). Tombol "Kosongkan" disediakan (di header sheet Pesanan)
// utk kasus cache masih ada tapi pelanggan mau mulai pesanan batch baru.
var CART_TTL_MS = 24 * 60 * 60 * 1000;
var CART_STORAGE_KEY = 'posOrderCart';

function saveCart(){
  try {
    localStorage.setItem(CART_STORAGE_KEY, JSON.stringify({
      generatedAt: DATA.generatedAt,
      savedAt: Date.now(),
      cart: cart,
      cartNotes: cartNotes
    }));
  } catch (e) {}
}

function loadCart(){
  try {
    var raw = localStorage.getItem(CART_STORAGE_KEY);
    if (!raw) return;
    var saved = JSON.parse(raw);
    if (!saved || saved.generatedAt !== DATA.generatedAt) return;
    if (typeof saved.savedAt !== 'number' || (Date.now() - saved.savedAt) > CART_TTL_MS) return;
    cart = saved.cart || {};
    cartNotes = saved.cartNotes || {};
  } catch (e) {}
}

// Modal konfirmasi generik (ganti confirm() bawaan browser yang tidak
// ikut tema app) — dipakai baik utk kosongkan semua maupun hapus satu
// barang, supaya kedua tindakan destruktif ini konsisten butuh konfirmasi
// eksplisit sebelum benar-benar menghapus data pesanan pelanggan.
var _confirmCb = null;
function showConfirm(title, body, okLabel, cb){
  _confirmCb = cb;
  document.getElementById('confirmTitle').textContent = title;
  document.getElementById('confirmBody').textContent = body;
  document.getElementById('confirmOk').textContent = okLabel;
  document.getElementById('confirmOverlay').classList.add('show');
}
function hideConfirm(){
  document.getElementById('confirmOverlay').classList.remove('show');
  _confirmCb = null;
}
document.getElementById('confirmCancel').addEventListener('click', hideConfirm);
document.getElementById('confirmOverlay').addEventListener('click', function(e){
  if (e.target === this) hideConfirm();
});
document.getElementById('confirmOk').addEventListener('click', function(){
  var cb = _confirmCb;
  hideConfirm();
  if (cb) cb();
});

function doClearCart(){
  cart = {};
  cartNotes = {};
  _drafts = {};
  try { localStorage.removeItem(CART_STORAGE_KEY); localStorage.removeItem(DRAFT_KEY); } catch (e) {}
  setClearConfirm(false);
  render();
}
// Header halaman Pesanan: tetap popup konfirmasi.
function clearCart(){
  if (cartCount() === 0) return;
  showConfirm(
    'Kosongkan Keranjang?',
    'Semua barang (' + cartCount() + ' produk) akan dihapus dari pesanan ini. Tindakan ini tidak bisa dibatalkan.',
    'Kosongkan',
    doClearCart
  );
}
document.getElementById('clearCartBtn').addEventListener('click', clearCart);

// Halaman awal: tombol Kosongkan memakai konfirmasi INLINE Ya/Tidak di baris
// tombol yang sama (tombol hapus jadi "Ya" merah 1/4 di kiri, tombol utama
// jadi "Tidak" netral 3/4 di kanan), dgn animasi lebar yang sama. Bertahan
// sampai Ya/Tidak ditekan (atau pesanan kosong) — scroll/ketik tidak membatalkan.
var clearConfirm = false;
function setClearConfirm(on){
  if (clearConfirm === on) return;
  clearConfirm = on;
  var wrap = document.getElementById('mainBtnWrap');
  var mainBtn = document.getElementById('mainBtn');
  var clr = document.getElementById('mbClear');
  // Susunan isi berganti: samarkan sesaat supaya tidak melompat.
  mainBtn.classList.add('swapping');
  clr.classList.add('swapping');
  wrap.classList.toggle('mb-confirm', on);
  clr.querySelector('span').textContent = on ? 'Ya' : 'Kosongkan pesanan';
  clr.setAttribute('aria-label', on ? 'Ya, kosongkan pesanan' : 'Kosongkan pesanan');
  setTimeout(function(){ mainBtn.classList.remove('swapping'); clr.classList.remove('swapping'); }, 60);
}
document.getElementById('mbClear').addEventListener('click', function(){
  if (clearConfirm) { doClearCart(); return; }
  if (cartCount() === 0) return;
  setClearConfirm(true);
});

// Scroll daftar ke bawah: keterangan tombol Kosongkan menyusut (sisa ikon);
// scroll ke atas / di posisi paling atas: muncul lagi.
(function(){
  var listEl = document.getElementById('menuScroll');
  var wrap = document.getElementById('mainBtnWrap');
  var last = 0, ticking = false;
  listEl.addEventListener('scroll', function(){
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function(){
      ticking = false;
      var y = listEl.scrollTop, d = y - last;
      if (y <= 8) wrap.classList.remove('mb-collapsed');
      else if (d > 6) wrap.classList.add('mb-collapsed');
      else if (d < -6) wrap.classList.remove('mb-collapsed');
      if (Math.abs(d) > 6 || y <= 8) last = y;
    });
  }, {passive: true});
})();

DATA.products.forEach(function(p, pIdx){
  // Satuan lain (mis. Dus di samping Biji) sama-sama milik produk INI —
  // dikelompokkan di keranjang/pesanan sama seperti varian (parentName
  // diisi) begitu ada lebih dari 1 satuan, supaya tidak ambigu antara 2
  // baris "Sedap Goreng" yang cuma beda satuan.
  var pUnits = (p.units && p.units.length) ? p.units : [{unitId:p.unitId, unit:p.unit, price:p.price}];
  var pMulti = pUnits.length > 1;
  pUnits.forEach(function(u){
    unitProduct[u.unitId] = pIdx;
    byUnit[u.unitId] = {
      name: pMulti ? (p.name + ' — ' + u.unit) : p.name,
      unit: u.unit, price: u.price,
      parentName: pMulti ? p.name : null
    };
  });
  (p.variants||[]).forEach(function(v){
    var vUnits = (v.units && v.units.length) ? v.units : [{unitId:v.unitId, unit:v.unit, price:v.price}];
    var vMulti = vUnits.length > 1;
    vUnits.forEach(function(u){
      unitProduct[u.unitId] = pIdx;
      byUnit[u.unitId] = {
        name: p.name + ' — ' + v.name + (vMulti ? ' (' + u.unit + ')' : ''),
        unit: u.unit, price: u.price, parentName: p.name
      };
    });
  });
});

document.getElementById('storeName').textContent = DATA.store;
document.getElementById('paperStore').textContent = DATA.store;
// Logo header = persik The POS (garis putih di kotak aksen), disematkan di HTML.
// Baris status header (buka/tutup + jam) — diisi renderStatus() di bawah.

// ── Angka roll (mesin slot) utk total/subtotal. Digit yang berubah memutar
// strip [lama, acak..., baru] naik ATAU turun (acak), lalu strip diruntuhkan
// jadi teks biasa. Perbandingan digit dari kanan (satuan), jadi "9.500" ->
// "10.500" hanya memutar digit yang beda. Panggilan baru saat roll masih
// berjalan langsung memulai dari nilai akhir sebelumnya (tanpa antrean).
var ROLL_LH = 1.15; // em, sama dgn .rd/.rs i di CSS
var ROLL_REDUCED = false;
try { ROLL_REDUCED = window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) {}
function rollSet(el, text){
  if (!el) return;
  var old = el._rt;
  if (old === text) return;
  el._rt = text;
  clearTimeout(el._rtm);
  if (old === undefined || ROLL_REDUCED) { el.textContent = text; return; }
  el.setAttribute('aria-label', text);
  // Posisi kiri teks SEKARANG (termasuk transform yg sedang berjalan) —
  // dipakai di bawah utk meluncurkan teks mulus bila jumlah digit berubah.
  var oldLeft = rollLeft(el);
  el.style.transition = 'none';
  el.style.transform = '';
  el.innerHTML = '';
  var frag = document.createDocumentFragment();
  var pending = [];
  var nLen = text.length, oLen = old.length;
  for (var i = 0; i < nLen; i++) {
    var c = text.charAt(i);
    var oi = i - (nLen - oLen);
    var oc = oi >= 0 ? old.charAt(oi) : '';
    var isDigit = c >= '0' && c <= '9';
    var cell = document.createElement('span');
    if (!isDigit || oc === c) {
      cell.textContent = c;
      frag.appendChild(cell);
      continue;
    }
    cell.className = 'rd';
    var from = (oc >= '0' && oc <= '9') ? +oc : Math.floor(Math.random() * 10);
    var k = 2 + Math.floor(Math.random() * 4);
    var seq = [from];
    for (var j = 0; j < k; j++) seq.push(Math.floor(Math.random() * 10));
    seq.push(+c);
    var up = Math.random() < 0.5;
    var items = up ? seq : seq.slice().reverse();
    var strip = document.createElement('span');
    strip.className = 'rs';
    items.forEach(function(d){
      var it = document.createElement('i');
      it.textContent = d;
      strip.appendChild(it);
    });
    var last = items.length - 1;
    strip.style.transform = 'translateY(' + (up ? 0 : -last * ROLL_LH) + 'em)';
    pending.push([strip, up ? -last * ROLL_LH : 0]);
    cell.appendChild(strip);
    frag.appendChild(cell);
  }
  el.appendChild(frag);
  void el.offsetWidth; // paksa reflow supaya transisi mulai dari posisi awal
  // Jumlah digit berubah (9.999 -> 10.000): teks rata-kanan/tengah akan
  // melompat selebar satu digit. Mulai dari posisi lama lalu geser mulus
  // bersama putaran digit. Jumlah digit sama => dx = 0 (tidak ada geseran).
  var dx = oldLeft - rollLeft(el);
  if (Math.abs(dx) > 0.5 && !isNaN(dx)) {
    el.style.transform = 'translateX(' + dx + 'px)';
    void el.offsetWidth;
    el.style.transition = 'transform .6s cubic-bezier(.2,.8,.2,1)';
    el.style.transform = 'translateX(0)';
  }
  pending.forEach(function(p){
    p[0].style.transition = 'transform .6s cubic-bezier(.2,.8,.2,1)';
    p[0].style.transform = 'translateY(' + p[1] + 'em)';
  });
  el._rtm = setTimeout(function(){
    el.textContent = text;
    el.style.transition = '';
    el.style.transform = '';
  }, 680);
}
// Tepi kiri teks di elemen roll (teks biasa ATAU deretan sel hasil roll).
function rollLeft(el){
  var n = el.firstChild;
  if (!n) return el.getBoundingClientRect().left;
  if (n.nodeType === 3) {
    var r = document.createRange();
    r.selectNodeContents(n);
    return r.getBoundingClientRect().left;
  }
  return n.getBoundingClientRect().left;
}

function rp(n){
  var s = Math.round(n).toString();
  var out = '';
  for (var i=0;i<s.length;i++){
    if (i>0 && (s.length-i)%3===0) out += '.';
    out += s[i];
  }
  return 'Rp ' + out;
}

// Item 79 — auto-pilih ikon produk TANPA config manual per produk:
// (1) kata kunci nama produk (kasus umum toko kelontong Indonesia),
// (2) fallback ke kategori produk (SUDAH dikurasi owner, gratis dari data
//     yang ada, lihat field `category` di `_buildCatalogJson`),
// (3) fallback terakhir ikon generik. Kamus kata kunci sengaja DATA
// STATIS (bukan model/ML) — murah, dapat diaudit, mudah ditambah kalau
// ada laporan "ikon salah/generik" utk produk tertentu.
var ICON_KEYWORDS = [
  [['beras','rojolele','pandan wangi'], '🌾'],
  [['minyak goreng','minyak kelapa'], '🫙'],
  [['gula pasir','gula merah','gula aren'], '🧂'],
  [['telur'], '🥚'],
  [['indomie','mie instan','mie goreng','mie ayam','sedaap'], '🍜'],
  [['kopi'], '☕'],
  [['teh celup','teh tubruk','teh '], '🍵'],
  [['aqua','air mineral','air minum'], '💧'],
  [['gas','lpg','tabung'], '🔥'],
  [['sabun mandi','sabun cuci','lifebuoy','deterjen','rinso'], '🧼'],
  [['rokok'], '🚬'],
  [['susu'], '🥛'],
  [['roti'], '🍞'],
  [['gula-gula','permen','coklat','cokelat'], '🍬'],
  [['kerupuk'], '🍘'],
  [['sampo','shampo'], '🧴'],
  [['pasta gigi','odol'], '🪥'],
  [['popok','diapers','pembalut'], '🧷'],
  [['beras','tepung terigu','tepung beras'], '🌾'],
  [['saus','kecap','sambal'], '🫙'],
  [['garam'], '🧂']
];
// Kategori (product_groups) -> ikon generik. Nama kategori bebas diisi
// owner sendiri, jadi cocokkan case-insensitive & substring, bukan exact.
var CATEGORY_ICONS = [
  [['sembako'], '🌾'],
  [['minuman'], '🥤'],
  [['makanan','snack','camilan'], '🍪'],
  [['mandi','cuci','kebersihan','rumah tangga'], '🧼'],
  [['rokok'], '🚬'],
  [['bayi'], '🍼'],
  [['bumbu','dapur'], '🧂'],
  [['gas','bahan bakar'], '🔥']
];
var ICON_DEFAULT = '🛒';
function matchDict(dict, text){
  var t = (text||'').toLowerCase();
  for (var i=0;i<dict.length;i++){
    var keywords = dict[i][0];
    for (var j=0;j<keywords.length;j++){
      if (t.indexOf(keywords[j]) >= 0) return dict[i][1];
    }
  }
  return null;
}
function pickIcon(name, category){
  return matchDict(ICON_KEYWORDS, name) ||
    matchDict(CATEGORY_ICONS, category) ||
    ICON_DEFAULT;
}

function fmtQty(q){
  return (q % 1 === 0) ? String(q) : String(q);
}

// Jumlah PRODUK berbeda di pesanan (bukan total qty): satu produk dgn
// beberapa satuan/varian tetap dihitung 1 (mis. gula pcs + gula dus = 1).
// Nol <=> keranjang kosong, jadi tetap aman dipakai sbg penjaga "kosong?".
function cartCount(){
  var seen = {}, n = 0;
  for (var k in cart) {
    if (!(cart[k] > 0)) continue;
    var key = (unitProduct[k] !== undefined) ? 'p' + unitProduct[k] : 'u' + k;
    if (!seen[key]) { seen[key] = true; n++; }
  }
  return n;
}
function cartTotal(){
  var t = 0;
  for (var k in cart) { var u = byUnit[k]; if (u) t += u.price * cart[k]; }
  return t;
}
function _ownUnits(p){
  return (p.units && p.units.length) ? p.units : [{unitId:p.unitId, unit:p.unit, price:p.price}];
}
function totalQtyForProduct(p){
  var n = 0;
  _ownUnits(p).forEach(function(u){ n += cart[u.unitId] || 0; });
  (p.variants||[]).forEach(function(v){
    _ownUnits(v).forEach(function(u){ n += cart[u.unitId] || 0; });
  });
  return n;
}
function minPriceForProduct(p){
  var prices = _ownUnits(p).map(function(u){ return u.price; });
  (p.variants||[]).forEach(function(v){
    _ownUnits(v).forEach(function(u){ prices.push(u.price); });
  });
  return Math.min.apply(null, prices);
}
// Total satuan/varian yang bisa dipilih pelanggan — dipakai renderList utk
// tahu apakah tampilkan "N pilihan · mulai Rp X" atau harga satuan tunggal.
function totalOptionsFor(p){
  var n = _ownUnits(p).length;
  (p.variants||[]).forEach(function(v){ n += _ownUnits(v).length; });
  return n;
}
function unitOptionsFor(p){
  var opts = [];
  _ownUnits(p).forEach(function(u){
    opts.push({unitId:u.unitId, label:u.unit, unit:u.unit, price:u.price});
  });
  (p.variants||[]).forEach(function(v){
    var vUnits = _ownUnits(v);
    var vMulti = vUnits.length > 1;
    vUnits.forEach(function(u){
      opts.push({
        unitId:u.unitId,
        label: vMulti ? (v.name + ' (' + u.unit + ')') : v.name,
        unit:u.unit, price:u.price
      });
    });
  });
  return opts;
}
function findProductForUnit(unitId){
  for (var i=0;i<DATA.products.length;i++){
    var p = DATA.products[i];
    var pUnits = _ownUnits(p);
    for (var k=0;k<pUnits.length;k++){ if (pUnits[k].unitId === unitId) return p; }
    for (var j=0;j<(p.variants||[]).length;j++){
      var vUnits = _ownUnits(p.variants[j]);
      for (var m=0;m<vUnits.length;m++){ if (vUnits[m].unitId === unitId) return p; }
    }
  }
  return null;
}

function setQty(unitId, qty){
  dropDraft(unitId);
  if (qty <= 0) {
    delete cart[unitId];
    delete cartNotes[unitId];
  } else {
    cart[unitId] = qty;
  }
  // Render ulang HANYA baris produk yang badge qty-nya berubah, bukan
  // renderList() penuh (dulu membangun ulang SELURUH grid tiap klik +/-,
  // O(jumlah produk) kerja DOM per tap — kerasa lag di katalog besar).
  // Sisa baris (nama/meta/harga) tidak pernah berubah gara-gara qty, jadi
  // aman di-skip. Fallback ke renderList() penuh kalau produk somehow
  // tidak ketemu (mis. unitId dari sumber tak terduga).
  var p = findProductForUnit(unitId);
  if (p) refreshProwControls(p); else renderList(true);
  renderCartBar();
  if (sheetOpen) renderCartSheet();
  saveCart();
}

// Update badge +/qty SATU baris produk di tempat (tanpa rebuild grid).
// No-op kalau baris sedang tidak tampil (mis. terfilter search) — nanti
// otomatis benar begitu renderList() jalan lagi (search berubah).
function refreshProwControls(p){
  var row = document.querySelector('.prow[data-pid="'+p.id+'"]');
  if (!row) return;
  var wrap = row.querySelector('.prow-controls');
  if (!wrap) return; // stok habis — tidak ada kontrol qty utk diupdate
  syncProwControls(wrap, p, true);
  // Blueprint §3 — ikon memantul sekali sbg umpan balik visual. Kelasnya
  // dilepas + dipaksa reflow dulu supaya animasi benar-benar diputar ulang
  // walau tombol ditekan berkali-kali cepat.
  var icon = row.querySelector('.prow-icon');
  if (icon) {
    icon.classList.remove('icon-pop');
    void icon.offsetWidth;
    icon.classList.add('icon-pop');
  }
}

// ── Toko tutup (jadwal jam + kode pelanggan). SEMUA pengecekan di browser
// (halaman statis): penghalang utk pelanggan biasa, bukan pagar mutlak.
// Jam toko dihitung dari zona waktu HP owner saat Publish (DATA.hours.tz),
// BUKAN jam lokal pelanggan. Harga saat tutup hanya disembunyikan di
// TAMPILAN (data tetap ada di sumber halaman).
var ACCESS_KEY = 'posOrderAccess';
var shopClosed = false;      // efektif (sudah memperhitungkan kode)
var accessGranted = false;
var _emptyCatalog = !DATA.products || DATA.products.length === 0;

function fmtHHMM(m){
  var h = Math.floor(m / 60), mm = m % 60;
  return (h < 10 ? '0' : '') + h + '.' + (mm < 10 ? '0' : '') + mm;
}
function shopMinutesNow(){
  var d = new Date(Date.now() + DATA.hours.tz * 60000);
  return d.getUTCHours() * 60 + d.getUTCMinutes();
}
// {closed, msg} menurut jadwal (tanpa memperhitungkan kode).
function hoursState(){
  var h = DATA.hours;
  if (!h) return {closed: false, msg: '', when: ''};
  if (h.forced) return {closed: true, msg: 'Toko sedang tutup sementara', when: 'Toko sedang tutup sementara'};
  if (!h.enabled) return {closed: false, msg: ''};
  var now = shopMinutesNow(), o = h.open, c = h.close;
  var isOpen = (o === c) ? true : (o < c ? (now >= o && now < c) : (now >= o || now < c));
  if (isOpen) return {closed: false, msg: ''};
  var today = (o < c) ? (now < o) : true; // jendela lewat tengah malam: buka lagi hari ini
  return {closed: true, msg: 'Toko tutup · buka ' + (today ? 'hari ini ' : 'besok ') + fmtHHMM(o),
          when: 'Buka lagi ' + (today ? 'hari ini' : 'besok') + ' pukul ' + fmtHHMM(o)};
}
function loadAccess(){
  accessGranted = false;
  try {
    var raw = localStorage.getItem(ACCESS_KEY);
    if (!raw || !DATA.access) return;
    var saved = JSON.parse(raw);
    if (saved && DATA.access.hashes.indexOf(saved.hash) >= 0) accessGranted = true;
  } catch (e) {}
}
// Game: halaman awal (bawah) atau, saat toko tutup, bawah halaman tutup.
function placeGame(closed){
  var g = document.getElementById('gameSlot');
  if (!g) return;
  var host = closed ? document.getElementById('closedPage') : document.querySelector('.landing-below');
  if (host && g.parentNode !== host) host.appendChild(g);
}
var _lastClosedKey = null;
function applyOpenState(){
  renderStatus();
  var st = hoursState();
  var closed = st.closed && !accessGranted;
  var app = document.getElementById('app');
  var key = closed + '|' + st.msg;
  shopClosed = closed;
  if (key === _lastClosedKey) return;
  _lastClosedKey = key;
  app.classList.toggle('closed', closed || _emptyCatalog);
  // Toko tutup = halaman khusus (stiker + jam buka + pengumuman + tautan kode).
  app.classList.toggle('shop-closed', closed);
  document.getElementById('cpWhen').textContent = st.when || '';
  var cpAnn = document.getElementById('cpAnn');
  cpAnn.hidden = !(closed && ANN);
  if (ANN) cpAnn.textContent = ANN;
  if (closed) closeAnn();
  placeGame(closed);
  document.getElementById('codeLink').style.display =
      (DATA.access && DATA.access.hashes && DATA.access.hashes.length) ? '' : 'none';
  if (closed && sheetOpen) closeSheet(false);
  renderList(true); // shopClosed berubah — harga/meta baris ikut berubah
  renderCartBar();
}

// Kode pelanggan: PBKDF2-HMAC-SHA256 (sama dgn app) lalu cocokkan ke daftar hash.
function normCode(s){ return String(s || '').toUpperCase().replace(/[^A-Z0-9]/g, ''); }
function hexOf(buf){
  var a = new Uint8Array(buf), out = '';
  for (var i = 0; i < a.length; i++) out += (a[i] < 16 ? '0' : '') + a[i].toString(16);
  return out;
}
function hashCode(code){
  var enc = new TextEncoder();
  return crypto.subtle.importKey('raw', enc.encode(normCode(code)), {name: 'PBKDF2'}, false, ['deriveBits'])
    .then(function(key){
      return crypto.subtle.deriveBits({name: 'PBKDF2', salt: enc.encode(DATA.access.salt),
        iterations: DATA.access.iters, hash: 'SHA-256'}, key, 256);
    }).then(hexOf);
}
var _codeFails = 0, _codeLockUntil = 0;
function openCodeDialog(){
  document.getElementById('codeErr').textContent = '';
  document.getElementById('codeInput').value = '';
  document.getElementById('codeOverlay').classList.add('show');
  setTimeout(function(){ document.getElementById('codeInput').focus(); }, 60);
}
function closeCodeDialog(){ document.getElementById('codeOverlay').classList.remove('show'); }
function submitCode(){
  var err = document.getElementById('codeErr');
  var code = document.getElementById('codeInput').value;
  if (!normCode(code)) { err.textContent = 'Masukkan kode dulu'; return; }
  if (Date.now() < _codeLockUntil) { err.textContent = 'Terlalu banyak percobaan — coba lagi sebentar'; return; }
  if (!(window.crypto && crypto.subtle)) {
    err.textContent = 'Browser ini belum mendukung — buka lewat Chrome atau Safari';
    return;
  }
  hashCode(code).then(function(h){
    if (DATA.access.hashes.indexOf(h) >= 0) {
      _codeFails = 0;
      try { localStorage.setItem(ACCESS_KEY, JSON.stringify({hash: h})); } catch (e) {}
      accessGranted = true;
      _lastClosedKey = null;
      closeCodeDialog();
      applyOpenState();
      showToast('Kode diterima — silakan memesan');
    } else {
      _codeFails++;
      if (_codeFails >= 5) { _codeLockUntil = Date.now() + 30000; _codeFails = 0; }
      err.textContent = 'Kode salah';
    }
  }).catch(function(){ err.textContent = 'Gagal memeriksa kode — coba lagi'; });
}
document.getElementById('codeLink').addEventListener('click', openCodeDialog);
document.getElementById('codeCancel').addEventListener('click', closeCodeDialog);
document.getElementById('codeOk').addEventListener('click', submitCode);
document.getElementById('codeInput').addEventListener('keydown', function(e){
  if (e.key === 'Enter') submitCode();
});
document.getElementById('codeOverlay').addEventListener('click', function(e){
  if (e.target === this) closeCodeDialog();
});

// Daftar dibatasi PAGE_SIZE baris per tampilan: membangun ribuan baris DOM
// tiap ketikan terukur 2-10 dtk di HP low-end (2000 produk ~22.000 node).
// Pelanggan mencari dengan mengetik, hampir tak pernah menggulir semuanya.
// Pencocokan query TETAP memeriksa SELURUH produk — hanya yang dirender
// yang dibatasi. JANGAN ganti dgn content-visibility (terukur memperburuk
// scroll) atau infinite scroll.
var PAGE_SIZE = 60;
var shownLimit = PAGE_SIZE;   // baris maks yang dirender utk query aktif
var _lastQ = null;            // query (trim+lowercase) render terakhir ('' = tanpa query)
var _lastKey = null;          // kunci isi daftar render terakhir (query / kategori / semua)
var _stale = false;           // true = render dilewati saat landing, wajib dibangun ulang
var _matches = [];            // produk yang cocok utk _lastQ (semua, bukan hanya yang tampil)
var _renderedCount = 0;       // berapa dari _matches yang sudah ada di DOM
var _moreBar = null;          // elemen keterangan + tombol "Tampilkan lagi"

// Indeks pencarian — dihitung SEKALI saat halaman dibuka (nama produk +
// nama tiap varian, huruf kecil). Aturan cocok sama persis dgn dulu: nama
// produk cocok ATAU ada varian yang cocok (baris induk tetap tampil).
var SEARCH_INDEX = DATA.products.map(function(p){
  return {
    n: String(p.name).toLowerCase(),
    v: (p.variants || []).map(function(v){ return String(v.name).toLowerCase(); })
  };
});
function matchesQuery(i, q){
  var ix = SEARCH_INDEX[i];
  if (ix.n.indexOf(q) >= 0) return true;
  for (var k = 0; k < ix.v.length; k++) { if (ix.v[k].indexOf(q) >= 0) return true; }
  return false;
}
function fmtCount(n){ return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, '.'); }

function buildProductRow(p){
  var row = document.createElement('div');
  row.className = 'prow';
  row.dataset.pid = p.id;
  var main = document.createElement('div');
  main.className = 'prow-main';

  var metaHtml = shopClosed ? '—' : (totalOptionsFor(p) > 1
    ? totalOptionsFor(p) + ' pilihan · mulai ' + rp(minPriceForProduct(p))
    : rp(p.price) + ' /' + esc(p.unit));
  main.innerHTML =
    '<div class="prow-icon" aria-hidden="true">'+pickIcon(p.name, p.category)+'</div>' +
    '<div class="prow-info"><div class="prow-name">'+esc(p.name)+'</div>' +
      '<div class="prow-meta">'+metaHtml+'</div>' +
      (CATS_ON && p.category ? '<div class="prow-cat">'+esc(p.category)+'</div>' : '') +
      '</div>';

  if (p.outOfStock) {
    // Item 25a — tanda stok habis manual: badge menggantikan tombol
    // tambah, tidak bisa dipesan lewat katalog HTML statis ini.
    main.insertAdjacentHTML('beforeend', '<span class="oos-badge">Stok Habis</span>');
  } else {
    // Kontrol +/− meniru _AddControl di app kasir (lingkaran "+" oranye,
    // berubah jadi angka hijau + minus merah begitu ada qty). Tap SISA
    // badan baris (bukan tombol) buka modal pilih satuan/catatan — sama
    // seperti tap badan kartu produk di app kasir.
    main.appendChild(buildProwControls(p));
    main.addEventListener('click', function(e){
      if (e.target.closest('.prow-controls')) return;
      openItemModal(p);
    });
  }
  row.appendChild(main);
  return row;
}

// Keterangan di ATAS daftar: "N produk di <Kategori>" (mode kategori) atau
// "Menampilkan X dari N produk — ketik nama barang untuk mencari" (semua
// produk tanpa query, mis. layout tanpa kategori). Mode pencarian tidak
// memakainya (info "Menampilkan X dari N" ada di ujung daftar, di atas
// tombol "Tampilkan lagi").
function updateListInfo(){
  var el = document.getElementById('listInfo');
  var total = _matches.length, txt = '';
  if (!_lastQ && total > 0) {
    var catName = (CATS_ON && selCat && selCat !== '*') ? selCat : '';
    var trunc = total > _renderedCount;
    if (catName) {
      txt = (trunc ? 'Menampilkan ' + fmtCount(_renderedCount) + ' dari ' + fmtCount(total) + ' produk di '
                   : fmtCount(total) + ' produk di ') + catName;
    } else if (trunc) {
      txt = 'Menampilkan ' + fmtCount(_renderedCount) + ' dari ' + fmtCount(total) +
            ' produk — ketik nama barang untuk mencari';
    }
  }
  el.textContent = txt;
  el.hidden = !txt;
}

// Tombol "Tampilkan lagi" di ujung daftar. Elemennya dipakai ulang (fokus
// tombol tidak hilang saat ditekan). Info "Menampilkan X dari N produk"
// di sini hanya utk hasil PENCARIAN (selain itu ada di updateListInfo).
function updateMoreBar(list){
  var total = _matches.length;
  if (total <= _renderedCount) {
    if (_moreBar && _moreBar.parentNode) _moreBar.parentNode.removeChild(_moreBar);
    return;
  }
  if (!_moreBar) {
    _moreBar = document.createElement('div');
    _moreBar.className = 'more-bar';
    _moreBar.innerHTML = '<div class="more-info" id="moreInfo"></div>' +
      '<button type="button" class="more-btn" id="moreBtn"></button>';
    _moreBar.querySelector('#moreBtn').addEventListener('click', function(){
      shownLimit += PAGE_SIZE;
      renderList();
    });
  }
  var remaining = total - _renderedCount;
  var step = Math.min(PAGE_SIZE, remaining);
  var info = _lastQ ? 'Menampilkan ' + fmtCount(_renderedCount) + ' dari ' + fmtCount(total) + ' produk' : '';
  var infoEl = _moreBar.querySelector('#moreInfo');
  infoEl.textContent = info;
  infoEl.hidden = !info;
  _moreBar.querySelector('#moreBtn').textContent = 'Tampilkan ' + fmtCount(step) + ' lagi' +
    (remaining > PAGE_SIZE ? ' (sisa ' + fmtCount(remaining) + ')' : '');
  if (list.lastChild !== _moreBar) list.appendChild(_moreBar); // selalu baris paling akhir
}

// Baris dibangun BERTAHAP: potongan pertama (cukup utk layar pertama) langsung,
// sisanya sepotong per frame. Membangun 60 baris sekaligus terukur ~300 ms
// satu frame di HP lambat (emoji + kartu berbayangan mahal di-raster) —
// itu yang bikin transisi landing <-> daftar & mengetik tersendat. Token
// membatalkan pengisian lama begitu render baru dimulai.
var ROWS_FIRST = 4;
var _fillToken = 0;
// Ukuran potongan menyesuaikan kecepatan perangkat (AIMD): frame sebelumnya
// cepat -> potongan digandakan (maks 20), lambat -> dibagi dua (min 2). HP
// lambat tetap tidak melewati ~1 frame panjang; perangkat cepat selesai
// dalam beberapa frame.
function fillRows(list, from, to, token){
  var i = from, size = ROWS_FIRST, last = 0;
  function step(now){
    if (token !== _fillToken) return;
    if (last) {
      var dt = now - last;
      if (dt > 34) size = Math.max(2, size >> 1);
      else if (dt < 21) size = Math.min(20, size * 2);
    }
    last = now || 0;
    var end = Math.min(to, i + size);
    var frag = document.createDocumentFragment();
    for (; i < end; i++) frag.appendChild(buildProductRow(_matches[i]));
    list.insertBefore(frag, (_moreBar && _moreBar.parentNode === list) ? _moreBar : null);
    if (i < to) requestAnimationFrame(step);
  }
  step(0);
}

// Kunci isi daftar: query (PENCARIAN SELALU GLOBAL — mengabaikan kategori
// terpilih) > kategori terpilih > semua produk.
function listKeyFor(q){
  if (q) return 'q:' + q;
  if (CATS_ON && selCat && selCat !== '*') return 'c:' + selCat;
  return 'all';
}

// force=true: bangun ulang baris yang sedang tampil walau query/limit tak
// berubah (perlu saat qty/keranjang berubah dari tempat lain, atau
// shopClosed berganti). Query/kategori berubah otomatis mereset limit +
// gulir ke atas. Saat LANDING daftar tidak tampil: tidak dibangun sama
// sekali (ditandai _stale, dibangun begitu pindah ke mode daftar).
function renderList(force){
  if (curView === 'landing') { _stale = true; return; }
  var q = document.getElementById('q').value.trim().toLowerCase();
  var key = listKeyFor(q);
  var list = document.getElementById('list');
  var scroller = document.getElementById('menuScroll');
  var qChanged = (key !== _lastKey) || _stale;
  _stale = false;
  if (!force && !qChanged && shownLimit === _renderedCount) return;
  if (!force && !qChanged && _renderedCount >= _matches.length) return;

  if (qChanged) {
    shownLimit = PAGE_SIZE;
    _matches = [];
    var cat = (!q && CATS_ON && selCat && selCat !== '*') ? selCat : null;
    for (var i = 0; i < DATA.products.length; i++) {
      if (q) { if (matchesQuery(i, q)) _matches.push(DATA.products[i]); }
      else if (cat) { if (DATA.products[i].category === cat) _matches.push(DATA.products[i]); }
      else _matches.push(DATA.products[i]);
    }
    _lastQ = q;
    _lastKey = key;
  }
  var target = Math.min(shownLimit, _matches.length);

  // Tambah baris saja (tombol "Tampilkan lagi") — tanpa bongkar ulang.
  if (!force && !qChanged && _renderedCount > 0 && target > _renderedCount) {
    var from = _renderedCount;
    // Tombol "Tampilkan lagi" TIDAK dicabut/dipindah (mencabut elemen yang
    // sedang fokus melepas fokusnya) — baris baru disisipkan di depannya.
    _renderedCount = target;
    updateMoreBar(list);
    updateListInfo();
    fillRows(list, from, target, ++_fillToken);
    return;
  }

  var keepScroll = scroller.scrollTop;
  var token = ++_fillToken;
  if (_moreBar && _moreBar.parentNode) _moreBar.parentNode.removeChild(_moreBar);
  list.innerHTML = '';
  _renderedCount = target;
  if (_matches.length === 0) {
    list.appendChild(notFoundNode(q));
  } else if (qChanged) {
    // Isi baru dari atas: bertahap (lihat fillRows).
    updateMoreBar(list);
    fillRows(list, 0, target, token);
  } else {
    // Render ulang paksa (mis. qty berubah) dgn posisi gulir dipertahankan:
    // harus utuh sekaligus supaya posisi gulir bisa dipulihkan.
    var frag = document.createDocumentFragment();
    for (var j = 0; j < target; j++) frag.appendChild(buildProductRow(_matches[j]));
    list.appendChild(frag);
    updateMoreBar(list);
  }
  updateListInfo();
  scroller.scrollTop = qChanged ? 0 : keepScroll;
}

// "+" selalu menambah SATUAN DASAR induk, walau produk punya varian — sama
// seperti _quickAdd() di app kasir (pilih varian lewat modal/tap badan).
function prowQuickAdd(p){
  setQty(p.unitId, (cart[p.unitId] || 0) + 1);
}
function prowDecrement(p){
  var cur = cart[p.unitId] || 0;
  if (cur <= 0) {
    showToast('Atur jumlah varian lewat keranjang');
    return;
  }
  setQty(p.unitId, cur - 1);
}
// Blueprint §4 — kontrol dibangun SEKALI per baris (tombol minus + pill
// "Tambah" selalu dua-duanya ada di DOM), lalu cuma di-mutate lewat
// syncProwControls(). Ini syarat mutlak supaya transisi CSS `width`
// ("pill memecah") punya nilai awal untuk dianimasikan — versi lama
// mengganti node tiap qty berubah, yang membuat setiap perubahan tampil
// sebagai lompatan instan, bukan transisi.
function buildProwControls(p){
  var wrap = document.createElement('div');
  wrap.className = 'prow-controls';
  var minus = document.createElement('button');
  minus.type = 'button';
  minus.className = 'pc-minus';
  minus.textContent = String.fromCharCode(8722);
  minus.setAttribute('aria-label', 'Kurangi ' + p.name);
  minus.addEventListener('click', function(){ prowDecrement(p); });
  var add = document.createElement('button');
  add.type = 'button';
  add.className = 'pc-add';
  add.setAttribute('aria-label', 'Tambah ' + p.name);
  add.innerHTML = '<span class="pc-label">Tambah</span><span class="pc-qty"></span>';
  add.addEventListener('click', function(){ prowQuickAdd(p); });
  wrap.appendChild(minus);
  wrap.appendChild(add);
  syncProwControls(wrap, p, false);
  return wrap;
}

// Update tampilan kontrol SATU baris tanpa mengganti node-nya.
// `animate` false saat render awal (supaya daftar tidak "meletup" semua
// sekaligus saat halaman dibuka), true saat qty benar-benar diubah user.
function syncProwControls(wrap, p, animate){
  var qty = totalQtyForProduct(p);
  var qtyEl = wrap.querySelector('.pc-qty');
  var label = fmtQty(qty);
  qtyEl.textContent = label;
  // Qty desimal (mis. "0.25", produk timbang) lebih panjang dari 1-2 digit
  // biasa — susutkan font proporsional supaya tetap muat di lingkaran 40px.
  qtyEl.style.fontSize = label.length > 2 ? (16 * (2 / label.length)) + 'px' : '';
  wrap.classList.toggle('selected', qty > 0);
  if (animate && qty > 0) {
    var wasFirst = qtyEl.classList.contains('badge-incr');
    qtyEl.classList.remove('badge-incr', 'badge-incr2');
    qtyEl.classList.add(wasFirst ? 'badge-incr2' : 'badge-incr');
  }
}

// Stepper inline +/- — sekarang hanya dipakai di lembar keranjang, di mana
// barisnya SELALU qty > 0 (barang qty 0 dihapus dari cart, bukan ditampilkan).
// ── Tombol kirim WhatsApp + Telegram. HAS_TG = toko mengisi kolom Telegram
// (DATA.telegramUrl, sudah dinormalisasi di sisi app). Tanpa Telegram: satu
// tombol WhatsApp seperti biasa. Dengan Telegram: halaman Pesanan menampilkan
// dua tombol 50/50, tiap tombol 2 baris (logo + teks / total).
var HAS_TG = !!(DATA.telegramUrl && typeof DATA.telegramUrl === 'string');
var _sendLabelShort = false;
if (HAS_TG) {
  document.getElementById('app').classList.add('has-tg');
  document.getElementById('mainBtnTg').hidden = false;
}
// Teks tombol: tunggal = "Kirim via WhatsApp" (seperti dulu); berdua = "Kirim ke
// WhatsApp"/"Kirim ke Telegram", dipendekkan jadi nama saja bila tak muat.
function setSendLabels(){
  var orderMode = document.getElementById('app').classList.contains('order-mode');
  var wa = document.getElementById('mbLabel');
  if (!orderMode) { wa.textContent = 'Lihat Pesanan'; return; }
  if (!HAS_TG) { wa.textContent = 'Kirim via WhatsApp'; return; }
  wa.textContent = _sendLabelShort ? 'WhatsApp' : 'Kirim ke WhatsApp';
  document.getElementById('mbLabelTg').textContent =
      _sendLabelShort ? 'Telegram' : 'Kirim ke Telegram';
}
var _measureCtx = null;
function textWidth(el, str){
  try {
    if (!_measureCtx) _measureCtx = document.createElement('canvas').getContext('2d');
    var cs = getComputedStyle(el);
    _measureCtx.font = cs.fontStyle + ' ' + cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily;
    return _measureCtx.measureText(str).width;
  } catch (e) { return 0; }
}
// Lebar tombol saat animasi melebar belum selesai tidak bisa diukur — hitung
// lebar TARGET (separuh baris) lalu cek apakah "logo + teks penuh" muat.
function fitSendLabels(){
  if (!HAS_TG) return;
  var app = document.getElementById('app');
  if (!app.classList.contains('order-mode')) return;
  var row = document.getElementById('mbRow');
  var btnW = (row.clientWidth - 8) / 2, avail = btnW - 16;
  if (!(avail > 0)) return;
  _sendLabelShort = false;
  setSendLabels();
  var full = Math.max(
      textWidth(document.getElementById('mbLabel'), 'Kirim ke WhatsApp'),
      textWidth(document.getElementById('mbLabelTg'), 'Kirim ke Telegram'));
  if (20 + 6 + full + 1 > avail) { _sendLabelShort = true; setSendLabels(); }
  var tot = rp(cartTotal());
  var tw = textWidth(document.getElementById('mbTotal'), tot);
  ['mbTotal', 'mbTotalTg'].forEach(function(id){
    document.getElementById(id).classList.toggle('tt', tw + 1 > avail);
  });
}
window.addEventListener('resize', fitSendLabels);
try { document.fonts.ready.then(fitSendLabels); } catch (e) {}

// Blueprint §5 — satu tombol aksi utama yang teks/warna/aksinya mengikuti
// konteks (browse vs ringkasan pesanan), dan SEMBUNYI total saat belum ada
// barang dipilih. Nominal total menyatu di dalam tombol yang sama.
function renderCartBar(){
  var n = cartCount();
  var orderMode = document.getElementById('app').classList.contains('order-mode');
  document.getElementById('mainBtnWrap').classList.toggle('hidden', n === 0 || shopClosed);
  if (n === 0) setClearConfirm(false);
  var mbBadge = document.getElementById('mbBadge');
  mbBadge.textContent = fmtQty(n);
  // Blueprint §4 — badge per-baris SELALU memantul saat qty berubah; badge di
  // tombol utama sebelumnya cuma ganti teks diam-diam, beda perilaku dari
  // baris. Retrigger animasi yang sama di sini, HANYA saat n benar-benar
  // berubah (bukan tiap renderCartBar() dipanggil, mis. buka/tutup ringkasan
  // pesanan tanpa ubah qty) — trik nama kelas berselang sama seperti
  // syncProwControls() supaya animasi restart walau nama kelas sebelumnya sama.
  if (n !== _mbBadgeCount) {
    var wasFirst = mbBadge.classList.contains('badge-incr');
    mbBadge.classList.remove('badge-incr', 'badge-incr2');
    mbBadge.classList.add(wasFirst ? 'badge-incr2' : 'badge-incr');
    _mbBadgeCount = n;
  }
  rollSet(document.getElementById('mbTotal'), rp(cartTotal()));
  if (HAS_TG) rollSet(document.getElementById('mbTotalTg'), rp(cartTotal()));
  var mainBtn = document.getElementById('mainBtn');
  if (_mbOrderMode !== null && _mbOrderMode !== orderMode) {
    // Susunan isi tombol berubah (tumpuk <-> satu baris): samarkan sesaat.
    mainBtn.classList.add('swapping');
    if (HAS_TG) document.getElementById('mainBtnTg').classList.add('swapping');
    setTimeout(function(){
      mainBtn.classList.remove('swapping');
      if (HAS_TG) document.getElementById('mainBtnTg').classList.remove('swapping');
    }, 60);
  }
  _mbOrderMode = orderMode;
  _sendLabelShort = false;
  setSendLabels();
  document.getElementById('mainBtn').classList.toggle('wa', orderMode);
  if (orderMode && HAS_TG) {
    mainBtn.setAttribute('aria-label', 'Kirim pesanan ke WhatsApp');
    fitSendLabels();
  } else {
    mainBtn.removeAttribute('aria-label');
  }
  document.getElementById('orderSub').textContent =
      n === 0 ? 'Belum ada barang dipilih' : fmtQty(n) + ' produk dipilih';
}

// ── Halaman Pesanan (Mockup B, struk). Baris dibangun SEKALI per unit lalu
// disinkronkan di tempat (bukan dibangun ulang tiap qty berubah) — syarat
// agar animasi "Tambah?" -> stepper, roll subtotal, dan hapus-menutup halus.
var cartRowEls = {};   // unitId -> elemen baris
var openRowId = null;  // baris yang stepper-nya sedang terbuka (maks. satu)
var openRowTimer = null;

function numOnly(n){ return rp(n).replace('Rp ', ''); }

function buildCartRow(id){
  var el = document.createElement('div');
  el.className = 'ln';
  el.dataset.id = id;
  el.innerHTML =
    '<div class="l1"><span class="q"></span><span class="nm"></span><span class="dots"></span>' +
      '<span class="s roll"></span></div>' +
    '<div class="l2"><span class="at"></span>' +
      '<div class="tbx"><button type="button" class="tb" data-act="open">Tambah?</button>' +
        '<div class="stp"><button type="button" data-act="dec" aria-label="Kurangi">&minus;</button>' +
        '<span class="qn"></span>' +
        '<button type="button" class="p" data-act="inc" aria-label="Tambah">+</button></div></div></div>' +
    '<div class="nn ci-note-view" style="display:none"></div>';
  return el;
}
function syncCartRow(id, el){
  var u = byUnit[id], qty = cart[id];
  el.querySelector('.q').textContent = fmtQty(qty) + '×';
  el.querySelector('.nm').textContent = u.name;
  rollSet(el.querySelector('.s'), numOnly(u.price * qty));
  el.querySelector('.at').textContent = '@ ' + rp(u.price) + ' /' + u.unit;
  el.querySelector('.qn').textContent = fmtQty(qty);
  var nn = el.querySelector('.nn');
  if (cartNotes[id]) { nn.style.display = ''; nn.textContent = '↳ ' + cartNotes[id]; }
  else { nn.style.display = 'none'; nn.textContent = ''; }
}
function removeCartRow(id){
  var el = cartRowEls[id];
  delete cartRowEls[id];
  if (!el) return;
  el.style.height = el.offsetHeight + 'px';
  void el.offsetHeight;
  el.classList.add('gone');
  el.style.height = '0px';
  setTimeout(function(){ if (el.parentNode) el.parentNode.removeChild(el); }, 280);
}
function setOpenRow(id){
  if (openRowId && cartRowEls[openRowId]) {
    cartRowEls[openRowId].querySelector('.tbx').classList.remove('open');
  }
  openRowId = id;
  clearTimeout(openRowTimer);
  if (id && cartRowEls[id]) {
    cartRowEls[id].querySelector('.tbx').classList.add('open');
    // Kembali ke "Tambah?" bila tidak disentuh beberapa detik.
    openRowTimer = setTimeout(function(){ setOpenRow(null); }, 4000);
  }
}

function renderCartSheet(){
  var wrap = document.getElementById('cartItems');
  var ids = Object.keys(cart).filter(function(id){ return byUnit[id]; });
  if (ids.length === 0) {
    Object.keys(cartRowEls).forEach(function(id){ delete cartRowEls[id]; });
    wrap.innerHTML = '<div class="empty">Keranjang kosong.</div>';
    setOpenRow(null);
    rollSet(document.getElementById('sheetTotal'), rp(0));
    return;
  }
  var emptyEl = wrap.querySelector('.empty');
  if (emptyEl) emptyEl.parentNode.removeChild(emptyEl);
  Object.keys(cartRowEls).forEach(function(id){
    if (!(id in cart)) { if (openRowId === id) setOpenRow(null); removeCartRow(id); }
  });
  ids.forEach(function(id){
    var el = cartRowEls[id];
    if (!el) { el = buildCartRow(id); cartRowEls[id] = el; wrap.appendChild(el); }
    syncCartRow(id, el);
  });
  rollSet(document.getElementById('sheetTotal'), rp(cartTotal()));
}

document.getElementById('cartItems').addEventListener('click', function(e){
  var row = e.target.closest('.ln');
  if (!row || row.classList.contains('gone')) return;
  var id = row.dataset.id;
  var btn = e.target.closest('button[data-act]');
  if (btn) {
    var act = btn.dataset.act;
    if (act === 'open') { setOpenRow(id); return; }
    var cur = cart[id] || 0;
    // Hapus langsung saat qty 1 -> 0 (baris menutup halus); selain itu timer
    // "kembali ke Tambah?" diulang tiap ketukan.
    setOpenRow(act === 'dec' && cur <= 1 ? null : id);
    setQty(id, act === 'inc' ? cur + 1 : cur - 1);
    return;
  }
  if (e.target.closest('.tbx')) return;
  // Ketuk nama/baris: buka modal produk (ubah satuan/catatan).
  var p = findProductForUnit(id);
  if (p) openItemModal(p, id);
});
// Ketuk di luar stepper -> kembali ke "Tambah?".
document.getElementById('pageOrder').addEventListener('click', function(e){
  if (openRowId && !e.target.closest('.tbx')) setOpenRow(null);
});

// ── Modal tap-item (Item 14) — pengganti dropdown varian lama: satu modal
// untuk semua produk (varian atau tidak), dipakai baik dari daftar maupun
// dari baris keranjang (utk ubah satuan/jumlah/catatan barang yg sudah
// dipilih). Harga MURNI tampilan (dari katalog, tidak bisa diketik ulang
// oleh pelanggan) — kasir tetap satu-satunya sumber harga final saat
// transaksi diproses (lihat komentar di kelas OrderPageService).
// ── Draf modal (qty & catatan) PERSISTEN di localStorage — bila halaman
// ter-refresh/modal ditutup tak sengaja, isian tidak hilang. Pola sama dgn
// cache keranjang di atas: dikunci DATA.generatedAt + kedaluwarsa 1 hari,
// semua akses dibungkus try/catch (mode privat/diblokir). Disimpan per
// satuan, hanya bila BEDA dari kondisi keranjang (tidak ada draf basi).
var DRAFT_KEY = 'posOrderItemDraft';
var _drafts = {};
function loadDrafts(){
  try {
    var raw = localStorage.getItem(DRAFT_KEY);
    if (!raw) return;
    var d = JSON.parse(raw);
    if (!d || d.generatedAt !== DATA.generatedAt) return;
    if (typeof d.savedAt !== 'number' || (Date.now() - d.savedAt) > CART_TTL_MS) return;
    _drafts = d.drafts || {};
  } catch (e) {}
}
function saveDrafts(){
  try {
    if (Object.keys(_drafts).length === 0) { localStorage.removeItem(DRAFT_KEY); return; }
    localStorage.setItem(DRAFT_KEY, JSON.stringify({
      generatedAt: DATA.generatedAt, savedAt: Date.now(), drafts: _drafts
    }));
  } catch (e) {}
}
function dropDraft(unitId){
  if (_drafts[unitId] !== undefined) { delete _drafts[unitId]; saveDrafts(); }
}
function noteDraft(){
  var uid = itemModalUnitId;
  if (!uid) return;
  var note = document.getElementById('itemNote').value;
  var baseQty = cart[uid] || 1;
  var baseNote = cartNotes[uid] || '';
  if (itemModalQty === baseQty && note.trim() === baseNote.trim()) {
    delete _drafts[uid];
  } else {
    _drafts[uid] = {qty: itemModalQty, note: note};
  }
  saveDrafts();
}
loadDrafts();

function openItemModal(p, preselectUnitId){
  itemModalProduct = p;
  document.getElementById('itemTitle').textContent = p.name;
  document.getElementById('itemEmoji').textContent = pickIcon(p.name, p.category);
  document.getElementById('itemCat').textContent = p.category || '';
  loadUnitIntoForm(p, preselectUnitId || p.unitId);
  document.getElementById('itemScrim').classList.add('show');
  document.getElementById('itemSheet').classList.add('show');
  document.documentElement.classList.add('modal-open');
}

function closeItemModal(){
  document.getElementById('itemScrim').classList.remove('show');
  document.getElementById('itemSheet').classList.remove('show');
  document.documentElement.classList.remove('modal-open');
  itemModalProduct = null;
  itemModalUnitId = null;
}

// Pilihan modal dipisah: VARIAN (entri induk "Biasa" + tiap varian) dan
// SATUAN (satuan milik entri terpilih). Satu unitId = satu pasangan (entri, satuan).
function entriesFor(p){
  var es = [{label:'Biasa', units:_ownUnits(p)}];
  (p.variants||[]).forEach(function(v){ es.push({label:v.name, units:_ownUnits(v)}); });
  return es;
}
function locateUnit(p, unitId){
  var es = entriesFor(p);
  for (var i=0;i<es.length;i++){
    for (var k=0;k<es[i].units.length;k++){
      if (es[i].units[k].unitId === unitId) return {entries:es, ei:i, ui:k};
    }
  }
  return {entries:es, ei:0, ui:0};
}
// Walk-through: tampil SETIAP modal dibuka selama pilihan melebihi lebar
// (perlu digeser); panah berdenyut lewat CSS. Pilihan terpilih digulirkan
// ke tengah supaya selalu terlihat. Satu petunjuk per baris.
function fillSeg(wrapId, boxId, hintId, items, selIdx, onPick){
  var wrap = document.getElementById(wrapId);
  var box = document.getElementById(boxId);
  var hint = document.getElementById(hintId);
  wrap.innerHTML = '';
  box.style.display = items.length <= 1 ? 'none' : 'block';
  var selEl = null;
  items.forEach(function(o, i){
    var chip = document.createElement('button');
    chip.type = 'button';
    chip.className = 'unit-chip' + (i === selIdx ? ' sel' : '');
    chip.innerHTML = esc(o.label) + '<small>' + rp(o.price) + '</small>';
    chip.addEventListener('click', function(){ onPick(i); });
    wrap.appendChild(chip);
    if (i === selIdx) selEl = chip;
  });
  requestAnimationFrame(function(){
    var over = wrap.scrollWidth > wrap.clientWidth + 2;
    hint.classList.toggle('show', items.length > 1 && over);
    if (selEl && over) wrap.scrollLeft = selEl.offsetLeft - (wrap.clientWidth - selEl.offsetWidth) / 2;
  });
}
function renderUnitChips(p, selectedUnitId){
  var loc = locateUnit(p, selectedUnitId);
  var cur = loc.entries[loc.ei];
  var curUnit = cur.units[loc.ui].unit;
  // Satuan: milik entri terpilih.
  fillSeg('itemUnitChips', 'itemSegWrap', 'itemSegHint',
    cur.units.map(function(u){ return {label:u.unit, price:u.price}; }), loc.ui,
    function(i){ loadUnitIntoForm(p, cur.units[i].unitId); });
  // Varian: pindah varian mempertahankan satuan yang sama bila ada.
  fillSeg('itemVarChips', 'itemVarWrap', 'itemVarHint',
    loc.entries.map(function(e){
      var m = e.units.filter(function(u){ return u.unit === curUnit; })[0] || e.units[0];
      return {label:e.label, price:m.price};
    }), loc.ei,
    function(i){
      var e = loc.entries[i];
      var m = e.units.filter(function(u){ return u.unit === curUnit; })[0] || e.units[0];
      loadUnitIntoForm(p, m.unitId);
    });
}

function loadUnitIntoForm(p, unitId){
  itemModalUnitId = unitId;
  renderUnitChips(p, unitId);
  rollSet(document.getElementById('itemPriceVal'), rp(byUnit[unitId].price));
  document.getElementById('itemPriceUnit').textContent = '/ ' + byUnit[unitId].unit;
  itemModalQty = cart[unitId] || 1;
  var draftNote = cartNotes[unitId] || '';
  var dr = _drafts[unitId];
  if (dr && typeof dr.qty === 'number') { itemModalQty = dr.qty; draftNote = dr.note || ''; }
  document.getElementById('itemQtyVal').value = fmtQty(itemModalQty);
  document.getElementById('itemNote').value = draftNote;
  document.getElementById('itemActions').classList.toggle('nodel', !cart[unitId]);
  updateItemSubtotal();
}

function updateItemSubtotal(){
  var price = itemModalUnitId ? byUnit[itemModalUnitId].price : 0;
  rollSet(document.getElementById('itemSubtotal'), rp(price * itemModalQty));
  document.getElementById('itemEq').textContent =
      itemModalUnitId ? fmtQty(itemModalQty) + ' × ' + rp(price) : '';
}

// Field jumlah bisa diketik LANGSUNG (mis. 2.5 kg), selain lewat tombol +/-.
document.getElementById('itemQtyVal').addEventListener('input', function(){
  var v = parseFloat(this.value);
  itemModalQty = (isNaN(v) || v < 0) ? 0 : v;
  updateItemSubtotal();
  noteDraft();
});
document.getElementById('itemNote').addEventListener('input', noteDraft);
document.getElementById('itemQtyDec').addEventListener('click', function(){
  itemModalQty = Math.max(0, itemModalQty - 1);
  document.getElementById('itemQtyVal').value = fmtQty(itemModalQty);
  updateItemSubtotal();
  noteDraft();
});
document.getElementById('itemQtyInc').addEventListener('click', function(){
  itemModalQty += 1;
  document.getElementById('itemQtyVal').value = fmtQty(itemModalQty);
  updateItemSubtotal();
  noteDraft();
});
document.getElementById('itemSheetClose').addEventListener('click', closeItemModal);
document.getElementById('itemScrim').addEventListener('click', closeItemModal);

// ── Geser ke bawah menutup modal (perilaku seperti keranjang di aplikasi
// kasir): modal IKUT BERGESER mengikuti jari saat isi sudah mentok di atas,
// menutup bila ditarik > 30% tinggi atau cukup cepat, selain itu kembali
// (snap-back). touchmove non-pasif + preventDefault supaya browser TIDAK
// ikut refresh (pull-to-refresh) / membekukan halaman.
// Dipakai bersama oleh modal produk & sheet riwayat pesanan.
function attachSheetSwipe(sheet, onClose){
  var body = sheet.querySelector('.sheet-body');
  var startY = 0, dy = 0, startT = 0, tracking = false, dragging = false;
  sheet.addEventListener('touchstart', function(e){
    if (!sheet.classList.contains('show') || e.touches.length !== 1) return;
    if (body.contains(e.target) && body.scrollTop > 0) return;
    startY = e.touches[0].clientY; startT = Date.now(); dy = 0;
    tracking = true; dragging = false;
  }, {passive: true});
  sheet.addEventListener('touchmove', function(e){
    if (!tracking) return;
    dy = e.touches[0].clientY - startY;
    if (!dragging) {
      if (dy > 6 && body.scrollTop <= 0) { dragging = true; sheet.style.transition = 'none'; }
      else if (dy < -6) { tracking = false; return; }
      else return;
    }
    if (e.cancelable) e.preventDefault();
    sheet.style.transform = 'translateY(' + Math.max(0, dy) + 'px)';
  }, {passive: false});
  function end(){
    if (!tracking) return;
    tracking = false;
    if (!dragging) return;
    dragging = false;
    var vel = dy / Math.max(1, Date.now() - startT);
    sheet.style.transition = '';
    var close = dy > sheet.offsetHeight * 0.3 || vel > 0.6;
    sheet.style.transform = '';
    if (close) onClose();
  }
  sheet.addEventListener('touchend', end);
  sheet.addEventListener('touchcancel', end);
}
attachSheetSwipe(document.getElementById('itemSheet'), function(){ closeItemModal(); });

document.getElementById('itemAddBtn').addEventListener('click', function(){
  if (!itemModalProduct || !itemModalUnitId) return;
  var unitId = itemModalUnitId;
  var note = document.getElementById('itemNote').value.trim();
  if (note) cartNotes[unitId] = note; else delete cartNotes[unitId];
  if (itemModalQty > 0) {
    cart[unitId] = itemModalQty;
  } else {
    delete cart[unitId];
    delete cartNotes[unitId];
  }
  dropDraft(unitId);
  closeItemModal();
  render();
  saveCart();
});
document.getElementById('itemRemoveBtn').addEventListener('click', function(){
  if (!itemModalUnitId) return;
  delete cart[itemModalUnitId];
  delete cartNotes[itemModalUnitId];
  dropDraft(itemModalUnitId);
  closeItemModal();
  render();
  saveCart();
});

function render(){ renderList(true); renderCartBar(); if (sheetOpen) renderCartSheet(); }

// ── Halaman awal (landing) / mode daftar ─────────────────────────────────
// Keadaan tampilan diturunkan dari: ada query? kategori terpilih? Pencarian
// SELALU global. Pindah keadaan = applyState(): layout berganti SEKALI
// (atribut data-view di #pageMenu), lalu elemen yang bergeser dianimasikan
// dgn teknik FLIP — hanya transform/opacity (tanpa animasi height/top/
// margin, tanpa layout thrash). Input pencarian TIDAK pernah dipindah dari
// DOM-nya, jadi fokus/kursor/keyboard HP aman saat transisi.
var CATS = (DATA.categories || []).filter(function(c){ return typeof c === 'string' && c; });
var CATS_ON = !!DATA.showCategories && CATS.length > 0;
var selCat = null;   // null = belum memilih (landing); '*' = Semua produk; selain itu nama kategori
var curView = null, curCatRow = false, curExtras = false;
function byId(id){ return document.getElementById(id); }
var qEl = byId('q'), pageMenu = byId('pageMenu'), menuScroll = byId('menuScroll');
var searchWrapEl = byId('searchWrap'), searchBoxEl = byId('searchBox');
var heroBlock = byId('heroBlock'), landingBelow = byId('landingBelow');
var catRowEl = byId('catRow'), catsHero = byId('catsHero');
var extrasSlotB = byId('extrasSlotB'), listWrapEl = byId('listWrap'), listEl2 = byId('list');
var tbId = byId('tbId'), menuTopEl = byId('menuTop');
var UI_EASE = 'cubic-bezier(.22,.61,.36,1)';
var UI_MS = 280;
function motionOk(){
  try {
    return typeof Element.prototype.animate === 'function' &&
      !window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  } catch (e) { return false; }
}

function computeState(){
  var q = qEl.value.trim();
  // Halaman awal (landing) SELALU ada; tanpa kategori isinya hanya satu chip
  // "Semua produk" untuk menjelajah — tidak langsung membuka seluruh daftar.
  var view = (q || selCat !== null) ? 'list' : 'landing';
  return {view: view, catRow: CATS_ON && view === 'list' && !q, extras: false};
}

// Salinan visual elemen yang akan HILANG (ghost): ditaruh absolut di posisi
// lamanya lalu di-fade-out, supaya elemen yang langsung di-display:none
// tidak lenyap mendadak. id dibuang agar tidak dobel di DOM.
function ghostOf(el, mode){
  var pr = pageMenu.getBoundingClientRect(), r = el.getBoundingClientRect();
  if (!r.width || !r.height) return null;
  var g;
  if (mode === 'list') {
    g = document.createElement('div');
    g.className = 'list' + (el.classList.contains('tile-mode') ? ' tile-mode' : '');
    for (var i = 0; i < el.children.length && i < 6; i++) g.appendChild(el.children[i].cloneNode(true));
  } else {
    g = el.cloneNode(true);
  }
  g.removeAttribute('id');
  Array.prototype.forEach.call(g.querySelectorAll('[id]'), function(n){ n.removeAttribute('id'); });
  g.classList.add('ghost');
  g.setAttribute('aria-hidden', 'true');
  g.style.display = (mode === 'list') ? 'block' : getComputedStyle(el).display;
  g.style.left = (r.left - pr.left) + 'px';
  g.style.top = (r.top - pr.top) + 'px';
  g.style.width = r.width + 'px';
  g.style.height = r.height + 'px';
  return g;
}
function flipY(el, oldTop){
  var dy = oldTop - el.getBoundingClientRect().top;
  if (Math.abs(dy) > 1) {
    el.animate([{transform: 'translateY(' + dy + 'px)'}, {transform: 'none'}],
      {duration: UI_MS, easing: UI_EASE});
  }
}
function enterAnim(el, dy, delay){
  el.animate([{opacity: 0, transform: 'translateY(' + dy + 'px)'}, {opacity: 1, transform: 'none'}],
    {duration: UI_MS, delay: delay || 0, easing: UI_EASE, fill: 'backwards'});
}

function applyState(st, animate){
  var oldView = curView, wasCatRow = curCatRow, wasExtras = curExtras;
  if (oldView === st.view && wasCatRow === st.catRow && wasExtras === st.extras) return;
  var anim = animate && oldView !== null && !sheetOpen && motionOk();
  var ghosts = [], first = null;
  if (anim) {
    first = {search: searchWrapEl.getBoundingClientRect().top,
             list: listWrapEl.getBoundingClientRect().top};
    if (oldView === 'landing' && st.view === 'list') {
      ghosts.push(ghostOf(heroBlock)); ghosts.push(ghostOf(landingBelow));
    } else if (oldView === 'list' && st.view === 'landing') {
      ghosts.push(ghostOf(listEl2, 'list'));
      if (wasCatRow) ghosts.push(ghostOf(catRowEl));
    } else if (wasCatRow && !st.catRow) {
      ghosts.push(ghostOf(catRowEl));
    }
    if (wasExtras && !st.extras) ghosts.push(ghostOf(extrasSlotB));
  }
  pageMenu.setAttribute('data-view', st.view);
  pageMenu.setAttribute('data-catrow', st.catRow ? '1' : '0');
  pageMenu.setAttribute('data-extras', st.extras ? '1' : '0');
  curView = st.view; curCatRow = st.catRow; curExtras = st.extras;
  if (oldView !== st.view) menuScroll.scrollTop = 0;
  // Ke landing: kosongkan baris daftar (ghost sudah menyalin yg terlihat).
  // Baris basi yang disembunyikan akan di-layout ULANG saat mode daftar
  // tampil lagi (ratusan objek, ~puluhan ms di HP lambat) sebelum sempat
  // diganti isi baru.
  if (st.view === 'landing' && oldView !== 'landing') clearListDom();
  if (oldView !== null) renderList(); // render awal dilakukan init (render())
  syncTbId();
  if (oldView === 'landing' && st.view === 'list') pushListState();
  else if (oldView === 'list' && st.view === 'landing') popListState();
  if (!anim) return;

  flipY(searchWrapEl, first.search);
  if (oldView === 'list' && st.view === 'list') flipY(listWrapEl, first.list);
  if (oldView === 'landing' && st.view === 'list') {
    enterAnim(listWrapEl, 14, 40);
    if (st.catRow) enterAnim(catRowEl, 8, 20);
  } else if (oldView === 'list' && st.view === 'landing') {
    enterAnim(heroBlock, 12, 40);
    enterAnim(landingBelow, 14, 80);
  } else {
    if (st.catRow && !wasCatRow) enterAnim(catRowEl, 8, 0);
    if (st.extras && !wasExtras) enterAnim(extrasSlotB, 8, 0);
  }
  ghosts.forEach(function(g){
    if (!g) return;
    pageMenu.appendChild(g);
    var kill = function(){ if (g.parentNode) g.parentNode.removeChild(g); };
    g.animate([{opacity: 1, transform: 'none'}, {opacity: 0, transform: 'translateY(-8px)'}],
      {duration: 200, easing: 'ease-out', fill: 'forwards'}).onfinish = kill;
    setTimeout(kill, 600);
  });
}

function clearListDom(){
  _fillToken++;
  if (_moreBar && _moreBar.parentNode) _moreBar.parentNode.removeChild(_moreBar);
  listEl2.innerHTML = '';
  _renderedCount = 0;
  _matches = [];
  _lastKey = null;
  _lastQ = null;
  byId('listInfo').hidden = true;
}
function syncTbId(){
  var link = curView === 'list';
  tbId.classList.toggle('clickable', link);
  if (link) tbId.setAttribute('aria-label', 'Kembali ke halaman awal');
  else tbId.removeAttribute('aria-label');
}
tbId.addEventListener('click', function(){ if (curView === 'list') goLanding(); });

function goLanding(noAnim){
  selCat = null;
  setSelChips();
  qEl.value = '';
  clearTimeout(searchTimer);
  syncQueryUi();
  applyState(computeState(), !noAnim);
}

// Riwayat browser: masuk mode daftar dari landing memakai satu entri
// history, jadi tombol Kembali HP kembali ke landing (bukan keluar dari
// katalog). _popIgnore menelan popstate yg dipicu history.back() buatan sendiri.
var _listPushed = false, _popIgnore = 0;
function pushListState(){
  if (_listPushed) return;
  try { history.pushState({posList: 1}, ''); _listPushed = true; } catch (e) {}
}
function popListState(){
  if (!_listPushed) return;
  _listPushed = false;
  _popIgnore++;
  try { history.back(); } catch (e) { _popIgnore--; }
}

// ── Chip kategori. Dibangun SEKALI (dua set: di landing & di baris sticky);
// pilihan hanya mengganti class (fokus keyboard tidak hilang).
function buildChips(){
  function mk(label, val, cls){
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'cat-chip' + (cls ? ' ' + cls : '');
    b.textContent = label;
    b.dataset.cat = val;
    b.addEventListener('click', function(){ selectCat(val); });
    return b;
  }
  catsHero.appendChild(mk('Semua produk', '*', 'all'));
  if (!CATS_ON) return;   // kategori dimatikan: landing hanya punya chip "Semua produk"
  CATS.forEach(function(c){ catsHero.appendChild(mk(c, c)); });
  catRowEl.appendChild(mk('Semua produk', '*'));
  CATS.forEach(function(c){ catRowEl.appendChild(mk(c, c)); });
}
function setSelChips(){
  Array.prototype.forEach.call(catRowEl.children, function(b){
    var on = selCat !== null && b.dataset.cat === selCat;
    b.classList.toggle('sel', on);
    b.setAttribute('aria-pressed', on ? 'true' : 'false');
  });
}
function centerChip(val){
  requestAnimationFrame(function(){
    Array.prototype.forEach.call(catRowEl.children, function(b){
      if (b.dataset.cat === val) {
        catRowEl.scrollLeft = b.offsetLeft - (catRowEl.clientWidth - b.offsetWidth) / 2;
      }
    });
  });
}
function selectCat(val){
  if (selCat === val && curView === 'list') return;
  var wasList = curView === 'list';
  selCat = val;
  setSelChips();
  clearTimeout(searchTimer);
  applyState(computeState(), true);   // landing -> daftar: daftar dibangun di dalam
  if (wasList) {
    renderList();
    if (motionOk()) listWrapEl.animate([{opacity: .3}, {opacity: 1}], {duration: 200, easing: 'ease-out'});
  }
  centerChip(val);
}

// ── Kolom cari: placeholder saran terlaris bergantian ("Cari <b>Nama</b>").
// Berhenti saat field fokus/terisi/tab tersembunyi; tanpa animasi bila
// prefers-reduced-motion (teks langsung diganti). Tombol panah mengisi kolom
// dgn saran yang SEDANG tampil lalu mencari (pencarian global biasa).
var SUG = (DATA.topSellers || []).filter(function(s){ return typeof s === 'string' && s.trim(); });
var sugIdx = 0, phTimer = null;
var phLayer = byId('phLayer'), phCur = byId('phA'), phNext = byId('phB'), goBtn = byId('goBtn');
// Format: "Cari <b>Nama</b>? Tekan →" — memberi tahu pelanggan bahwa tombol
// panah di kanan (atau Enter) langsung mencari saran itu.
var ARROW_SVG = '<svg class="ph-arr" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14"/><path d="M13 6l6 6-6 6"/></svg>';
function setPh(el, name){
  el.textContent = '';
  var i = document.createElement('i');
  var a = document.createElement('em');
  a.textContent = 'Cari ';
  var b = document.createElement('b');
  b.textContent = name;
  var c = document.createElement('em');
  c.textContent = '? Tekan';
  var arr = document.createElement('em');
  arr.innerHTML = ARROW_SVG;
  i.appendChild(a); i.appendChild(b); i.appendChild(c); i.appendChild(arr);
  el.appendChild(i);
}
function syncQueryUi(){
  var has = qEl.value.length > 0;
  searchBoxEl.classList.toggle('has-text', has);
  phLayer.classList.toggle('off', has || !SUG.length);
  goBtn.hidden = !has && !SUG.length;
  goBtn.setAttribute('aria-label',
    has ? 'Hapus pencarian' : (SUG.length ? 'Cari ' + SUG[sugIdx] : 'Cari'));
}
function phCanRun(){
  // Tetap berjalan saat kolom fokus (kursor di dalam): Enter tetap mencari
  // saran yang tampil. Berhenti begitu ada satu huruf diketik.
  return SUG.length > 1 && !document.hidden && !qEl.value && !sheetOpen;
}
function phStep(){
  var next = (sugIdx + 1) % SUG.length;
  if (!motionOk()) {
    setPh(phCur, SUG[next]);
  } else {
    setPh(phNext, SUG[next]);
    phNext.className = 'noanim down';
    void phNext.offsetWidth;
    phNext.className = 'cur';
    phCur.className = 'up';
    var t = phCur; phCur = phNext; phNext = t;
  }
  sugIdx = next;
  syncQueryUi();
}
function phLoop(){
  clearTimeout(phTimer);
  phTimer = setTimeout(function(){ if (phCanRun()) phStep(); phLoop(); }, 2800);
}
function initPlaceholder(){
  if (SUG.length) {
    qEl.placeholder = '';
    setPh(phCur, SUG[0]);
    phLoop();
  }
  syncQueryUi();
}
function fillSuggestion(){
  if (!SUG.length) return;
  qEl.value = SUG[sugIdx];
  syncQueryUi();
  immediateSearch();
  qEl.blur();
}
// Landing + keyboard terbuka: kolom cari bisa tertutup keyboard / tombol
// keranjang di bawah. Gulir halaman secukupnya (kolom cari menempel di bawah
// header lewat sticky) supaya kolom cari TERLIHAT. Tidak melakukan apa pun
// bila sudah terlihat penuh.
var _revealTimer = null;
function revealSearch(delay){
  clearTimeout(_revealTimer);
  _revealTimer = setTimeout(function(){
    if (curView !== 'landing' || document.activeElement !== qEl) return;
    var r = searchWrapEl.getBoundingClientRect();
    var top = menuTopEl.getBoundingClientRect().bottom;
    var wrap = byId('mainBtnWrap');
    var lim = window.innerHeight;
    if (window.visualViewport) lim = Math.min(lim, visualViewport.offsetTop + visualViewport.height);
    if (!wrap.classList.contains('hidden') && wrap.offsetHeight) lim = Math.min(lim, wrap.getBoundingClientRect().top);
    if (r.top >= top && r.bottom <= lim - 8) return;
    var d = r.top - top - 8;
    if (d > 0) menuScroll.scrollTo({top: menuScroll.scrollTop + d, behavior: motionOk() ? 'smooth' : 'auto'});
  }, delay);
}
qEl.addEventListener('focus', function(){ revealSearch(380); });
if (window.visualViewport) visualViewport.addEventListener('resize', function(){ revealSearch(120); });
function immediateSearch(){
  clearTimeout(searchTimer);
  applyState(computeState(), true);
  renderList();
}

// Debounce ~120ms — tiap huruf diketik memicu renderList(); tanpa debounce
// ini kerja berulang di setiap huruf, dampaknya terbesar di HP low-end.
// Pengecualian: huruf PERTAMA / terakhir-dihapus (keadaan tampilan berganti,
// mis. landing <-> hasil) diproses langsung supaya transisinya responsif.
var searchTimer = null;
qEl.addEventListener('input', function(){
  syncQueryUi();
  clearTimeout(searchTimer);
  var st = computeState();
  if (st.view !== curView || st.catRow !== curCatRow || st.extras !== curExtras) {
    applyState(st, true);
    if (st.view === 'landing') revealSearch(400);   // hapus huruf terakhir -> landing
    return;
  }
  searchTimer = setTimeout(function(){ renderList(); }, 120);
});
qEl.addEventListener('keydown', function(e){
  if (e.key !== 'Enter') return;
  e.preventDefault();
  if (!qEl.value.trim() && SUG.length) { fillSuggestion(); return; }
  immediateSearch();
  qEl.blur();
});
// Tombol (panah/X) tidak boleh mencuri fokus: kursor tetap di kolom cari &
// keyboard HP tetap terbuka (pelanggan tak perlu mengetuk kolom lagi).
['mousedown', 'pointerdown'].forEach(function(ev){
  goBtn.addEventListener(ev, function(e){ if (document.activeElement === qEl) e.preventDefault(); });
});
goBtn.addEventListener('click', function(){
  if (qEl.value.length > 0) {
    qEl.value = '';
    syncQueryUi();
    immediateSearch();
    qEl.focus();
    revealSearch(400);
  } else {
    fillSuggestion();
  }
});

// ── Stiker animasi (Lottie). JSON per slot tersemat di <script type=
// application/json id="stk-<slot>"> (hanya bila ada stiker; pustaka lottie ikut
// tersemat hanya saat itu). Animasi baru dibuat saat kotaknya TERLIHAT (idle),
// dijeda saat keluar layar / tab disembunyikan, dan jadi gambar diam bila
// pengguna memilih mengurangi gerakan. Gagal di langkah mana pun = kotak
// disembunyikan, halaman tetap normal.
var STK_EL = [];
function stkJson(slot){
  if (!window.lottie) return null;
  var key = '_' + slot;
  if (stkJson[key] !== undefined) return stkJson[key];
  var node = document.getElementById('stk-' + slot), v = null;
  if (node) { try { v = JSON.parse(node.textContent); } catch (e) {} }
  return (stkJson[key] = v);
}
var stkIO = null;
function stkApply(el){
  var a = el._anim;
  if (!a) return;
  try {
    if (!motionOk()) a.goToAndStop(Math.floor(a.totalFrames / 2), true);
    else if (el._vis && !document.hidden) a.play();
    else a.pause();
  } catch (e) {}
}
function stkCreate(el){
  if (el._anim || el._dead) return;
  try {
    el._anim = lottie.loadAnimation({container: el, renderer: 'svg', loop: true, autoplay: false,
      animationData: stkJson(el.getAttribute('data-stk')),
      rendererSettings: {preserveAspectRatio: 'xMidYMid meet'}});
  } catch (e) { el._dead = true; el.hidden = true; return; }
  stkApply(el);
}
function stkSeen(el, vis){
  el._vis = vis;
  if (vis && !el._anim) {
    var go = function(){ if (el._vis) stkCreate(el); };
    if (window.requestIdleCallback) requestIdleCallback(go, {timeout: 400}); else setTimeout(go, 60);
  } else stkApply(el);
}
function stkMount(el){
  if (el._stk) return;
  if (!stkJson(el.getAttribute('data-stk'))) { el.hidden = true; return; }
  el._stk = true;
  el.hidden = false;
  STK_EL.push(el);
  if ('IntersectionObserver' in window) {
    if (!stkIO) stkIO = new IntersectionObserver(function(es){
      es.forEach(function(e){ stkSeen(e.target, e.isIntersecting); });
    });
    stkIO.observe(el);
  } else stkSeen(el, true);
}
document.addEventListener('visibilitychange', function(){ STK_EL.forEach(stkApply); });

// Halaman "Produk tidak ditemukan": satu node dipakai ulang (animasinya tidak
// dibuat ulang tiap ketikan); hanya teks yang berganti.
var _nfEl = null, _nfP = null;
function notFoundNode(q){
  if (!_nfEl) {
    _nfEl = document.createElement('div');
    _nfEl.className = 'nf';
    var st = document.createElement('div');
    st.className = 'stk';
    st.setAttribute('data-stk', 'notFound');
    st.hidden = true;
    _nfP = document.createElement('p');
    _nfEl.appendChild(st);
    _nfEl.appendChild(_nfP);
    stkMount(st);
  }
  _nfP.textContent = q ? 'Produk "' + q + '" tidak ditemukan' : 'Belum ada produk di sini';
  return _nfEl;
}

// ── Status header (buka/tutup + jam) ──────────────────────────────────
function renderStatus(){
  var el = byId('storeSub'), h = DATA.hours, st = hoursState(), text, closed = false, warn = false;
  if (h && (h.forced || h.enabled)) {
    if (st.closed && !accessGranted) { closed = true; text = st.msg; }
    else if (st.closed) { warn = true; text = 'Pesan titipan · toko tutup'; }
    else text = (h.enabled && h.open !== h.close) ? 'Buka · sampai ' + fmtHHMM(h.close) : 'Buka';
  } else {
    text = null;
  }
  // Tanpa jam buka: baris 1 = "Katalog pesanan", baris 2 = "Diperbarui <waktu>"
  // (waktu tak terputus di tengah). Dengan jam buka: satu teks, boleh membungkus.
  var upd = null;
  if (text === null) { text = 'Katalog pesanan'; upd = DATA.generatedAt; }
  var key = (closed ? '1' : warn ? '2' : '0') + text + '|' + (upd || '');
  if (el._k === key) return;
  el._k = key;
  el.textContent = '';
  var dot = document.createElement('i');
  dot.className = 'st-dot' + (closed ? ' closed' : warn ? ' warn' : '');
  var sp = document.createElement('span');
  sp.className = 'st-txt';
  sp.appendChild(document.createTextNode(text));
  if (upd) {
    var u = document.createElement('span');
    u.className = 'st-upd';
    u.appendChild(document.createTextNode('Diperbarui '));
    var nb = document.createElement('span');
    nb.className = 'nb';
    nb.textContent = upd;
    u.appendChild(nb);
    sp.appendChild(u);
  }
  el.appendChild(dot);
  el.appendChild(sp);
}

// ── Pengumuman toko (teks dari owner => SELALU textContent, bukan innerHTML).
// Otomatis muncul SEKALI tiap halaman dibuka (lama = clamp(3000 + 60ms x
// huruf, 3000, 12000)), menciut ke tombol bila discroll / ketuk di luar;
// diketuk manual = tanpa batas waktu sampai scroll/ketuk di luar/ketuk lagi.
var ANN = (function(){
  var a = DATA.announcement;
  if (!a || a.enabled === false || typeof a.text !== 'string') return null;
  var t = a.text.trim();
  return t ? t : null;
})();
var annBtn = byId('annBtn'), annPop = byId('annPop'), annProg = byId('annProg');
var annOpen = false, annTimer = null, annAutoShown = false, annScrollBase = 0;
function annAutoMs(){ return Math.min(12000, Math.max(3000, 3000 + 60 * ANN.length)); }
function openAnn(auto){
  if (!ANN || annOpen) return;
  annPop.style.top = (menuTopEl.offsetTop + menuTopEl.offsetHeight + 6) + 'px';
  var br = annBtn.getBoundingClientRect(), pr = pageMenu.getBoundingClientRect();
  var ax = (br.left + br.width / 2) - pr.left - annPop.offsetLeft;
  ax = Math.max(18, Math.min(annPop.offsetWidth - 18, ax));
  annPop.style.setProperty('--ax', ax + 'px');
  annPop.classList.toggle('manual', !auto);
  annOpen = true;
  annScrollBase = menuScroll.scrollTop;
  annBtn.setAttribute('aria-expanded', 'true');
  annBtn.classList.add('seen');
  clearTimeout(annTimer);
  if (auto) {
    var ms = annAutoMs();
    annProg.style.transition = 'none';
    annProg.style.transform = 'scaleX(1)';
    void annProg.offsetWidth;
    annProg.style.transition = 'transform ' + ms + 'ms linear';
    annProg.style.transform = 'scaleX(0)';
    annTimer = setTimeout(closeAnn, ms);
  }
  annPop.classList.add('show');
}
function closeAnn(){
  clearTimeout(annTimer);
  annTimer = null;
  if (!annOpen) return;
  annOpen = false;
  annPop.classList.remove('show');
  annBtn.setAttribute('aria-expanded', 'false');
}
function initAnn(){
  if (!ANN) { annBtn.hidden = true; return; }
  annBtn.hidden = false;
  byId('annText').textContent = ANN;
  annBtn.addEventListener('click', function(){ if (annOpen) closeAnn(); else openAnn(false); });
  menuScroll.addEventListener('scroll', function(){
    if (annOpen && Math.abs(menuScroll.scrollTop - annScrollBase) > 8) closeAnn();
  }, {passive: true});
  var ty = 0;
  pageMenu.addEventListener('touchstart', function(e){ if (e.touches.length) ty = e.touches[0].clientY; }, {passive: true});
  pageMenu.addEventListener('touchmove', function(e){
    if (annOpen && e.touches.length && Math.abs(e.touches[0].clientY - ty) > 12) closeAnn();
  }, {passive: true});
  pageMenu.addEventListener('wheel', function(e){ if (annOpen && Math.abs(e.deltaY) > 4) closeAnn(); }, {passive: true});
  document.addEventListener('pointerdown', function(e){
    if (annOpen && !annPop.contains(e.target) && !annBtn.contains(e.target)) closeAnn();
  }, true);
  // Sekali per halaman dibuka — bukan tiap perubahan keadaan.
  setTimeout(function(){
    if (annAutoShown || sheetOpen || shopClosed) return;
    annAutoShown = true;
    openAnn(true);
  }, 450);
}

// ── Pesan lagi: riwayat pesanan di localStorage HP pelanggan sendiri (kunci
// TIDAK memuat generatedAt, jadi bertahan lintas Publish; SEMUA pesanan
// disimpan, tanpa batas jumlah). Semua akses try/catch. Harga SELALU dari
// katalog terkini — yang disimpan hanya unitId, qty, nama tampil, catatan.
var HIST_KEY = 'posOrderHistory';
var DUP_WINDOW_MS = 120000;
var MONTHS_ID = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Ags','Sep','Okt','Nov','Des'];
function loadHistory(){
  var out = [];
  try {
    var raw = localStorage.getItem(HIST_KEY);
    if (!raw) return out;
    var arr = JSON.parse(raw);
    if (!Array.isArray(arr)) return out;
    arr.forEach(function(o){
      if (!o || typeof o.t !== 'number' || !Array.isArray(o.items)) return;
      var items = o.items.filter(function(it){ return it && typeof it.id === 'string' && it.q > 0; });
      if (items.length) out.push({t: o.t, items: items});
    });
  } catch (e) {}
  out.sort(function(a, b){ return b.t - a.t; });
  return out;
}
function requestPersist(){
  try {
    if (navigator.storage && navigator.storage.persist) {
      var r = navigator.storage.persist();
      if (r && r.catch) r.catch(function(){});
    }
  } catch (e) {}
}
function orderSig(items){
  return items.map(function(it){ return it.id + ':' + it.q + ':' + (it.note || ''); }).sort().join('|');
}
// Dipanggil tiap pelanggan menekan kirim. Isi identik < 2 menit dari
// pesanan terakhir (dobel-ketuk) diabaikan.
function recordOrder(){
  if (!DATA.reorder) return;
  var items = [];
  Object.keys(cart).forEach(function(id){
    var u = byUnit[id];
    if (!u || !(cart[id] > 0)) return;
    var it = {id: id, q: cart[id], n: u.name};
    var note = (cartNotes[id] || '').trim();
    if (note) it.note = note;
    items.push(it);
  });
  if (!items.length) return;
  var list = loadHistory();
  var now = Date.now();
  if (list.length && now - list[0].t < DUP_WINDOW_MS && orderSig(list[0].items) === orderSig(items)) return;
  list.unshift({t: now, items: items});
  try { localStorage.setItem(HIST_KEY, JSON.stringify(list)); } catch (e) { return; }
  requestPersist();
  renderExtras();
}
function p2(n){ return (n < 10 ? '0' : '') + n; }
function fmtOrderDate(t, withYear, withTime){
  var d = new Date(t);
  return d.getDate() + ' ' + MONTHS_ID[d.getMonth()] + (withYear ? ' ' + d.getFullYear() : '') +
    (withTime ? ' · ' + p2(d.getHours()) + '.' + p2(d.getMinutes()) : '');
}
function summarizeItems(items, withQty){
  var parts = items.slice(0, 3).map(function(it){ return it.n + (withQty ? ' ×' + fmtQty(it.q) : ''); });
  if (items.length > 3) parts.push('+' + (items.length - 3) + ' lagi');
  return parts.join(', ');
}
var extrasEl = byId('extras');
function renderExtras(){
  var on = !!DATA.reorder;
  extrasEl.hidden = !on;
  if (!on) return;
  var list = loadHistory();
  byId('againWrap').hidden = list.length === 0;
  byId('noHist').hidden = list.length > 0;
  if (list.length) {
    var o = list[0];
    byId('againTitle').textContent = fmtOrderDate(o.t, false, false) + ' · ' + o.items.length + ' jenis barang';
    byId('againSub').textContent = summarizeItems(o.items, false);
    byId('histN').textContent = String(list.length);
  }
}
// Masukkan item ke keranjang: qty = qty tersimpan (item lain tidak disentuh),
// lewati unitId yg tak ada di katalog sekarang / produk habis.
function applyOrderItems(items){
  var added = 0, missing = [];
  items.forEach(function(it){
    var u = byUnit[it.id], p = u ? findProductForUnit(it.id) : null;
    if (!u || !p || p.outOfStock) { missing.push(it.n || (u && u.name) || 'barang'); return; }
    cart[it.id] = it.q;
    dropDraft(it.id);
    if (it.note) cartNotes[it.id] = it.note;
    added++;
  });
  if (added) { render(); saveCart(); }
  return {added: added, missing: missing};
}
function reorderMessage(res){
  if (!res.added) {
    return {text: res.missing.length ? 'Barang di pesanan ini sudah tidak tersedia' : 'Tidak ada barang untuk dimasukkan', err: true};
  }
  var t = res.added + ' barang dimasukkan';
  if (res.missing.length) {
    t += ' · ' + res.missing.length + ' tidak tersedia lagi (' +
      res.missing.slice(0, 2).join(', ') + (res.missing.length > 2 ? ', dll' : '') + ')';
  }
  return {text: t, err: false};
}
function reorderFrom(items, inSheet){
  try {
    var res = applyOrderItems(items), m = reorderMessage(res);
    showToast(m.text, {ms: 4500, error: m.err});
    if (inSheet) byId('histMsg').textContent = (m.err ? '' : '✓ ') + m.text;
  } catch (e) { showToast('Gagal memasukkan pesanan', {error: true}); }
}
byId('againBtn').addEventListener('click', function(){
  var list = loadHistory();
  if (list.length) reorderFrom(list[0].items, false);
});
function renderHistSheet(){
  var list = loadHistory(), box = byId('histList');
  byId('histCount').textContent = '(' + list.length + ')';
  box.textContent = '';
  list.forEach(function(o, idx){
    var row = document.createElement('div');
    row.className = 'hist-it';
    var tx = document.createElement('div');
    tx.className = 'hi-t';
    var t = document.createElement('div');
    t.className = 't';
    t.textContent = fmtOrderDate(o.t, true, true);
    var s = document.createElement('div');
    s.className = 's';
    s.textContent = summarizeItems(o.items, true);
    tx.appendChild(t);
    tx.appendChild(s);
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'btn' + (idx === 0 ? '' : ' o');
    b.textContent = 'Pesan lagi';
    b.addEventListener('click', function(){ reorderFrom(o.items, true); });
    row.appendChild(tx);
    row.appendChild(b);
    box.appendChild(row);
  });
}
function openHist(){
  renderHistSheet();
  byId('histMsg').textContent = '';
  byId('histScrim').classList.add('show');
  byId('histSheet').classList.add('show');
  document.documentElement.classList.add('modal-open');
}
function closeHist(){
  byId('histScrim').classList.remove('show');
  byId('histSheet').classList.remove('show');
  document.documentElement.classList.remove('modal-open');
}
byId('histOpen').addEventListener('click', openHist);
byId('histClose').addEventListener('click', closeHist);
byId('histScrim').addEventListener('click', closeHist);
attachSheetSwipe(byId('histSheet'), closeHist);

// Pemulihan: tempel teks WhatsApp -> ambil kode `#PSN:` / `PSN:` (teks lain
// diabaikan), format `unitId=qty[:catatanEncoded];...`. Tidak boleh melempar.
function parsePsn(text){
  var items = [], re = /#?PSN:(\S+)/gi, m;
  var src = String(text == null ? '' : text);
  while ((m = re.exec(src)) !== null) {
    m[1].split(';').forEach(function(part){
      var eq = part.indexOf('=');
      if (eq <= 0) return;
      var id = part.slice(0, eq), rest = part.slice(eq + 1), ci = rest.indexOf(':');
      var q = parseFloat(ci >= 0 ? rest.slice(0, ci) : rest);
      if (!id || !(q > 0) || !isFinite(q)) return;
      var it = {id: id, q: q};
      if (ci >= 0) {
        var raw = rest.slice(ci + 1), note = raw;
        try { note = decodeURIComponent(raw); } catch (e) { note = raw; }
        note = note.trim();
        if (note) it.note = note;
      }
      items.push(it);
    });
  }
  return items;
}
function loadPasted(){
  var msg = byId('pasteMsg');
  try {
    var items = parsePsn(byId('pasteIn').value);
    if (!items.length) { msg.textContent = 'Kode pesanan tidak ditemukan di teks ini'; return; }
    msg.textContent = '';
    var res = applyOrderItems(items), m = reorderMessage(res);
    showToast(m.text, {ms: 4500, error: m.err});
    if (res.added) byId('pasteIn').value = '';
    else msg.textContent = m.text;
  } catch (e) {
    msg.textContent = 'Kode pesanan tidak ditemukan di teks ini';
  }
}
byId('pasteBtn').addEventListener('click', loadPasted);
byId('pasteIn').addEventListener('keydown', function(e){ if (e.key === 'Enter') { e.preventDefault(); loadPasted(); } });
byId('pasteIn').addEventListener('input', function(){ byId('pasteMsg').textContent = ''; });
// Slot "Pesan lagi": di landing (bawah chip) atau, tanpa kategori, di bawah kolom cari.
byId('extrasSlotL').appendChild(extrasEl);


// Blueprint §2/§6 — pindah mode, BUKAN pindah halaman: tidak ada reload,
// tidak ada history baru, kedua section tetap hidup di DOM. `sheetOpen`
// dipertahankan namanya sbg penanda "ringkasan pesanan sedang terlihat",
// dipakai render() utk melewati kerja render keranjang saat tidak tampil.
// Tombol Kembali HP harus menutup ringkasan dulu, BUKAN langsung keluar
// dari katalog — begitu tampilannya terasa seperti dua halaman, keluar
// total saat menekan Kembali terasa seperti kehilangan pesanan. Satu entri
// history didorong saat masuk mode pesanan lalu dikonsumsi saat keluar,
// jadi tidak pernah menumpuk berapa kali pun pelanggan bolak-balik.
var _histPushed = false;
function openSheet(){
  setClearConfirm(false);
  sheetOpen = true;
  renderCartSheet();
  document.getElementById('app').classList.add('order-mode');
  renderCartBar();
  document.getElementById('pageOrder').scrollTop = 0;
  if (!_histPushed) {
    try { history.pushState({posOrder:1}, ''); _histPushed = true; } catch (e) {}
  }
}
// `fromPop` true = dipanggil dari event popstate (history SUDAH mundur
// sendiri, jangan panggil history.back() lagi — itu akan mundur dua kali
// dan menutup katalognya).
function closeSheet(fromPop){
  sheetOpen = false;
  document.getElementById('app').classList.remove('order-mode');
  renderCartBar();
  if (_histPushed) {
    _histPushed = false;
    if (!fromPop) { _popIgnore++; try { history.back(); } catch (e) { _popIgnore--; } }
  }
}
document.getElementById('backBtn').addEventListener('click', function(){ closeSheet(false); });
window.addEventListener('popstate', function(){
  if (_popIgnore > 0) { _popIgnore--; return; }
  if (sentOpen) { closeSent(true); return; }
  if (sheetOpen) { closeSheet(true); return; }
  // Kembali dari mode daftar (masuk lewat landing) -> kembali ke landing.
  if (_listPushed) { _listPushed = false; goLanding(); }
});

function esc(s){
  var d = document.createElement('div');
  d.textContent = s == null ? '' : s;
  return d.innerHTML;
}

function buildOrderText(){
  var name = document.getElementById('custName').value.trim();
  var phone = document.getElementById('custPhone').value.trim();
  var note = document.getElementById('custNote').value.trim();
  var lines = ['PESANAN — ' + DATA.store, '━━━━━━━━━━━━━━━'];
  var byParent = {};
  var codeParts = [];
  Object.keys(cart).forEach(function(id){
    var u = byUnit[id]; if (!u) return;
    var qty = cart[id];
    var itemNote = (cartNotes[id] || '').trim();
    // Item 26a — catatan per-produk ikut baris kode mesin sbg segmen
    // opsional ":<catatan ter-encode>" — encodeURIComponent supaya bebas-
    // karakter (termasuk ';'/'=') tidak bentrok delimiter format ini.
    // Baris TANPA catatan tetap "id=qty" polos (backward-compatible).
    codeParts.push(id + '=' + qty + (itemNote ? ':' + encodeURIComponent(itemNote) : ''));
    var key = u.parentName || u.name;
    (byParent[key] = byParent[key] || []).push(
        {name:u.name, unit:u.unit, qty:qty, isChild: !!u.parentName, itemNote:itemNote});
  });
  Object.keys(byParent).forEach(function(k){
    var rows = byParent[k];
    if (rows.length === 1 && !rows[0].isChild) {
      lines.push(rows[0].name + ' ' + rows[0].unit + ' × ' + fmtQty(rows[0].qty));
      if (rows[0].itemNote) lines.push('    * ' + rows[0].itemNote);
    } else {
      lines.push(k);
      rows.forEach(function(r){
        var label = r.isChild ? r.name.split(' — ').slice(1).join(' — ') : r.name;
        lines.push('  > ' + label + ' ' + r.unit + ' × ' + fmtQty(r.qty));
        if (r.itemNote) lines.push('    * ' + r.itemNote);
      });
    }
  });
  lines.push('━━━━━━━━━━━━━━━');
  lines.push('Total: ' + rp(cartTotal()));
  lines.push('');
  lines.push('Nama: ' + (name || '-'));
  lines.push('HP: ' + (phone || '-'));
  if (note) lines.push('Catatan: ' + note);
  lines.push('');
  lines.push(DATA.machinePrefix + codeParts.join(';'));
  return lines.join('\n');
}

// Blueprint §7 — auto-hilang 2,5 detik, atau ditutup manual dgn tap.
// `persist` true utk kondisi yang memang menetap (mis. katalog kosong),
// yang di blueprint juga sengaja TIDAK auto-hide.
var _toastTimer = null;
function showToast(msg, opts){
  opts = opts || {};
  var t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.toggle('err', !!opts.error);
  t.classList.add('show');
  clearTimeout(_toastTimer);
  if (!opts.persist) {
    _toastTimer = setTimeout(function(){ t.classList.remove('show'); }, opts.ms || 2500);
  }
}
document.getElementById('toast').addEventListener('click', function(){
  clearTimeout(_toastTimer);
  this.classList.remove('show');
});

function copyText(text){
  var ok = false;
  try {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.focus(); ta.select();
    ok = document.execCommand('copy');
    document.body.removeChild(ta);
  } catch (e) { ok = false; }
  return ok;
}

// channel: 'wa' (WhatsApp, bawaan) atau 'tg' (Telegram). Dua jalur berbagi
// teks pesanan (termasuk kode mesin #PSN: — SAMA PERSIS), salin ke clipboard,
// dan simpan riwayat "Pesan lagi" (recordOrder sudah menolak dobel-ketuk
// isi identik < 2 menit). copyText + window.open SINKRON di handler klik agar
// lolos kebijakan browser.
function submitOrder(channel){
  if (cartCount() === 0) return;
  var text = buildOrderText();
  var copied = copyText(text);
  if (channel === 'tg') {
    // Telegram TIDAK mendukung mengisi teks otomatis ke chat pengguna
    // tertentu lewat tautan: salin dulu, pelanggan tempel sendiri.
    if (!DATA.telegramUrl) return;
    showToast(copied ? 'Pesanan disalin — tempel di chat Telegram'
                     : 'Gagal menyalin — salin manual dari halaman Pesanan');
    try { recordOrder(); } catch (e) {}
    window.open(DATA.telegramUrl, '_blank');
    showSent();
    return;
  }
  var num = (DATA.waNumber || '').replace(/[^0-9]/g, '');
  // Item 12 — direct: deep-link ke nomor WA toko. Non-direct: share WA
  // generik (tanpa nomor tujuan), pelanggan pilih sendiri kontaknya.
  var url = (DATA.waDirect && num)
    ? ('https://wa.me/' + num + '?text=' + encodeURIComponent(text))
    : ('https://api.whatsapp.com/send?text=' + encodeURIComponent(text));
  showToast('Teks pesanan disalin — tempel bila perlu');
  try { recordOrder(); } catch (e) {}
  window.open(url, '_blank');
  showSent();
}

// Halaman "Pesanan dikirim!": tampil SEGERA setelah Kirim (WhatsApp/Telegram
// dibuka di tab/aplikasi lain). Keranjang dikosongkan sesudah halaman tampil;
// riwayat "Pesan lagi" sudah tersimpan (recordOrder) sebelum ini. Memakai entri
// history milik halaman Pesanan, jadi tombol Kembali HP -> halaman awal.
var sentOpen = false;
function showSent(){
  if (sentOpen) return;
  sentOpen = true;
  document.getElementById('app').classList.add('sent-mode');
  var btn = document.getElementById('sentBack');
  try { btn.focus({preventScroll: true}); } catch (e) {}
  setTimeout(function(){ if (sentOpen) doClearCart(); }, 350);
}
function closeSent(fromPop){
  if (!sentOpen) return;
  sentOpen = false;
  document.getElementById('app').classList.remove('sent-mode');
  closeSheet(!!fromPop);
  // Tanpa animasi: halaman menu sendiri sedang muncul kembali (transisi CSS);
  // WAAPI di atas itu (flipY kolom cari) pernah membuat kolom cari tetap
  // 'visibility:hidden' di Chromium.
  goLanding(true);
  menuScroll.scrollTop = 0;
}
document.getElementById('sentBack').addEventListener('click', function(){ closeSent(false); });

// Blueprint §5 — satu tombol, dua aksi tergantung mode: dari daftar produk
// membuka ringkasan, dari ringkasan mengirim pesanan (WhatsApp).
document.getElementById('mainBtn').addEventListener('click', function(){
  if (clearConfirm) { setClearConfirm(false); return; } // tombol "Tidak"
  if (cartCount() === 0) return;
  if (document.getElementById('app').classList.contains('order-mode')) {
    submitOrder('wa');
  } else {
    openSheet();
  }
});
document.getElementById('mainBtnTg').addEventListener('click', function(){
  if (cartCount() === 0) return;
  if (document.getElementById('app').classList.contains('order-mode')) submitOrder('tg');
});

document.getElementById('copyBtn').addEventListener('click', function(){
  if (cartCount() === 0) { showToast('Pilih barang dulu'); return; }
  var ok = copyText(buildOrderText());
  showToast(ok ? 'Teks pesanan disalin' : 'Gagal menyalin — salin manual dari WhatsApp');
});

// Blueprint §6 — katalog tanpa produk sama sekali (mis. semua produk
// dinonaktifkan saat katalog dibuat) tampil sbg state "tutup" yang jelas:
// daftar diredupkan + toast menetap, bukan layar kosong tanpa penjelasan.
if (!DATA.products || DATA.products.length === 0) {
  document.getElementById('app').classList.add('closed');
}

// ── Game labirin
(function(){
  var card = document.getElementById('mazeCard'); if (!card) return;
  // Dimatikan owner (Pengaturan > Katalog): buang kartu sama sekali.
  if (!DATA.game) { var gs = document.getElementById('gameSlot'); if (gs && gs.parentNode) gs.parentNode.removeChild(gs); return; }
  var stage = document.getElementById('mzStage'), cv = document.getElementById('mzCanvas');
  var ctx = cv.getContext('2d'); if (!ctx) { card.style.display = 'none'; return; }
  var elTime = document.getElementById('mzTime'), elBest = document.getElementById('mzBest');
  var elWin = document.getElementById('mzWin'), elWinS = document.getElementById('mzWinS'), elWinR = document.getElementById('mzWinR');
  var elHint = document.getElementById('mzHint'), elGyro = document.getElementById('mzGyro');
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Tingkat kesulitan: ukuran petak, jumlah "lorong tembus" (makin sedikit = makin sulit).
  var LEVELS = {
    mudah:  {n: 6,  loops: 6},
    sedang: {n: 9,  loops: 3},
    sulit:  {n: 13, loops: 0}
  };
  var level = 'mudah';
  try { var sv = localStorage.getItem('posMazeLevel'); if (sv && LEVELS[sv]) level = sv; } catch (e) {}

  var W = 320, DPR = 1, pad = 6, cs = 40, t = 5, r = 10;
  var maze = null, rects = [], stat = null; // stat = kanvas statis (labirin)
  var bx = 0, by = 0, vx = 0, vy = 0, sx = 0, sy = 0, gx = 0, gy = 0, holeR = 12;
  var state = 'play';              // play | sink | win
  var sinkT = 0, winTimer = 0;
  var started = false, tStart = 0, elapsed = 0;
  var trail = [], parts = [];
  var touch = null, keys = {}, gyroVec = {x: 0, y: 0}, override = null;
  var gyroOn = false, gBase = null;

  function rnd(n) { return Math.floor(Math.random() * n); }
  function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }
  function fmt(s) { return s.toFixed(1).replace('.', ','); }

  // ── Labirin (recursive backtracker) ──
  function genMaze(n, loops) {
    var h = [], v = [], vis = [], y, x;
    for (y = 0; y <= n; y++) { h[y] = []; for (x = 0; x < n; x++) h[y][x] = true; }
    for (y = 0; y < n; y++) { v[y] = []; for (x = 0; x <= n; x++) v[y][x] = true; vis[y] = []; for (x = 0; x < n; x++) vis[y][x] = false; }
    var stack = [[0, 0]]; vis[0][0] = true;
    while (stack.length) {
      var c = stack[stack.length - 1], cx = c[0], cy = c[1], nb = [];
      if (cy > 0 && !vis[cy - 1][cx]) nb.push([cx, cy - 1, 'u']);
      if (cy < n - 1 && !vis[cy + 1][cx]) nb.push([cx, cy + 1, 'd']);
      if (cx > 0 && !vis[cy][cx - 1]) nb.push([cx - 1, cy, 'l']);
      if (cx < n - 1 && !vis[cy][cx + 1]) nb.push([cx + 1, cy, 'r']);
      if (!nb.length) { stack.pop(); continue; }
      var p = nb[rnd(nb.length)];
      if (p[2] === 'u') h[cy][cx] = false; else if (p[2] === 'd') h[cy + 1][cx] = false;
      else if (p[2] === 'l') v[cy][cx] = false; else v[cy][cx + 1] = false;
      vis[p[1]][p[0]] = true; stack.push([p[0], p[1]]);
    }
    for (var k = 0; k < loops; k++) { // buka beberapa dinding dalam: jalan pintas (level mudah)
      if (rnd(2)) { var yy = 1 + rnd(n - 1), xx = rnd(n); h[yy][xx] = false; }
      else { var y2 = rnd(n), x2 = 1 + rnd(n - 1); v[y2][x2] = false; }
    }
    return {n: n, h: h, v: v};
  }
  function solve(m) { // BFS: daftar petak dari start ke tujuan (untuk uji)
    var n = m.n, prev = {}, q = [[0, 0]], seen = {'0,0': 1};
    while (q.length) {
      var c = q.shift(), x = c[0], y = c[1];
      if (x === n - 1 && y === n - 1) break;
      var cand = [];
      if (y > 0 && !m.h[y][x]) cand.push([x, y - 1]);
      if (y < n - 1 && !m.h[y + 1][x]) cand.push([x, y + 1]);
      if (x > 0 && !m.v[y][x]) cand.push([x - 1, y]);
      if (x < n - 1 && !m.v[y][x + 1]) cand.push([x + 1, y]);
      for (var i = 0; i < cand.length; i++) {
        var key = cand[i][0] + ',' + cand[i][1];
        if (!seen[key]) { seen[key] = 1; prev[key] = x + ',' + y; q.push(cand[i]); }
      }
    }
    var path = [], cur = (n - 1) + ',' + (n - 1);
    while (cur) { var s = cur.split(','); path.unshift([+s[0], +s[1]]); cur = prev[cur]; }
    return path;
  }
  function cellCenter(cx, cy) { return [pad + (cx + 0.5) * cs, pad + (cy + 0.5) * cs]; }

  function buildRects() {
    rects = []; var n = maze.n, x, y;
    for (y = 0; y <= n; y++) for (x = 0; x < n; x++) if (maze.h[y][x]) {
      var yy = pad + y * cs; rects.push([pad + x * cs - t / 2, yy - t / 2, pad + (x + 1) * cs + t / 2, yy + t / 2]);
    }
    for (y = 0; y < n; y++) for (x = 0; x <= n; x++) if (maze.v[y][x]) {
      var xx = pad + x * cs; rects.push([xx - t / 2, pad + y * cs - t / 2, xx + t / 2, pad + (y + 1) * cs + t / 2]);
    }
  }

  // ── Ukuran & lapisan statis ──
  function cssVar(name, fb) { var v = getComputedStyle(document.documentElement).getPropertyValue(name).trim(); return v || fb; }
  function drawStatic() {
    if (!maze) return;
    stat = document.createElement('canvas'); stat.width = cv.width; stat.height = cv.height;
    var c = stat.getContext('2d'); c.scale(DPR, DPR);
    var field = cssVar('--field', '#f1eee7'), wall = cssVar('--ink-2', '#6c685f'), acc = cssVar('--accent', '#c96442'), line = cssVar('--line', '#e7e2d7');
    // lantai
    c.fillStyle = field; c.fillRect(0, 0, W, W);
    var g = c.createLinearGradient(0, 0, W, W); g.addColorStop(0, 'rgba(255,255,255,.10)'); g.addColorStop(1, 'rgba(0,0,0,.06)');
    c.fillStyle = g; c.fillRect(0, 0, W, W);
    // tanda start
    var s = cellCenter(0, 0);
    c.fillStyle = acc; c.globalAlpha = .16; c.beginPath(); c.arc(s[0], s[1], r * 1.5, 0, 6.2832); c.fill(); c.globalAlpha = 1;
    // lubang tujuan
    var gl = cellCenter(maze.n - 1, maze.n - 1); gx = gl[0]; gy = gl[1]; holeR = r * 1.2;
    var hg = c.createRadialGradient(gx, gy, holeR * .15, gx, gy, holeR * 1.25);
    hg.addColorStop(0, 'rgba(0,0,0,.92)'); hg.addColorStop(.72, 'rgba(0,0,0,.7)'); hg.addColorStop(1, 'rgba(0,0,0,0)');
    c.fillStyle = hg; c.beginPath(); c.arc(gx, gy, holeR * 1.25, 0, 6.2832); c.fill();
    c.strokeStyle = acc; c.lineWidth = Math.max(2, r * .22); c.beginPath(); c.arc(gx, gy, holeR, 0, 6.2832); c.stroke();
    // dinding (bayangan lalu isi)
    c.fillStyle = 'rgba(0,0,0,.18)';
    rects.forEach(function(q){ rr(c, q[0] + 1.2, q[1] + 1.8, q[2] - q[0], q[3] - q[1], Math.min(t / 2, 3)); });
    c.fillStyle = wall;
    rects.forEach(function(q){ rr(c, q[0], q[1], q[2] - q[0], q[3] - q[1], Math.min(t / 2, 3)); });
    c.fillStyle = 'rgba(255,255,255,.18)';
    rects.forEach(function(q){ var hgt = Math.min(1.2, (q[3] - q[1]) / 3); c.fillRect(q[0] + 1, q[1], Math.max(0, q[2] - q[0] - 2), hgt); });
    c.strokeStyle = line; c.lineWidth = 1; c.strokeRect(.5, .5, W - 1, W - 1);
  }
  function rr(c, x, y, w, h, rad) { c.beginPath(); c.moveTo(x + rad, y); c.arcTo(x + w, y, x + w, y + h, rad); c.arcTo(x + w, y + h, x, y + h, rad); c.arcTo(x, y + h, x, y, rad); c.arcTo(x, y, x + w, y, rad); c.closePath(); c.fill(); }

  function resize() {
    var cw = Math.round(stage.clientWidth);
    if (!cw && cv.width) return; // tersembunyi: pertahankan ukuran terakhir
    var w = cw || 320;
    if (w === W && cv.width) return;
    // Ukuran papan berubah (mis. awalnya 320 bawaan saat kartu masih tersembunyi,
    // lalu lebar asli): geometri labirin HARUS dibangun ulang & posisi bola
    // diskalakan — kalau tidak dinding tetap berukuran lama sedangkan lubang
    // tujuan memakai ukuran baru (lubang "melayang" di luar labirin).
    var oldW = W, oldPad = pad, oldSpan = W - 2 * pad;
    var nbx = (bx - oldPad) / oldSpan, nby = (by - oldPad) / oldSpan;
    var nsx = (sx - oldPad) / oldSpan, nsy = (sy - oldPad) / oldSpan;
    W = w; DPR = Math.min(window.devicePixelRatio || 1, 2);
    cv.width = Math.round(W * DPR); cv.height = Math.round(W * DPR);
    layout();
    if (maze) {
      buildRects();
      var span = W - 2 * pad, k = W / oldW;
      bx = pad + nbx * span; by = pad + nby * span;
      sx = pad + nsx * span; sy = pad + nsy * span;
      vx *= k; vy *= k; trail = [];
    }
    drawStatic(); draw();
  }
  function layout() {
    var n = LEVELS[level].n; pad = Math.max(5, Math.round(W * .018)); cs = (W - 2 * pad) / n;
    t = Math.max(3.5, cs * .13); r = Math.max(6, cs * .28);
  }

  // ── Mulai labirin baru ──
  function newMaze(keepWin) {
    clearTimeout(winTimer); var cfg = LEVELS[level];
    maze = genMaze(cfg.n, cfg.loops); layout(); buildRects();
    var s = cellCenter(0, 0); bx = s[0]; by = s[1]; vx = vy = 0; sx = sy = 0;
    state = 'play'; started = false; elapsed = 0; trail = []; parts = [];
    elTime.textContent = '0,0'; elWin.classList.remove('show');
    drawStatic(); showBest(); draw(); kick();
  }
  function showBest() {
    var b = getBest(); elBest.textContent = b ? 'Rekor ' + fmt(b) + ' dtk' : 'Rekor —';
  }
  function getBest() { try { var o = JSON.parse(localStorage.getItem('posMazeBest') || '{}'); return o[level] || 0; } catch (e) { return 0; } }
  function setBest(sec) {
    try { var o = JSON.parse(localStorage.getItem('posMazeBest') || '{}'); o[level] = sec; localStorage.setItem('posMazeBest', JSON.stringify(o)); } catch (e) {}
  }

  // ── Input ──
  function inputVec() {
    if (override) return {x: override[0], y: override[1]};
    var x = 0, y = 0;
    if (touch) { x += touch.x; y += touch.y; }
    if (keys.ArrowLeft || keys.a) x -= 1; if (keys.ArrowRight || keys.d) x += 1;
    if (keys.ArrowUp || keys.w) y -= 1; if (keys.ArrowDown || keys.s) y += 1;
    if (gyroOn) { x += gyroVec.x; y += gyroVec.y; }
    var m = Math.sqrt(x * x + y * y); if (m > 1) { x /= m; y /= m; }
    return {x: x, y: y};
  }
  stage.addEventListener('pointerdown', function(e){
    if (state === 'win' && elWin.classList.contains('show')) { clearTimeout(winTimer); newMaze(); return; }
    var b = stage.getBoundingClientRect();
    touch = {ox: e.clientX - b.left, oy: e.clientY - b.top, x: 0, y: 0, cx: e.clientX - b.left, cy: e.clientY - b.top};
    try { stage.setPointerCapture(e.pointerId); } catch (er) {}
    kick(); e.preventDefault();
  });
  stage.addEventListener('pointermove', function(e){
    if (!touch) return;
    var b = stage.getBoundingClientRect(), px = e.clientX - b.left, py = e.clientY - b.top, R = W * .2;
    touch.cx = px; touch.cy = py;
    var dx = (px - touch.ox) / R, dy = (py - touch.oy) / R, m = Math.sqrt(dx * dx + dy * dy);
    if (m > 1) { dx /= m; dy /= m; m = 1; }
    // kurva halus: gerakan kecil = pelan, gerakan penuh = kencang
    var k = m * m * (3 - 2 * m) / (m || 1); touch.x = dx * k; touch.y = dy * k;
    kick();
  });
  function endTouch() { touch = null; kick(); }
  stage.addEventListener('pointerup', endTouch);
  stage.addEventListener('pointercancel', endTouch);
  stage.addEventListener('lostpointercapture', endTouch);
  window.addEventListener('keydown', function(e){
    if (!visible) return;
    var tg = e.target && e.target.tagName; if (tg === 'INPUT' || tg === 'TEXTAREA') return;
    var k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
    if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'a', 'd', 'w', 's'].indexOf(k) < 0) return;
    if (k.length > 1) e.preventDefault();
    keys[k] = true; kick();
  });
  window.addEventListener('keyup', function(e){ var k = e.key.length === 1 ? e.key.toLowerCase() : e.key; delete keys[k]; });

  // ── Gyro ──
  function onOrient(e) {
    if (e.gamma == null || e.beta == null) return;
    if (!gBase) gBase = {g: e.gamma, b: e.beta};
    var a = (screen.orientation && screen.orientation.angle) || window.orientation || 0;
    var g = e.gamma - gBase.g, b = e.beta - gBase.b, x, y;
    if (a === 90) { x = b; y = -g; } else if (a === 180) { x = -g; y = -b; } else if (a === 270 || a === -90) { x = -b; y = g; } else { x = g; y = b; }
    gyroVec.x = clamp(x / 22, -1, 1); gyroVec.y = clamp(y / 22, -1, 1);
    if (Math.abs(gyroVec.x) + Math.abs(gyroVec.y) > .04) kick();
  }
  function setGyro(on) {
    gyroOn = on; gBase = null; gyroVec.x = gyroVec.y = 0;
    elGyro.setAttribute('aria-pressed', on ? 'true' : 'false');
    elHint.textContent = on ? 'Miringkan HP untuk menggulirkan bola (ketuk ikon lagi untuk mengkalibrasi ulang)' : 'Geser jari di papan untuk menggerakkan bola';
    try { localStorage.setItem('posMazeGyro', on ? '1' : '0'); } catch (e) {}
    window.removeEventListener('deviceorientation', onOrient);
    if (on) window.addEventListener('deviceorientation', onOrient);
  }
  elGyro.addEventListener('click', function(){
    if (gyroOn) { setGyro(false); return; }
    var DOE = window.DeviceOrientationEvent;
    if (!DOE) { elHint.textContent = 'Perangkat ini tidak mendukung gyro'; return; }
    if (typeof DOE.requestPermission === 'function') { // iOS: izin harus dari ketukan pengguna
      DOE.requestPermission().then(function(s){
        if (s === 'granted') setGyro(true); else elHint.textContent = 'Izin gyro ditolak — kontrol sentuh tetap bisa dipakai';
      }).catch(function(){ elHint.textContent = 'Gyro tidak bisa diaktifkan'; });
    } else { setGyro(true); }
  });
  try { // Android/Chrome: pulihkan pilihan gyro tanpa izin tambahan
    if (localStorage.getItem('posMazeGyro') === '1' && window.DeviceOrientationEvent && typeof DeviceOrientationEvent.requestPermission !== 'function') setGyro(true);
  } catch (e) {}

  // ── Fisika ──
  var ACC = 3.1, VMAX = 1.7, DAMP = 2.0, REST = .42, STEP = 1 / 180;
  function physics(h) {
    var inp = inputVec(), a = ACC * W;
    vx += inp.x * a * h; vy += inp.y * a * h;
    var d = Math.exp(-DAMP * h); vx *= d; vy *= d;
    var sp = Math.sqrt(vx * vx + vy * vy), mx = VMAX * W; if (sp > mx) { vx *= mx / sp; vy *= mx / sp; }
    bx += vx * h; by += vy * h;
    var hit = 0;
    for (var i = 0; i < rects.length; i++) {
      var q = rects[i];
      if (bx + r < q[0] || bx - r > q[2] || by + r < q[1] || by - r > q[3]) continue;
      var cx = clamp(bx, q[0], q[2]), cy = clamp(by, q[1], q[3]), dx = bx - cx, dy = by - cy, dd = dx * dx + dy * dy;
      if (dd >= r * r) continue;
      var nx, ny, pen;
      if (dd > 1e-6) { var dl = Math.sqrt(dd); nx = dx / dl; ny = dy / dl; pen = r - dl; }
      else { var l = bx - q[0], rr2 = q[2] - bx, tp = by - q[1], bt = q[3] - by, mn = Math.min(l, rr2, tp, bt);
        if (mn === l) { nx = -1; ny = 0; pen = r + l; } else if (mn === rr2) { nx = 1; ny = 0; pen = r + rr2; } else if (mn === tp) { nx = 0; ny = -1; pen = r + tp; } else { nx = 0; ny = 1; pen = r + bt; } }
      bx += nx * pen; by += ny * pen;
      var vn = vx * nx + vy * ny;
      if (vn < 0) { vx -= (1 + REST) * vn * nx; vy -= (1 + REST) * vn * ny; if (-vn > hit) hit = -vn; }
    }
    if (hit > W * .45 && navigator.vibrate && !reduce) { try { navigator.vibrate(8); } catch (e) {} }
    // tarikan lubang tujuan
    var gdx = gx - bx, gdy = gy - by, gd = Math.sqrt(gdx * gdx + gdy * gdy);
    if (gd < holeR * 1.6) { var pull = (1 - gd / (holeR * 1.6)) * W * 1.3; vx += gdx / (gd || 1) * pull * h; vy += gdy / (gd || 1) * pull * h; }
    if (gd < holeR * .55) { state = 'sink'; sinkT = 0; sx = bx; sy = by; finish(); }
  }
  function finish() {
    var sec = elapsed || (started ? (performance.now() - tStart) / 1000 : 0);
    var best = getBest(), rec = !best || sec < best;
    if (rec && sec > 0) setBest(sec);
    elTime.textContent = fmt(sec);
    elWinS.textContent = 'Waktu ' + fmt(sec) + ' dtk';
    elWinR.hidden = !rec; showBest();
    for (var i = 0; i < (reduce ? 0 : 36); i++) {
      var an = Math.random() * 6.2832, sp = (.25 + Math.random() * .7) * W;
      parts.push({x: gx, y: gy, vx: Math.cos(an) * sp, vy: Math.sin(an) * sp - W * .25, life: 1, c: i % 3});
    }
    winTimer = setTimeout(function(){ newMaze(); }, 3200);
  }

  // ── Gambar ──
  function draw() {
    if (!stat) return;
    ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.drawImage(stat, 0, 0);
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    var acc = cssVar('--accent', '#c96442');
    if (!reduce) for (var i = 0; i < trail.length; i++) {
      var p = trail[i], f = (i + 1) / trail.length;
      ctx.globalAlpha = f * .18; ctx.fillStyle = acc; ctx.beginPath(); ctx.arc(p[0], p[1], r * (.45 + f * .4), 0, 6.2832); ctx.fill();
    }
    ctx.globalAlpha = 1;
    var scale = 1, x = bx, y = by;
    if (state === 'sink' || state === 'win') { var k = clamp(sinkT / .35, 0, 1); x = sx + (gx - sx) * k; y = sy + (gy - sy) * k; scale = 1 - .8 * k; }
    var rad = r * scale;
    // bayangan
    var sh = ctx.createRadialGradient(x + rad * .25, y + rad * .4, rad * .2, x + rad * .25, y + rad * .4, rad * 1.25);
    sh.addColorStop(0, 'rgba(0,0,0,.34)'); sh.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = sh; ctx.beginPath(); ctx.arc(x + rad * .25, y + rad * .4, rad * 1.25, 0, 6.2832); ctx.fill();
    // bola logam
    var bg = ctx.createRadialGradient(x - rad * .38, y - rad * .42, rad * .08, x, y, rad);
    bg.addColorStop(0, '#ffffff'); bg.addColorStop(.28, '#d9dde2'); bg.addColorStop(.7, '#8a9098'); bg.addColorStop(1, '#4a4f56');
    ctx.fillStyle = bg; ctx.beginPath(); ctx.arc(x, y, rad, 0, 6.2832); ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,.35)'; ctx.lineWidth = 1; ctx.stroke();
    // serpihan konfeti
    for (var j = 0; j < parts.length; j++) {
      var q = parts[j]; ctx.globalAlpha = clamp(q.life, 0, 1);
      ctx.fillStyle = q.c === 0 ? acc : (q.c === 1 ? '#f2b84b' : '#6fa380');
      ctx.fillRect(q.x - 2, q.y - 2, 4, 4);
    }
    ctx.globalAlpha = 1;
    // penunjuk geser (joystick halus)
    if (touch) {
      ctx.strokeStyle = 'rgba(255,255,255,.55)'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(touch.ox, touch.oy, W * .2, 0, 6.2832); ctx.stroke();
      ctx.fillStyle = 'rgba(255,255,255,.35)'; ctx.beginPath(); ctx.arc(touch.cx, touch.cy, W * .035, 0, 6.2832); ctx.fill();
    }
  }

  // ── Loop (berhenti saat diam / tak terlihat) ──
  var running = false, last = 0, acc = 0, visible = false, lastLabel = 0;
  function kick() {
    if (running || !visible || document.hidden) return;
    running = true; last = performance.now(); requestAnimationFrame(frame);
  }
  function frame(now) {
    var dt = Math.min(.05, (now - last) / 1000); last = now;
    if (state === 'play') {
      acc += dt;
      var inp = inputVec();
      if (!started && (Math.abs(inp.x) + Math.abs(inp.y) > .05)) { started = true; tStart = now; }
      while (acc >= STEP) { physics(STEP); acc -= STEP; if (state !== 'play') break; }
      if (started && state === 'play') elapsed = (now - tStart) / 1000;
      if (!reduce) { trail.push([bx, by]); if (trail.length > 10) trail.shift(); }
    } else { acc = 0; sinkT += dt; if (sinkT > .35 && state === 'sink') state = 'win'; if (state === 'win' && !elWin.classList.contains('show')) elWin.classList.add('show'); }
    for (var i = parts.length - 1; i >= 0; i--) { var p = parts[i]; p.vy += W * 1.6 * dt; p.x += p.vx * dt; p.y += p.vy * dt; p.life -= dt * .7; if (p.life <= 0) parts.splice(i, 1); }
    if (now - lastLabel > 100) { lastLabel = now; if (started && state === 'play') elTime.textContent = fmt(elapsed); }
    draw();
    var sp = vx * vx + vy * vy, inp2 = inputVec();
    var idle = state === 'play' && sp < 4 && Math.abs(inp2.x) + Math.abs(inp2.y) < .02 && !touch && !parts.length;
    if (idle || (state === 'win' && !parts.length)) { running = false; return; }
    requestAnimationFrame(frame);
  }
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function(es){ visible = es[es.length - 1].isIntersecting; if (visible) { resize(); kick(); } }, {threshold: .2}).observe(card);
  } else { visible = true; }
  document.addEventListener('visibilitychange', function(){ if (!document.hidden) kick(); });
  if ('ResizeObserver' in window) new ResizeObserver(function(){ resize(); }).observe(stage); else window.addEventListener('resize', resize);
  // Ganti tema (terang/gelap) -> gambar ulang lapisan statis.
  new MutationObserver(function(){ drawStatic(); draw(); }).observe(document.documentElement, {attributes: true, attributeFilter: ['data-theme']});

  // Tingkat kesulitan.
  var seg = document.getElementById('mzSeg');
  function setLevel(lv) {
    level = lv; try { localStorage.setItem('posMazeLevel', lv); } catch (e) {}
    [].forEach.call(seg.querySelectorAll('button'), function(b){ b.setAttribute('aria-selected', b.getAttribute('data-lv') === lv ? 'true' : 'false'); });
    newMaze();
  }
  seg.addEventListener('click', function(e){ var b = e.target.closest('button'); if (b) setLevel(b.getAttribute('data-lv')); });
  document.getElementById('mzNew').addEventListener('click', function(){ newMaze(); });
  [].forEach.call(seg.querySelectorAll('button'), function(b){ b.setAttribute('aria-selected', b.getAttribute('data-lv') === level ? 'true' : 'false'); });

  // Pengait uji (tidak dipakai UI).
  window.__maze = {
    state: function(){ return {state: state, level: level, n: maze.n, bx: bx, by: by, vx: vx, vy: vy, r: r, cs: cs, gx: gx, gy: gy, started: started, elapsed: elapsed, running: running, W: W}; },
    solve: function(){ return solve(maze).map(function(c){ return cellCenter(c[0], c[1]); }); },
    drive: function(x, y){ override = (x == null) ? null : [x, y]; kick(); },
    newMaze: newMaze, setLevel: setLevel
  };

  resize(); newMaze();
})();

Array.prototype.forEach.call(document.querySelectorAll('.stk'), stkMount);
loadCart();
loadAccess();
buildChips();
initPlaceholder();
renderExtras();
if (DATA.reorder && loadHistory().length) requestPersist();
initAnn();
applyState(computeState(), false);
setSelChips();
syncTbId();
applyOpenState();
render();
// Jadwal dicek ulang berkala (halaman yang dibiarkan terbuka melewati jam
// buka/tutup ikut berganti) dan saat kembali ke tab.
setInterval(applyOpenState, 30000);
document.addEventListener('visibilitychange', function(){ if (!document.hidden) applyOpenState(); });
if (!DATA.products || DATA.products.length === 0) {
  showToast('Katalog ini sedang kosong — hubungi toko', {persist:true});
}
</script>
</body>
</html>
''';
