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
      'tombol Kosongkan terpisah, merah, di KIRI tombol utama, konfirmasi inline',
      () {
    expect(html, contains('id="mbClear"'));
    expect(html, contains('aria-label="Kosongkan pesanan"'));
    expect(html, contains('<span>Kosongkan pesanan</span>'));
    expect(html, contains(".mb-clear{"));
    expect(html, contains('background:#D64545'));
    // Halaman awal: tombol hapus DI KIRI tombol utama (urutan DOM).
    expect(
        html.indexOf('id="mbClear"'), lessThan(html.indexOf('id="mainBtn"')));
    // Header halaman Pesanan: clearCart() tetap popup (showConfirm).
    final body = html.substring(html.indexOf('function clearCart(){'),
        html.indexOf("document.getElementById('clearCartBtn')"));
    expect(body, contains('showConfirm('));
  });

  test('konfirmasi hapus INLINE Ya (merah 1/4 kiri) / Tidak (netral 3/4)', () {
    expect(html, contains('function setClearConfirm(on)'));
    expect(html, contains('setClearConfirm(true);'));
    expect(html, contains("if (clearConfirm) { doClearCart(); return; }"));
    expect(
        html,
        contains(
            "if (clearConfirm) { setClearConfirm(false); return; } // tombol \"Tidak\""));
    expect(html, contains('<span class="mb-q">Kosongkan pesanan?</span>'));
    expect(html, contains('<span class="mb-no">Tidak</span>'));
    expect(html, contains('#mainBtnWrap.mb-confirm .mb-clear{width:25%;'));
    expect(html,
        contains('#mainBtnWrap.mb-confirm .mainbtn{background:var(--field);'));
    // Berakhir hanya saat Ya/Tidak, pesanan kosong, atau pindah ke Pesanan —
    // TIDAK ada pembatalan otomatis (timer) maupun karena scroll/ketik.
    expect(html, contains('if (n === 0) setClearConfirm(false);'));
    expect(html, contains('function openSheet(){\n  setClearConfirm(false);'));
    final confirm = html.substring(html.indexOf('function setClearConfirm(on)'),
        html.indexOf("document.getElementById('mbClear').addEventListener"));
    expect(confirm, isNot(contains('setTimeout(function(){ setClearConfirm')));
  });

  test(
      'scroll ke bawah: keterangan Kosongkan menyusut (sisa ikon); naik: muncul',
      () {
    expect(html, contains("listEl.addEventListener('scroll'"));
    expect(html, contains("wrap.classList.add('mb-collapsed')"));
    expect(html, contains("wrap.classList.remove('mb-collapsed')"));
    expect(html, contains('#mainBtnWrap.mb-collapsed .mb-clear{width:56px;'));
    expect(
        html,
        contains(
            '#mainBtnWrap.mb-collapsed .mb-clear span{max-width:0;opacity:0;}'));
    // Ikon lebih besar, keterangan lebih kecil.
    expect(html, contains('.mb-clear svg{width:20px;height:20px;'));
    expect(html, contains('font-size:9.5px;font-weight:700;line-height:1.15;'));
  });

  test(
      'halaman Pesanan: tombol Kosongkan menyusut ke lebar 0 (animasi menyatu)',
      () {
    expect(
        html,
        contains(
            '#app.order-mode .mb-clear{width:0;margin-right:0;padding:0;opacity:0;pointer-events:none;}'));
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
    // Hapus di KIRI, Tambah di kanan.
    expect(html.indexOf('id="itemRemoveBtn"'),
        lessThan(html.indexOf('id="itemAddBtn"')));
    expect(html, contains('<span>Hapus dari pesanan</span>'));
    // Belum ada di pesanan -> Hapus menyusut ke 0 (Tambah selebar penuh).
    expect(
        html,
        contains(
            '.im-actions.nodel .mb-clear{width:0;margin-right:0;padding:0;opacity:0;pointer-events:none;}'));
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

  test('modal produk: X lingkaran merah di pojok kanan atas', () {
    expect(html, contains('.sheet-x{position:absolute;top:10px;right:14px;'));
    expect(html, contains('border-radius:50%;background:#D64545;color:#fff'));
  });

  test('modal produk: geser ke bawah menutup (touch non-pasif, tanpa refresh)',
      () {
    expect(html, contains("sheet.addEventListener('touchmove'"));
    expect(html, contains('{passive: false}'));
    expect(html, contains('e.preventDefault()'));
    expect(html, contains('body.scrollTop <= 0'));
    expect(html, contains('sheet.offsetHeight * 0.3'));
    expect(html, contains('overscroll-behavior-y:contain'));
    // Pull-to-refresh hanya dimatikan SELAMA modal terbuka.
    expect(
        html,
        contains(
            'html.modal-open,html.modal-open body{overscroll-behavior-y:none;}'));
    expect(
        html, contains("document.documentElement.classList.add('modal-open')"));
    expect(html,
        contains("document.documentElement.classList.remove('modal-open')"));
  });

  test('draf modal persisten di localStorage (kunci versi katalog + TTL)', () {
    expect(html, contains("DRAFT_KEY = 'posOrderItemDraft'"));
    expect(html, contains('d.generatedAt !== DATA.generatedAt'));
    expect(html, contains('> CART_TTL_MS'));
    expect(html, contains('function noteDraft()'));
    // Dibersihkan saat tambah/hapus/ubah qty/kosongkan.
    expect(html, contains('dropDraft(unitId);\n  closeItemModal();'));
    expect(html, contains('localStorage.removeItem(DRAFT_KEY)'));
    final setQty = html.substring(html.indexOf('function setQty(unitId, qty){'),
        html.indexOf('function refreshProwControls'));
    expect(setQty, contains('dropDraft(unitId);'));
  });

  test(
      'angka total berputar (roll) hanya utk amount besar, bukan badge/harga daftar',
      () {
    expect(html, contains('function rollSet(el, text)'));
    expect(html, contains("rollSet(document.getElementById('mbTotal')"));
    expect(html, contains("rollSet(document.getElementById('sheetTotal')"));
    expect(html, contains("rollSet(document.getElementById('itemSubtotal')"));
    // Arah acak, hanya transform, hormati reduced-motion.
    expect(html, contains('Math.random() < 0.5'));
    expect(html, contains('prefers-reduced-motion: reduce'));
    expect(html, contains("transition = 'transform .6s"));
    // Elemen total memakai kelas roll; badge qty tetap animasi bounce lama.
    expect(html, contains('class="mb-total roll" id="mbTotal"'));
    expect(html, contains("document.getElementById('mbBadge')"));
    // Panggilan pertama = tanpa animasi (render awal).
    expect(html, contains('if (old === undefined || ROLL_REDUCED)'));
  });

  test(
      'redesign modal (Mockup B): hero, harga raksasa, segmen satuan, stepper besar',
      () {
    expect(html, contains('class="im-hero"'));
    expect(html, contains('id="itemEmoji"'));
    expect(html, contains('id="itemCat"'));
    expect(html, contains('class="im-price" id="itemPriceDisplay"'));
    expect(
        html,
        contains(
            '.im-price{text-align:center;margin-top:12px;font-family:var(--serif);font-size:38px;'));
    expect(html, contains('class="im-seg" id="itemUnitChips"'));
    expect(html, contains('.im-qty-input{width:96px;'));
    expect(
        html,
        contains(
            'font-size:54px;line-height:1;font-weight:600;font-family:var(--serif)'));
    expect(html, contains('id="itemEq"'));
    expect(html, contains('<label for="itemNote">Catatan</label>'));
    // Sheet memakai permukaan kartu (otomatis ikut mode gelap).
    expect(
        html,
        contains(
            'background:var(--card);border-radius:30px 30px 0 0;z-index:21;'));
  });

  test(
      'segmen satuan: walk-through panah berdenyut tiap modal dibuka bila perlu digeser',
      () {
    expect(html, contains('id="itemSegHint"'));
    expect(html, contains('Geser untuk satuan/varian lainnya'));
    expect(html, contains('@keyframes arr-pulse'));
    // Dihitung SETIAP renderUnitChips (tiap modal dibuka), bukan sekali saja.
    expect(
        html,
        contains(
            "hint.classList.toggle('show', opts.length > 1 && wrap.scrollWidth > wrap.clientWidth + 2)"));
    expect(html, isNot(contains("localStorage.setItem('posSegHint")));
    // Harga besar ikut efek roll saat satuan berganti.
    expect(html, contains("rollSet(document.getElementById('itemPriceVal')"));
  });

  test(
      'redesign halaman Pesanan (Mockup B): kertas struk, baris titik-titik, TOTAL',
      () {
    expect(html, contains('class="paper-wrap"'));
    expect(html, contains('id="paperStore"'));
    expect(html, contains('conic-gradient(from -45deg at bottom'));
    expect(html, contains('class="paper-total"'));
    expect(html, contains('id="sheetTotal"'));
    expect(
        html,
        contains(
            'class="l1"><span class="q"></span><span class="nm"></span><span class="dots"></span>'));
    expect(html,
        contains('<div class="ofield"><label for="custName">Nama</label>'));
    expect(html, contains('<label for="custNote">Catatan (opsional)</label>'));
    expect(html, contains('class="copy-link" id="copyBtn"'));
    expect(html, contains('.page-order{background:var(--canvas);}'));
    // Struk memakai permukaan kartu -> otomatis ikut mode gelap.
    expect(html, contains('.paper{background:var(--card);'));
  });

  test(
      '"Tambah?" -> stepper: kata kecil berubah mulus jadi pil, satu baris terbuka',
      () {
    expect(html, contains('data-act="open">Tambah?</button>'));
    expect(
        html,
        contains(
            '.tbx.open .stp{max-width:140px;opacity:1;padding:3px;transform:scale(1);}'));
    expect(html, contains('.tbx.open .tb{max-width:0;opacity:0;'));
    expect(
        html, contains('transition:max-width .3s cubic-bezier(.3,1.25,.45,1)'));
    expect(html, contains('function setOpenRow(id)'));
    expect(
        html,
        contains(
            'openRowTimer = setTimeout(function(){ setOpenRow(null); }, 4000);'));
    // Baris disinkronkan di tempat (node persisten), bukan dibangun ulang.
    expect(html, contains('function syncCartRow(id, el)'));
    expect(html, contains('function removeCartRow(id)'));
    expect(html,
        contains("rollSet(el.querySelector('.s'), numOnly(u.price * qty))"));
    // - saat qty 1 menghapus langsung; ketuk nama membuka modal produk.
    expect(
        html, contains("setOpenRow(act === 'dec' && cur <= 1 ? null : id);"));
    expect(html, contains('if (p) openItemModal(p, id);'));
  });
}
