# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 8 Juli 2026 (checkbox kembalian di struk + animasi
expand kolom cari kasir — commit `632a836`)._

---

## Di Mana Kita Sekarang

### Sesi terbaru (commit `632a836`) — 2 fitur independen
1. **Checkbox "kembalian sudah diambil"** di `receipt_screen.dart` —
   kolom baru `transactions.changeTaken` (`schemaVersion` 8->9, `BoolColumn`
   default false). Baris "Kembalian" diganti widget `_ChangeTakenRow`
   (checkbox + label + nominal, tap di mana pun pada baris men-toggle).
   `_toggleChangeTaken()` langsung `db.update(transactions)...write(...)`
   — MURNI per-perangkat, TIDAK ikut LAN sync (konsisten dengan pola
   `strukNote`/`internalNote` yang juga cuma diedit lokal setelah nota
   dibuat — `transactions` ada di `appendOnlyTables`, sync tidak pernah
   mengirim ulang baris yang sudah ada). Disembunyikan (`onChanged: null`)
   untuk nota void.
2. **Kolom cari kasir expand/collapse** — `_KasirTopbar` di
   `kasir_screen.dart` diubah dari `StatelessWidget` jadi `StatefulWidget`
   (`_KasirTopbarState`). State `_expanded` MURNI mengikuti
   `searchFocus.hasFocus` lewat listener (bukan bool terpisah) — jadi
   collapse/expand SELALU sinkron dengan fokus asli field, tidak bisa
   "nyasar". Layout: `LayoutBuilder` + `Stack` (`clipBehavior: Clip.none`
   supaya label tombol seperti "Antrian" tidak terpotong) — tombol-tombol
   topbar di `Positioned(right:0)` dengan `AnimatedOpacity`+`IgnorePointer`,
   field cari di `AnimatedPositioned(left:0, width: expanded ? maxW :
   128)` dengan `Container(color: cs.surface)` di baliknya (solid, bukan
   transparan) supaya BENAR-BENAR menimpa tombol, bukan cuma memotong tata
   letak. Tombol x (`suffixIcon`) hanya render saat `_expanded`;
   `_onClearOrShrink()`: kosong → `searchFocus.unfocus()` (memicu collapse
   lewat listener yang sama), berisi → `clear()` + `onSearch('')` TANPA
   unfocus. Collapse-dari-luar: `Listener(behavior: translucent,
   onPointerDown: unfocus)` + `NotificationListener<ScrollStartNotification>`
   membungkus SELURUH body di bawah topbar (banner + panel tahan + daftar
   produk) — pakai `Listener` bukan `GestureDetector` supaya tap tetap
   diteruskan normal ke kartu produk (tidak "dicuri" duluan oleh gesture
   arena). Teks yang sudah diketik TIDAK PERNAH dihapus oleh jalur
   collapse-dari-luar — hanya `_onClearOrShrink()` (tombol x saat kosong,
   yang memang textnya sudah kosong) atau eksplisit clear (x saat berisi)
   yang menyentuh `searchCtrl`.

Test baru sesi ini: migrasi v8->v9 (`test/migration_v9_test.dart`, Tier 1,
revert-verify kolom `change_taken`), toggle checkbox kembalian
(`test/receipt_change_taken_test.dart`, Tier 2 widget, revert-verify tulis
DB), 4 skenario kolom cari (`test/kasir_search_expand_test.dart`, Tier 2
widget: collapsed-default, expand+x-muncul, x-saat-berisi-vs-kosong,
tap-di-luar-collapse-tanpa-hapus-teks) — semua lolos revert-sementara.
`flutter analyze` bersih, **131 test hijau**.

### Sesi sebelumnya (commit `6dedc80`) — 3 perbaikan/fitur kecil independen
1. **Modal Bayar**: chip "Bayar Nanti" (dulu campur di baris Metode
   Pembayaran) sekarang jadi tombol dedicated sendiri di `payment_screen.dart`
   — 2 tombol di bar bawah: `FilledButton` hijau (`Color(0xFF22C55E)`)
   "Bayar {total}" + `FilledButton` merah (`scheme.error`) "Bayar Nanti".
   `_onBayarNantiPressed()` set `_selectedMethodType='tempo'` lalu langsung
   `_confirm()` — TIDAK ada dialog konfirmasi tambahan (sama seperti alur
   lama, cuma dipicu tombol berbeda).
2. **Harga Lain** (fitur baru — tabel `alt_prices`, `schemaVersion` 7->8):
   harga alternatif berlabel bebas per satuan produk (mis. "Harga Toko A" =
   3000), BEDA dari `price_tiers` (qty-tier) — murni pilihan manual, tidak
   pernah dipilih otomatis oleh `PriceService.resolvePrice`. Dikelola di
   `produk_form_screen.dart` (section "Harga Lain", pola sama persis dengan
   "Harga Grosir" — delete-then-reinsert saat save). Tampil sebagai chip
   tap-untuk-pakai di `ItemEntrySheet` (`getAltPrices()`, disatukan dengan
   chip satuan & tier grosir yang sudah ada, lewat `_applyTierPrice()` yang
   sama). Terdaftar sebagai master data satu-arah (host→klien) di
   `lan_sync_service.dart`/`dumpSince`/`_allTables` (backup), mengikuti pola
   `price_tiers` PERSIS (kalau nanti nambah tabel master data baru lagi, ikuti
   4 titik ini: `@DriftDatabase(tables:...)`, `_allTables`, `masterData` di
   `dumpSince`, `_kTableLabels` di `lan_sync_service.dart`).
3. **Katalog Pesanan (eksperimental)** — 3 poles UX di `order_page_service.dart`
   template: (a) dropdown varian pakai `openState` per productId + event
   `toggle` supaya TIDAK collapse tiap `render()` ulang (dulu nutup lagi tiap
   nambah qty varian) — hanya nutup kalau user sendiri tap ringkasan/induk;
   (b) tombol toggle terang/gelap manual (`#themeBtn`, `data-theme` attr +
   `localStorage`), menang atas `prefers-color-scheme` di kedua arah; (c)
   font total diperbesar (`.cb-total` 16->21px, `.grand .gv` 20->27px).
   **Perilaku JS ini TIDAK bisa dites lewat `flutter test`** (JS tidak
   dieksekusi) — diverifikasi manual pakai Chromium headless (Playwright,
   `/opt/pw-browsers/chromium`) generate HTML sungguhan lalu klik-klik. Kalau
   nanti ubah template ini lagi, verifikasi ulang dengan cara yang sama
   (lihat riwayat percakapan sesi ini untuk skrip contoh) — jangan cuma
   percaya `flutter analyze`/`flutter test` hijau, itu tidak menyentuh JS
   sama sekali.

Test sesi itu: migrasi v7->v8 (`test/migration_v8_test.dart`, Tier 1,
revert-verify tabel `alt_prices` benar-benar dibuat), `saveProduct` harga
alternatif (`test/alt_prices_test.dart`, Tier 1, revert-verify replace +
cascade-delete saat satuan dihapus), layout 2-tombol Bayar
(`test/payment_screen_buttons_test.dart`, Tier 2 widget, revert-verify label
hilang tertangkap).

### Fitur eksperimental Katalog Pesanan (branch `claude/order-html-eksperimental`)
Lengkap dua fase, menutup alur ujung-ke-ujung: generate HTML →
kirim WA manual → pelanggan pilih barang → kasir tempel balik ke keranjang.

### Fase 1 — generator HTML (commit `e422639`, `dc9c3ef`)
- `lib/core/services/order_page_service.dart` — `OrderPageService.
  generateHtml({db, storeName, storeWhatsapp})` → satu file HTML
  self-contained (CSS+JS inline, tanpa CDN/font eksternal, tanpa hosting —
  keputusan eksplisit user: kirim manual via WA). Pelanggan pilih barang
  (termasuk varian, UX arrow-tap + auto-expand saat search cocok) lalu tekan
  "Kirim via WhatsApp" — teks pesanan berformat manusia-bisa-baca + baris
  kode mesin `#PSN:<productUnitId>=<qty>;...` di akhir.
- `lib/features/pengaturan/order_share_screen.dart` — layar
  `/pengaturan/katalog-pesanan` (badge "Eksperimental", owner-only), generate
  → `Share.shareXFiles` (pola sama seperti share struk/katalog).
- 6 test (`test/order_page_service_test.dart`) menemukan & membuktikan 2 bug
  nyata sebelum dianggap selesai: varian bocor jadi baris induk terpisah
  (`searchProducts()` tidak menyaring varian, beda dari `watchProducts()`),
  dan XSS lewat data JSON yang belum di-escape `"</"` → `"<\/"` di dalam
  `<script>`.

### Fase 2 — parser & UI Tempel Pesanan (commit `ef9ab12`)
- `lib/core/services/order_parser_service.dart` — `OrderParserService.
  parse({db, text})` → `ParsedOrder`. Regex-extract baris `#PSN:...`, lookup
  tiap `productUnitId` ke DB, **resolve harga LIVE via `PriceService`**
  (bukan angka di teks — katalog terkirim bisa sudah basi beberapa hari),
  dedup unitId dobel (gabung qty, bukan baris ganda), barang yang sudah
  dihapus/dinonaktifkan masuk `ParsedOrder.notFound` tanpa menggagalkan
  baris valid lain. Ikut extract `Nama:`/`HP:`/`Catatan:` (nilai `-` atau
  kosong dianggap null).
- `lib/features/kasir/widgets/paste_order_sheet.dart` — `PasteOrderSheet`
  (bottom sheet): tempel teks → preview daftar item + notFound → isi
  keranjang. `_ensureParentInCart()` sengaja DUPLIKAT self-contained (bukan
  reuse method private `kasir_screen.dart`) — sesuai keputusan user sesi
  sebelumnya bahwa kasir utama TIDAK boleh disentuh oleh fitur eksperimental
  ini, hanya ditambah tombol baru.
- `lib/features/kasir/kasir_screen.dart` — perubahan ADDITIF saja: tombol
  baru "Tempel Pesanan" (`Icons.content_paste_go_rounded`) di topbar,
  hanya tampil di mode kasir normal (bukan mode katalog/tambah-belanjaan).
- 6 test parser (Tier 1 DB, `test/order_parser_service_test.dart`) + 1 test
  layout (Tier 2 widget, `test/kasir_topbar_layout_test.dart`, render
  `KasirScreen` di lebar 360dp) membuktikan tombol baru TIDAK memicu
  `RenderFlex` overflow — CLAUDE.md mencatat topbar kasir historis rawan
  kasus ini. Kedua kelas regresi (dedup dimatikan, lebar label dipaksa 200)
  diverifikasi lewat revert-sementara: tanpa fix, test gagal dengan pesan
  yang sesuai; dengan fix, hijau lagi.

### Yang SENGAJA belum dibangun (deferred, bukan lupa)
- Hosting "link hidup" (GitHub Pages dkk) untuk Katalog Pesanan — user pilih
  TIDAK sekarang (kirim manual via WA). Opsi & tradeoff sudah didiskusikan
  kalau nanti mau dipertimbangkan ulang.
- UX varian (arrow-tap + auto-expand-on-search) hanya ada di HTML generated,
  belum diseragamkan ke kasir utama (yang masih pakai long-press). Perubahan
  terpisah, perlu dikonfirmasi ulang user kalau mau diselaraskan.
- Belum ada PR untuk branch `claude/order-html-eksperimental` — menunggu
  instruksi user.

## Ringkasan Sesi Audit Sebelumnya (masih berlaku, tidak diulang detail)
14 bug hasil audit kode menyeluruh sudah diperbaiki & dirilis sebagai
v2.1.1+3 (lihat CHANGELOG untuk daftar commit `7d1fc6f`, `81f1af6`,
`c1bafd7`, `b6fefbe`). PR #2 sudah di-merge ke `main`. Build APK v2.1.1+3
sukses (dev pre-release di GitHub Releases).

## Temuan yang SENGAJA Belum Diperbaiki (kandidat diskusi, dari audit)
- **Multi-satuan + varian bercampur**: invariant `storedQty induk = base +
  Σvarian` ambigu bila satu produk punya ≥2 baris satuan non-varian di
  keranjang. Butuh refactor atribusi varian per-baris — jangan disentuh
  tanpa keputusan user.
- Tombol minus di kartu produk (`_decrementProduct`) selalu mengurangi baris
  satuan PERTAMA bila produk ada di keranjang dengan >1 satuan.
- **Upload sync klien→host masih full-dump** (sengaja — antrian approval
  host hanya di memori; watermark upload butuh mekanisme ACK approve dari
  host, pekerjaan tersendiri).
- Fitur "hantu" yang tabel-nya ada tapi tanpa UI: `expenses` (paling layak
  dibangun — lihat saran fitur), `suppliers/purchases/purchase_items`,
  `customer_groups/customer_group_prices`.

## Saran Fitur dari Audit (menunggu keputusan user, urut prioritas)
1. Pencatatan pengeluaran (tabel/sync/izin sudah ada → laba bersih di laporan).
2. Tukar poin loyalty di layar bayar (tipe ledger `redeem` sudah disiapkan).
3. Pilih metode bayar saat pelunasan hutang (kini hardcode 'tunai' di
   Tambah Bayar & pelunasan gabung nota).
4. Peringatan stok menipis (ambang minimum per satuan).
5. Layar "Buku Hutang" terpusat (siapa berhutang, umur hutang, aksi lunasi).
6. Backup otomatis terjadwal + pengingat "backup terakhir X hari lalu".
7. Edit/hapus metode pembayaran (kini hanya tambah + on/off).
8. Rekap tutup kasir harian (uang seharusnya di laci vs fisik).

## Keputusan Penting yang Masih Berlaku
- Cart meta tab = shrink-wrap kiri, **bukan** full-width.
- Animasi scan yang dipilih = **Opsi E** (garis pulse hijau), dari 8 opsi.
- Referensi proyek tinggal di `docs/reference/` (jangan hapus) — termasuk
  `Mockup.zip` & `Contoh_Dataset.rar` yang masih ada & dipakai aktif.
- Ekspor pakai `FilePicker.saveFile`, bukan `Printing.sharePdf`.
- Katalog Pesanan (eksperimental): tanpa hosting, kasir utama tidak
  disentuh (hanya tombol baru ditambah), Fase 1 (HTML) + Fase 2 (parser +
  Tempel Pesanan) sudah selesai keduanya.
- Harga Lain (`alt_prices`) TIDAK pernah dipilih otomatis oleh
  `PriceService.resolvePrice` — murni manual/tap, beda filosofi dari
  `price_tiers` (qty-tier) yang auto-resolve berdasar qty. Jangan campur
  logikanya kalau nanti ada perubahan price resolver.

## Menggantung / Kandidat Berikutnya
- Saran fitur audit di atas menunggu keputusan user.
- Belum ada PR untuk branch `claude/order-html-eksperimental` — menunggu
  instruksi user (buka PR / hal lain).
- Kalau Katalog Pesanan terbukti kepakai di lapangan: pertimbangkan lagi
  opsi hosting "link hidup" atau penyeragaman UX varian ke kasir utama
  (keduanya sengaja ditunda, lihat di atas).

## Preferensi User
- Untuk fitur bervisual (mis. animasi), **usulkan beberapa opsi desain dulu**
  sebelum implementasi.
- Bahasa komunikasi & teks UI: Indonesia.
- Hati-hati agar perubahan tidak merusak logika/alur aplikasi yang sudah ada.
- Untuk perbaikan bug: laporkan dulu dengan contoh kasus + severity, tawarkan
  metode fix via poll, baru eksekusi sesuai konfirmasi.
- Untuk fitur baru berisiko/besar: diskusikan cakupan dulu (boleh
  dipersempit dari proposal awal), baru eksekusi setelah "eksekusi semua"
  atau konfirmasi serupa.
