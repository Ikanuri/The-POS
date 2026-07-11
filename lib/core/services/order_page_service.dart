import 'dart:convert';

import '../database/app_database.dart';
import 'price_service.dart';

/// **EKSPERIMENTAL.** Generate halaman HTML self-contained (tanpa server,
/// tanpa CDN) berisi katalog produk aktif yang bisa dibuka pelanggan dari
/// WhatsApp untuk memilih barang, lalu mengirim balik teks pesanan siap
/// dibaca kasir (format manusia + baris kode mesin `#PSN:` untuk fase
/// tempel-otomatis ke keranjang di iterasi berikutnya).
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
  /// `#PSN:<productUnitId>=<qty>;<productUnitId>=<qty>;...`.
  static const machineCodePrefix = '#PSN:';

  /// Generate HTML katalog dari seluruh produk aktif (induk + varian) yang
  /// punya satuan dasar & harga > 0. `productCount` = jumlah induk yang
  /// masuk katalog (belum termasuk varian) — untuk info ringkas di UI.
  static Future<({String html, int productCount})> generateHtml({
    required AppDatabase db,
    required String storeName,
    String storeWhatsapp = '',
  }) async {
    final catalog = await _buildCatalogJson(db);
    final generatedAt = _formatGeneratedAt(DateTime.now());
    final nameOrDefault = storeName.isEmpty ? 'Toko' : storeName;
    final waDigits = storeWhatsapp.replaceAll(RegExp(r'[^0-9]'), '');

    final dataJson = jsonEncode({
      'store': nameOrDefault,
      'generatedAt': generatedAt,
      'waNumber': waDigits,
      'machinePrefix': machineCodePrefix,
      'products': catalog,
    });

    final html = _htmlTemplate
        // Konteks HTML biasa (di dalam <title>) — escape &/</> agar nama
        // toko yang mengandung karakter itu tidak merusak markup.
        .replaceAll('__STORE_NAME__', _escapeHtml(nameOrDefault))
        // Konteks di dalam <script> — SELALU escape "</" jadi "<\/" (teknik
        // standar embed-JSON-in-script) supaya nama toko yang kebetulan
        // memuat "</script>" tidak menutup blok skrip lebih awal lalu
        // membuat sisanya dieksekusi sebagai HTML/skrip baru (XSS).
        .replaceAll('__DATA_JSON__', dataJson.replaceAll('</', r'<\/'));
    return (html: html, productCount: catalog.length);
  }

  static Future<List<Map<String, Object?>>> _buildCatalogJson(
      AppDatabase db) async {
    final priceService = PriceService(db);
    final unitTypes = await db.getAllUnitTypes();
    final typeNameById = {for (final u in unitTypes) u.id: u.name};

    // Hanya produk induk (bukan varian) yang aktif — varian ditautkan di
    // bawah induknya masing-masing, sama seperti tampilan katalog kasir.
    // `searchProducts` TIDAK menyaring varian (beda dari `watchProducts`
    // yang punya `parentProductId.isNull()`) — filter manual di sini agar
    // varian tidak ikut muncul sebagai baris induk terpisah.
    final parents = (await db.searchProducts(''))
        .where((p) => p.parentProductId == null)
        .toList();

    final out = <Map<String, Object?>>[];
    for (final p in parents) {
      final units = await db.getProductUnits(p.id);
      // Fallback ke satuan pertama kalau tidak ada yang ditandai isBaseUnit
      // (mis. produk lama hasil import CSV sebelum fix) — konsisten dengan
      // pola dipakai di seluruh app (kasir_screen, produk_form_screen, dst),
      // supaya produk begini tidak lenyap diam-diam dari katalog.
      final base = units.where((u) => u.isBaseUnit).firstOrNull ?? units.firstOrNull;
      if (base == null) continue;
      final resolved =
          await priceService.resolvePrice(productUnitId: base.id, qty: 1);
      if (resolved.price <= 0) continue;

      final variantsOut = <Map<String, Object?>>[];
      final variants = await db.getVariants(p.id);
      for (final v in variants) {
        final vUnits = await db.getProductUnits(v.id);
        final vBase =
            vUnits.where((u) => u.isBaseUnit).firstOrNull ?? vUnits.firstOrNull;
        if (vBase == null) continue;
        final vResolved =
            await priceService.resolvePrice(productUnitId: vBase.id, qty: 1);
        if (vResolved.price <= 0) continue;
        variantsOut.add({
          'unitId': vBase.id,
          'name': v.name,
          'unit': typeNameById[vBase.unitTypeId ?? 1] ?? 'Satuan',
          'price': vResolved.price,
        });
      }

      // Induk yang HANYA punya varian (tidak dijual satuan dasarnya sendiri)
      // tetap disertakan sebagai header pengelompok tanpa harga tampil —
      // baris "beli langsung" untuk induk tetap tersedia bila harga valid.
      out.add({
        'id': p.id,
        'name': p.name,
        'unitId': base.id,
        'unit': typeNameById[base.unitTypeId ?? 1] ?? 'Satuan',
        'price': resolved.price,
        'variants': variantsOut,
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
:root{
  --accent:#c96442; --accent-2:#d97757;
  --canvas:#ebe8e0; --panel:#fbfaf7; --card:#ffffff;
  --ink:#2a2824; --ink-2:#6c685f; --ink-3:#9d988b;
  --line:#e7e2d7; --field:#f1eee7;
  --ok:#4f7b5e; --warn:#b9702b;
  --r-card:14px; --r-btn:11px;
  --font:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;
  --serif:Georgia,"Iowan Old Style","Palatino Linotype",serif;
}
@media (prefers-color-scheme: dark){
  :root{
    --canvas:#161412; --panel:#211e1c; --card:#2a2623;
    --ink:#ece7dd; --ink-2:#a8a298; --ink-3:#726c63;
    --line:#383330; --field:#1c1917;
    --ok:#6fa380; --warn:#d39a52;
  }
}
/* Toggle manual (tombol matahari/bulan) — menang atas prefers-color-scheme
   di kedua arah, supaya pilihan user selalu dihormati. */
:root[data-theme="dark"]{
  --canvas:#161412; --panel:#211e1c; --card:#2a2623;
  --ink:#ece7dd; --ink-2:#a8a298; --ink-3:#726c63;
  --line:#383330; --field:#1c1917;
  --ok:#6fa380; --warn:#d39a52;
}
:root[data-theme="light"]{
  --canvas:#ebe8e0; --panel:#fbfaf7; --card:#ffffff;
  --ink:#2a2824; --ink-2:#6c685f; --ink-3:#9d988b;
  --line:#e7e2d7; --field:#f1eee7;
  --ok:#4f7b5e; --warn:#b9702b;
}
*,*::before,*::after{box-sizing:border-box;}
html,body{margin:0;height:100%;}
body{
  font-family:var(--font); background:var(--canvas); color:var(--ink);
  -webkit-font-smoothing:antialiased; display:flex; justify-content:center;
}
#app{width:100%;max-width:480px;min-height:100vh;background:var(--panel);
  display:flex;flex-direction:column;position:relative;}
.topbar{padding:14px 16px 10px;border-bottom:1px solid var(--line);
  background:var(--panel);position:sticky;top:0;z-index:5;
  display:flex;align-items:flex-start;justify-content:space-between;gap:10px;}
.tb-store{font-family:var(--serif);font-size:19px;font-weight:600;}
.tb-sub{font-size:11px;color:var(--ink-3);margin-top:2px;}
.theme-btn{flex-shrink:0;width:34px;height:34px;border:1px solid var(--line);
  background:var(--field);color:var(--ink-2);border-radius:999px;cursor:pointer;
  display:flex;align-items:center;justify-content:center;}
.theme-btn svg{width:17px;height:17px;}
.search-wrap{padding:10px 16px;}
.search{display:flex;align-items:center;gap:8px;background:var(--field);
  border-radius:var(--r-btn);padding:9px 12px;}
.search input{flex:1;border:none;background:transparent;font-size:14px;
  color:var(--ink);outline:none;font-family:var(--font);}
.search svg{flex-shrink:0;opacity:.6;}
.list{flex:1;overflow-y:auto;padding:0 16px 96px;}
.prow{background:var(--card);border:1px solid var(--line);border-radius:var(--r-card);
  margin-bottom:8px;overflow:hidden;}
.prow-main{display:flex;align-items:center;gap:10px;padding:12px;}
.prow-info{flex:1;min-width:0;}
.prow-name{font-size:14px;font-weight:600;}
.prow-meta{font-size:12px;color:var(--ink-2);margin-top:2px;font-family:var(--serif);}
.stepper{display:flex;align-items:center;gap:0;background:var(--field);
  border-radius:999px;overflow:hidden;flex-shrink:0;}
.stepper button{width:30px;height:30px;border:none;background:transparent;
  color:var(--accent);font-size:17px;font-weight:700;cursor:pointer;
  display:flex;align-items:center;justify-content:center;}
.stepper .n{min-width:22px;text-align:center;font-weight:700;font-size:13px;}
.add-btn{border:none;background:var(--accent);color:#fff;border-radius:999px;
  padding:7px 14px;font-size:12.5px;font-weight:700;cursor:pointer;flex-shrink:0;}
.chev{width:28px;height:28px;border:none;background:transparent;cursor:pointer;
  display:flex;align-items:center;justify-content:center;flex-shrink:0;
  color:var(--ink-3);transition:transform .15s;}
details[open] .chev{transform:rotate(180deg);}
summary{list-style:none;cursor:pointer;}
summary::-webkit-details-marker{display:none;}
.vlist{padding:0 12px 10px;border-top:1px solid var(--line);}
.vrow{display:flex;align-items:center;gap:10px;padding:9px 0 9px 14px;
  border-bottom:1px dashed var(--line);}
.vrow:last-child{border-bottom:none;}
.vrow-info{flex:1;min-width:0;font-size:13px;font-weight:500;}
.vrow-price{font-size:12px;color:var(--ink-2);font-family:var(--serif);margin-top:1px;}
.vmatch{background:rgba(201,100,66,.10);}
.empty{text-align:center;color:var(--ink-3);padding:50px 20px;font-size:13.5px;}
.cartbar{position:fixed;left:0;right:0;bottom:0;max-width:480px;margin:0 auto;
  background:var(--card);border-top:1px solid var(--line);padding:10px 14px;
  display:flex;align-items:center;gap:10px;box-shadow:0 -4px 18px rgba(0,0,0,.08);}
.cb-count{width:32px;height:32px;border-radius:999px;background:var(--accent);
  color:#fff;display:flex;align-items:center;justify-content:center;
  font-weight:700;font-size:13px;flex-shrink:0;}
.cb-count.empty{background:var(--ink-3);}
.cb-info{flex:1;min-width:0;}
.cb-lbl{font-size:11px;color:var(--ink-3);}
.cb-total{font-size:21px;font-weight:700;font-family:var(--serif);}
.cb-view{border:1px solid var(--line);background:transparent;color:var(--ink);
  border-radius:var(--r-btn);padding:9px 16px;font-size:13px;font-weight:600;
  cursor:pointer;flex-shrink:0;}
.cb-view:disabled{opacity:.4;}
.scrim{position:fixed;inset:0;background:rgba(20,16,10,.42);z-index:20;
  display:none;}
.scrim.show{display:block;}
.sheet{position:fixed;left:0;right:0;bottom:0;max-width:480px;margin:0 auto;
  background:var(--panel);border-radius:18px 18px 0 0;z-index:21;
  max-height:86vh;display:flex;flex-direction:column;
  transform:translateY(100%);transition:transform .22s ease-out;}
.sheet.show{transform:translateY(0);}
.sheet-grip{width:38px;height:4px;background:var(--line);border-radius:2px;
  margin:10px auto 4px;flex-shrink:0;}
.sheet-head{display:flex;align-items:center;padding:6px 16px 10px;flex-shrink:0;}
.sheet-head b{font-size:15px;}
.sheet-x{margin-left:auto;border:none;background:transparent;color:var(--ink-3);
  font-size:20px;cursor:pointer;padding:4px;}
.sheet-body{overflow-y:auto;padding:0 16px;flex:1;}
.citem{display:flex;align-items:center;gap:10px;padding:10px 0;
  border-bottom:1px solid var(--line);}
.ci-info{flex:1;min-width:0;}
.ci-name{font-size:13.5px;font-weight:600;}
.ci-price{font-size:11.5px;color:var(--ink-3);margin-top:1px;}
.field-label{font-size:11px;color:var(--ink-3);font-weight:600;margin:14px 0 5px;}
.tfield{width:100%;border:1px solid var(--line);background:var(--field);
  border-radius:var(--r-btn);padding:10px 12px;font-size:13.5px;color:var(--ink);
  font-family:var(--font);outline:none;}
textarea.tfield{resize:none;min-height:56px;}
.sheet-foot{padding:12px 16px calc(16px + env(safe-area-inset-bottom));
  border-top:1px solid var(--line);flex-shrink:0;}
.grand{display:flex;justify-content:space-between;align-items:baseline;
  margin-bottom:10px;}
.grand .gl{font-size:13px;color:var(--ink-2);}
.grand .gv{font-size:27px;font-weight:700;font-family:var(--serif);}
.wa-btn{width:100%;border:none;background:#25D366;color:#fff;border-radius:var(--r-btn);
  padding:13px;font-size:14.5px;font-weight:700;cursor:pointer;
  display:flex;align-items:center;justify-content:center;gap:8px;}
.wa-btn:disabled{opacity:.4;}
.copy-btn{width:100%;border:1px solid var(--line);background:transparent;
  color:var(--ink);border-radius:var(--r-btn);padding:10px;font-size:13px;
  font-weight:600;cursor:pointer;margin-top:8px;}
.toast{position:fixed;left:50%;bottom:100px;transform:translateX(-50%);
  background:var(--ink);color:var(--panel);padding:9px 16px;border-radius:999px;
  font-size:12.5px;font-weight:600;z-index:30;opacity:0;pointer-events:none;
  transition:opacity .2s;}
.toast.show{opacity:1;}
</style>
</head>
<body>
<div id="app">
  <div class="topbar">
    <div>
      <div class="tb-store" id="storeName"></div>
      <div class="tb-sub" id="storeSub"></div>
    </div>
    <button class="theme-btn" id="themeBtn" type="button" aria-label="Ganti tampilan terang/gelap"></button>
  </div>
  <div class="search-wrap">
    <div class="search">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
      <input id="q" type="text" placeholder="Cari produk…" autocomplete="off" />
    </div>
  </div>
  <div class="list" id="list"></div>

  <div class="cartbar">
    <div class="cb-count empty" id="cbCount">0</div>
    <div class="cb-info">
      <div class="cb-lbl" id="cbLbl">Belum ada barang dipilih</div>
      <div class="cb-total" id="cbTotal">Rp 0</div>
    </div>
    <button class="cb-view" id="cbView" disabled>Lihat Pesanan</button>
  </div>
</div>

<div class="scrim" id="scrim"></div>
<div class="sheet" id="sheet">
  <div class="sheet-grip"></div>
  <div class="sheet-head"><b>Pesanan Anda</b><button class="sheet-x" id="sheetClose">&times;</button></div>
  <div class="sheet-body">
    <div id="cartItems"></div>
    <div class="field-label">Nama</div>
    <input class="tfield" id="custName" placeholder="Nama Anda" />
    <div class="field-label">No. HP</div>
    <input class="tfield" id="custPhone" type="tel" placeholder="08xxxxxxxxxx" />
    <div class="field-label">Catatan (opsional)</div>
    <textarea class="tfield" id="custNote" placeholder="mis. antar sore ya"></textarea>
  </div>
  <div class="sheet-foot">
    <div class="grand"><span class="gl">Total</span><span class="gv" id="sheetTotal">Rp 0</span></div>
    <button class="wa-btn" id="waBtn">
      <svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M12.04 2C6.58 2 2.13 6.45 2.13 11.91c0 1.75.46 3.45 1.32 4.95L2 22l5.28-1.38c1.44.79 3.06 1.2 4.71 1.2h.01c5.46 0 9.91-4.45 9.91-9.91C21.9 6.45 17.5 2 12.04 2z"/></svg>
      Kirim via WhatsApp
    </button>
    <button class="copy-btn" id="copyBtn">Salin Teks Pesanan</button>
  </div>
</div>
<div class="toast" id="toast"></div>

<script>
var DATA = __DATA_JSON__;
var cart = {}; // unitId -> qty
var byUnit = {}; // unitId -> {name, unit, price, parentName}
var openState = {}; // productId -> bool, dropdown varian tetap terbuka/tertutup lewat re-render
var sheetOpen = false; // hindari renderCartSheet() sia-sia saat sheet tertutup

// ── Toggle terang/gelap manual — menimpa prefers-color-scheme, disimpan
// per-browser lewat localStorage supaya pilihan bertahan saat file dibuka lagi.
var ICON_SUN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>';
var ICON_MOON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.8A9 9 0 1111.2 3a7 7 0 009.8 9.8z"/></svg>';

function applyTheme(mode){
  document.documentElement.setAttribute('data-theme', mode);
  document.getElementById('themeBtn').innerHTML = mode === 'dark' ? ICON_SUN : ICON_MOON;
}
function initTheme(){
  var saved = null;
  try { saved = localStorage.getItem('posOrderTheme'); } catch (e) {}
  if (saved !== 'light' && saved !== 'dark') {
    saved = (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light';
  }
  applyTheme(saved);
}
document.getElementById('themeBtn').addEventListener('click', function(){
  var cur = document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
  var next = cur === 'dark' ? 'light' : 'dark';
  applyTheme(next);
  try { localStorage.setItem('posOrderTheme', next); } catch (e) {}
});
initTheme();

DATA.products.forEach(function(p){
  byUnit[p.unitId] = {name:p.name, unit:p.unit, price:p.price, parentName:null};
  (p.variants||[]).forEach(function(v){
    byUnit[v.unitId] = {name:p.name + ' — ' + v.name, unit:v.unit, price:v.price, parentName:p.name};
  });
});

document.getElementById('storeName').textContent = DATA.store;
document.getElementById('storeSub').textContent = 'Katalog pesanan · diperbarui ' + DATA.generatedAt;

function rp(n){
  var s = Math.round(n).toString();
  var out = '';
  for (var i=0;i<s.length;i++){
    if (i>0 && (s.length-i)%3===0) out += '.';
    out += s[i];
  }
  return 'Rp ' + out;
}

function fmtQty(q){
  return (q % 1 === 0) ? String(q) : String(q);
}

function cartCount(){
  var n = 0;
  for (var k in cart) n += cart[k];
  return n;
}
function cartTotal(){
  var t = 0;
  for (var k in cart) { var u = byUnit[k]; if (u) t += u.price * cart[k]; }
  return t;
}

function setQty(unitId, qty){
  if (qty <= 0) delete cart[unitId]; else cart[unitId] = qty;
  // Update HANYA stepper baris yang berubah (bukan renderList() penuh) —
  // katalog bisa ratusan/ribuan baris, membangun ulang semuanya tiap tap
  // +/- sangat berat di HP low-end padahal cuma satu angka yang berubah.
  var old = document.querySelector('#list [data-unit="'+unitId+'"]');
  if (old) old.replaceWith(buildStepper(unitId, qty));
  renderCartBar();
  if (sheetOpen) renderCartSheet();
}

function renderList(){
  var q = document.getElementById('q').value.trim().toLowerCase();
  var list = document.getElementById('list');
  var frag = document.createDocumentFragment();
  var shown = 0;
  DATA.products.forEach(function(p){
    var variants = p.variants || [];
    var nameMatch = !q || p.name.toLowerCase().indexOf(q) >= 0;
    var matchedVariants = variants.filter(function(v){
      return !q || v.name.toLowerCase().indexOf(q) >= 0;
    });
    if (q && !nameMatch && matchedVariants.length === 0) return;
    shown++;

    var row = document.createElement('div');
    row.className = 'prow';

    if (variants.length > 0) {
      var det = document.createElement('details');
      det.dataset.pid = p.id;
      // Tetap terbuka sampai user sendiri yang tap induk untuk menutup —
      // openState dicek dulu supaya tidak collapse tiap kali render() ulang
      // (mis. selesai tambah qty varian).
      if (openState.hasOwnProperty(p.id)) {
        det.open = openState[p.id];
      } else if (q && matchedVariants.length > 0) {
        // Auto-expand: query aktif & cocok lewat nama varian (bukan nama induk).
        det.open = true;
      }
      det.addEventListener('toggle', function(){
        openState[this.dataset.pid] = this.open;
      });
      var sum = document.createElement('summary');
      sum.innerHTML =
        '<div class="prow-main">' +
          '<div class="prow-info">' +
            '<div class="prow-name">'+esc(p.name)+'</div>' +
            '<div class="prow-meta">'+variants.length+' varian · mulai '+rp(Math.min.apply(null, variants.map(function(v){return v.price;}).concat([p.price])))+'</div>' +
          '</div>' +
          '<button class="chev" type="button"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><path d="M6 9l6 6 6-6"/></svg></button>' +
        '</div>';
      det.appendChild(sum);
      var vlist = document.createElement('div');
      vlist.className = 'vlist';
      var displayVariants = q ? matchedVariants : variants;
      displayVariants.forEach(function(v){
        var qty = cart[v.unitId] || 0;
        var vr = document.createElement('div');
        vr.className = 'vrow' + ((q && matchedVariants.indexOf(v) >= 0) ? ' vmatch' : '');
        vr.innerHTML =
          '<div class="vrow-info">'+esc(v.name)+
            '<div class="vrow-price">'+rp(v.price)+' /'+esc(v.unit)+'</div></div>';
        vr.appendChild(buildStepper(v.unitId, qty));
        vlist.appendChild(vr);
      });
      det.appendChild(vlist);
      row.appendChild(det);
    } else {
      var qty = cart[p.unitId] || 0;
      var main = document.createElement('div');
      main.className = 'prow-main';
      main.innerHTML =
        '<div class="prow-info"><div class="prow-name">'+esc(p.name)+'</div>' +
          '<div class="prow-meta">'+rp(p.price)+' /'+esc(p.unit)+'</div></div>';
      main.appendChild(buildStepper(p.unitId, qty));
      row.appendChild(main);
    }
    frag.appendChild(row);
  });
  // Bangun semua baris di DocumentFragment dulu (di luar DOM aktif), baru
  // ditempel sekali di akhir — mencegah reflow bertahap per baris.
  list.innerHTML = '';
  if (shown === 0) {
    list.innerHTML = '<div class="empty">Produk "'+esc(q)+'" tidak ditemukan.</div>';
  } else {
    list.appendChild(frag);
  }
}

function buildStepper(unitId, qty){
  var wrap = document.createElement('div');
  wrap.dataset.unit = unitId;
  if (qty > 0) {
    wrap.className = 'stepper';
    wrap.innerHTML =
      '<button type="button" data-act="dec" data-id="'+unitId+'">−</button>' +
      '<span class="n">'+qty+'</span>' +
      '<button type="button" data-act="inc" data-id="'+unitId+'">+</button>';
  } else {
    var btn = document.createElement('button');
    btn.className = 'add-btn';
    btn.type = 'button';
    btn.dataset.act = 'inc';
    btn.dataset.id = unitId;
    btn.textContent = 'Pilih';
    wrap.appendChild(btn);
    return wrap;
  }
  return wrap;
}

document.getElementById('list').addEventListener('click', function(e){
  var btn = e.target.closest('button[data-act]');
  if (!btn) return;
  e.preventDefault();
  var id = btn.dataset.id;
  var cur = cart[id] || 0;
  setQty(id, btn.dataset.act === 'inc' ? cur + 1 : cur - 1);
});

function renderCartBar(){
  var n = cartCount();
  var c = document.getElementById('cbCount');
  c.textContent = n;
  c.className = 'cb-count' + (n === 0 ? ' empty' : '');
  document.getElementById('cbLbl').textContent = n === 0 ? 'Belum ada barang dipilih' : n + ' barang dipilih';
  document.getElementById('cbTotal').textContent = rp(cartTotal());
  document.getElementById('cbView').disabled = n === 0;
}

function renderCartSheet(){
  var wrap = document.getElementById('cartItems');
  wrap.innerHTML = '';
  var ids = Object.keys(cart);
  if (ids.length === 0) {
    wrap.innerHTML = '<div class="empty">Keranjang kosong.</div>';
  }
  ids.forEach(function(id){
    var u = byUnit[id]; if (!u) return;
    var qty = cart[id];
    var row = document.createElement('div');
    row.className = 'citem';
    row.innerHTML =
      '<div class="ci-info"><div class="ci-name">'+esc(u.name)+'</div>' +
        '<div class="ci-price">'+qty+' '+esc(u.unit)+' × '+rp(u.price)+' = '+rp(u.price*qty)+'</div></div>';
    row.appendChild(buildStepper(id, qty));
    wrap.appendChild(row);
  });
  document.getElementById('sheetTotal').textContent = rp(cartTotal());
}

document.getElementById('cartItems').addEventListener('click', function(e){
  var btn = e.target.closest('button[data-act]');
  if (!btn) return;
  var id = btn.dataset.id;
  var cur = cart[id] || 0;
  setQty(id, btn.dataset.act === 'inc' ? cur + 1 : cur - 1);
});

function render(){ renderList(); renderCartBar(); if (sheetOpen) renderCartSheet(); }

// Debounce ~120ms — tiap huruf diketik memicu renderList() yang membangun
// ulang SELURUH daftar produk; tanpa debounce ini kerja berat berulang di
// setiap huruf, dampaknya paling besar untuk performa di HP low-end.
var searchTimer = null;
document.getElementById('q').addEventListener('input', function(){
  clearTimeout(searchTimer);
  searchTimer = setTimeout(renderList, 120);
});

function openSheet(){
  sheetOpen = true;
  renderCartSheet();
  document.getElementById('scrim').classList.add('show');
  document.getElementById('sheet').classList.add('show');
}
function closeSheet(){
  sheetOpen = false;
  document.getElementById('scrim').classList.remove('show');
  document.getElementById('sheet').classList.remove('show');
}
document.getElementById('cbView').addEventListener('click', openSheet);
document.getElementById('sheetClose').addEventListener('click', closeSheet);
document.getElementById('scrim').addEventListener('click', closeSheet);

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
    codeParts.push(id + '=' + qty);
    var key = u.parentName || u.name;
    (byParent[key] = byParent[key] || []).push({name:u.name, unit:u.unit, qty:qty, isChild: !!u.parentName});
  });
  Object.keys(byParent).forEach(function(k){
    var rows = byParent[k];
    if (rows.length === 1 && !rows[0].isChild) {
      lines.push(rows[0].name + ' ' + rows[0].unit + ' × ' + fmtQty(rows[0].qty));
    } else {
      lines.push(k);
      rows.forEach(function(r){
        var label = r.isChild ? r.name.split(' — ').slice(1).join(' — ') : r.name;
        lines.push('  > ' + label + ' ' + r.unit + ' × ' + fmtQty(r.qty));
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

function showToast(msg){
  var t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  setTimeout(function(){ t.classList.remove('show'); }, 2000);
}

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

document.getElementById('waBtn').addEventListener('click', function(){
  if (cartCount() === 0) return;
  var text = buildOrderText();
  copyText(text);
  var num = (DATA.waNumber || '').replace(/[^0-9]/g, '');
  var url = 'https://wa.me/' + num + '?text=' + encodeURIComponent(text);
  showToast('Teks pesanan disalin — tempel bila perlu');
  window.open(url, '_blank');
});

document.getElementById('copyBtn').addEventListener('click', function(){
  if (cartCount() === 0) { showToast('Pilih barang dulu'); return; }
  var ok = copyText(buildOrderText());
  showToast(ok ? 'Teks pesanan disalin' : 'Gagal menyalin — salin manual dari WhatsApp');
});

render();
</script>
</body>
</html>
''';
