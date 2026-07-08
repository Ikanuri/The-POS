# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 7 Juli 2026 (Fase 1 fitur eksperimental Katalog Pesanan)._

---

## Di Mana Kita Sekarang

Setelah audit kode selesai (v2.1.1+3 sudah dirilis & di-build, lihat
riwayat commit untuk detail — `98db2/audit` di CHANGELOG), sesi ini mulai
membangun **fitur eksperimental baru: Katalog Pesanan** — turunan dari
proposal lama `docs/PROPOSAL_PERTIMBANGAN_BAROKAH_ORDER.md` ("Static HTML +
WhatsApp + Paste Parser"), tapi dengan cakupan yang jauh dipersempit sesuai
keputusan eksplisit user lewat diskusi + poll:

1. **Referensi visual**: pakai `docs/reference/Mockup.zip` (React JSX
   mockup) — dikonfirmasi ini memang cetak biru desain asli aplikasi
   (token warna `#C96442`, Hanken Grotesk + Newsreader identik dengan
   `AppTheme`). Tidak di-rebuild, hanya dijadikan acuan gaya visual untuk
   halaman baru.
2. **Cakupan dipersempit** ke HANYA: cart bar popup + keranjang + format
   teks pesanan siap kirim, semuanya di SATU file HTML self-contained
   (tanpa server/hosting — pilihan user: "kirim file WA manual").
3. **Hosting**: user pilih opsi B (tanpa hosting) dari 3 opsi yang
   ditawarkan (GitHub Pages / kirim manual / Netlify-Cloudflare). Jadi
   TIDAK ada link yang otomatis update — file digenerate ulang & dikirim
   manual tiap kali harga berubah.
4. **UX varian**: panah expand bisa langsung di-tap + auto-expand saat
   pencarian cocok — user pilih opsi B ("cukup di halaman order HTML
   saja") — **kasir utama TIDAK disentuh sama sekali**, tetap pakai
   long-press seperti sebelumnya.

### Yang sudah dibangun (commit `e422639`, branch `claude/order-html-eksperimental`)
- **`lib/core/services/order_page_service.dart`** — `OrderPageService.
  generateHtml({db, storeName, storeWhatsapp})` → `({String html, int
  productCount})`. Query katalog aktif (induk + varian, satuan dasar,
  harga tier minQty=1 via `PriceService`), suntik ke template HTML statis
  (CSS+JS inline, TANPA CDN/font eksternal — harus tetap terbuka sempurna
  walau HP pelanggan offline). Identitas baris pakai `productUnitId`
  (UUID), BUKAN `kodeProduk` (boleh kosong/tidak unik) — desain sengaja
  lebih robust dari proposal asli yang pakai `kodeProduk`.
- Format teks pesanan yang dihasilkan: baris manusia-bisa-baca + baris
  kode mesin `#PSN:<productUnitId>=<qty>;...` di akhir. **Kode mesin ini
  BELUM diparsing oleh apa pun** — murni disiapkan untuk Fase 2.
- **`lib/features/pengaturan/order_share_screen.dart`** — layar baru
  (`/pengaturan/katalog-pesanan`) dengan badge "Eksperimental" jelas,
  penjelasan cara kerja 4 langkah, tombol "Buat & Bagikan" yang generate
  HTML ke temp file lalu `Share.shareXFiles` (pola sama seperti share
  struk/katalog yang sudah ada).
- Entry point baru di `pengaturan_screen.dart`: section "Eksperimental"
  terpisah (hanya untuk owner), tidak mengubah section lain.
- Route baru `katalog-pesanan` di `app_router.dart`.
- **6 test baru** (`test/order_page_service_test.dart`) — Tier 1 DB murni.
  Menemukan & membuktikan **2 bug nyata** sebelum dianggap selesai (wajib
  revert-sementara per CLAUDE.md):
  1. `searchProducts()` TIDAK menyaring varian (beda dari `watchProducts`
     yang punya `.parentProductId.isNull()`) — varian sempat ikut muncul
     sebagai baris induk terpisah di katalog. **Fix**: filter manual
     `.where((p) => p.parentProductId == null)` di `_buildCatalogJson`.
  2. Data JSON yang disuntik ke dalam `<script>` belum di-escape `"</"` →
     `"<\/"` — nama toko yang kebetulan memuat `</script>` bisa menutup
     blok skrip lebih awal & membuat sisanya dieksekusi sebagai HTML/skrip
     baru (XSS). **Fix**: `dataJson.replaceAll('</', r'<\/')` sebelum
     disuntik. Catatan: `<title>` pakai escape HTML biasa (`_escapeHtml`,
     escape `&`/`<`/`>`) — BEDA dari escape untuk konteks `<script>`,
     jangan disamakan kalau menambah placeholder baru di template.

`flutter analyze` bersih, **112 test hijau** (106 lama + 6 baru).

### Yang SENGAJA belum dibangun (deferred, bukan lupa)
- **`OrderParserService`** (sisi kasir: baca teks pesanan → isi keranjang
  otomatis) — proposal asli menyebut ini "Fase 1", tapi user secara
  eksplisit mempersempit cakupan sesi ini ke HANYA generator HTML. Saya
  sempat menulis servicenya lalu **menghapusnya lagi** karena jadi kode
  mati tanpa UI pemanggil (bertentangan dengan prinsip audit kemarin).
  Kalau dilanjutkan: desain format `#PSN:<productUnitId>=<qty>;...` di
  `OrderPageService` sudah siap dipakai — parser tinggal regex-extract
  baris itu, lookup `productUnitId` ke DB, resolve harga LIVE lewat
  `PriceService` (JANGAN percaya angka di teks, katalog bisa basi),
  lalu bangun `CartItem[]`. Untuk varian, ingat invariant `storedQty
  induk = base + Σvarian` — perlu logika serupa `_ensureParentInCart` di
  `kasir_screen.dart` (tapi JANGAN import/pakai method private itu
  langsung — kasir utama sengaja tidak disentuh, tulis versi sendiri yang
  self-contained di file baru).
- **UX varian (arrow-tap + auto-expand-on-search)** hanya ada di HTML
  generated, belum di kasir utama. User sengaja pilih tidak menyentuh
  kasir utama sesi ini — kalau nanti mau diseragamkan, itu perubahan
  terpisah yang perlu dikonfirmasi ulang (kasir utama pola sekarang:
  long-press untuk expand, bukan tap-panah).
- Hosting "link hidup" (GitHub Pages dkk) — user pilih TIDAK sekarang.
  Opsi & tradeoff sudah didiskusikan & didokumentasikan kalau nanti mau
  dipertimbangkan ulang (lihat riwayat percakapan / proposal asli §6.7).

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
  disentuh, sisi parser/tempel-otomatis ditunda ke fase berikutnya.

## Menggantung / Kandidat Berikutnya
- **Katalog Pesanan Fase 2** (kalau Fase 1 terbukti kepakai): bangun
  `OrderParserService` + UI "Tempel Pesanan" di kasir. Lihat catatan
  desain di atas.
- Saran fitur audit di atas menunggu keputusan user.
- Belum ada PR untuk branch `claude/order-html-eksperimental` — menunggu
  instruksi user (buka PR / lanjut Fase 2 / hal lain).

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
