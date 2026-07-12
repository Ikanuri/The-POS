# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 12 Juli 2026 (sesi kembalian per-pembayaran + Buku
Hutang + Tambah Belanjaan, berlanjut ke sesi bugfix hari berikutnya, lalu
sesi lanjutan lagi — fix kalkulator + harga dasar/per-qty, lihat paragraf
baru di bawah).
**schemaVersion tetap 13** (semua fix sesi lanjutan ini murni logika, tidak
ada migrasi baru). Baseline sebelum sesi awal: 210 test hijau → **226 test
hijau** saat ini. Backlog Item 9-22 (PLAN.md) tetap 12/13 SELESAI (Item
17+21 — sync — masih sengaja ditunda, TIDAK berubah). **Item 23 masuk
PLAN.md** (lihat di bawah) — bug "Sisa Tagihan"/"Dibayar" + scope-scope
terkait yang masih menggantung.

**Sesi lanjutan (setelah `cd382ed`) — user lapor 4 poin sekaligus (screenshot
kalkulator + 3 permintaan tampilan/bug):**
1. Kalkulator kembalian PALSU (screenshot) — sudah dianalisis & dikonfirmasi
   sebagai bug NYATA yang SAMA dengan yang sudah dijelaskan di paragraf
   `cd382ed` di bawah (preview `_change`/`_shortfall` belum ikut
   `existingShortfall`) — SELESAI, PR #11 merged.
2. **Harga dasar di bawah nama produk (tab Produk) — SELESAI**
   (`b1141f6`). User pilih scope sempit: cuma harga satuan DASAR/utama
   (bukan semua satuan/tier). `getBaseUnitPrices()` baru di
   `app_database.dart` — 1 query JOIN (`product_units`+`price_tiers` pada
   `min_qty=1`+`is_base_unit=1`) untuk SEMUA produk sekaligus (hindari N+1
   per baris `ListView`), dipakai via `FutureProvider.autoDispose` di
   `produk_list_screen.dart`.
3. **Harga per-qty di baris item keranjang kasir — SELESAI** (`d703c0b`).
   User pilih pola "baris kecil di bawah nama item" (bukan cuma saat qty>1
   — SELALU tampil, konsisten). Baris satuan di `cart_sheet.dart`
   (`_CartItemTile`) sekarang `'${item.unitName} · ${formatRupiah(item.price)}'`
   dibungkus `Flexible`+ellipsis (defensif, pola overflow-prevention yang
   sudah dipakai berkali-kali sesi ini).
4. **Bug input harga di modal edit item kasir ("tidak bisa input nominal,
   cuma bisa hapus", "kasus ril di produk dengan 2 qty stepper di
   keranjang") — BELUM diperbaiki, MENGGANTUNG.** Sudah diinvestigasi
   (cek `_canOverride`/izin override harga, `ThousandsSeparatorFormatter`,
   pola stacking modal CartSheet→ItemEntrySheet, resolusi `targetId` untuk
   baris varian) — TIDAK ketemu akar masalah pasti dari baca kode statis
   saja. Sudah tanya user klarifikasi "2 qty stepper" itu maksudnya produk
   dengan varian (1 stepper produk utama + 1 stepper varian di modal yang
   sama), ATAU produk yang sama masuk keranjang di 2 satuan berbeda
   (mis. "Pak" & "Pcs") — **BELUM DIJAWAB user, jangan tebak-tebak fix
   sebelum jawaban masuk** (bug menyentuh alur pembayaran/harga, prioritas
   user selalu "laporkan dulu, jangan langsung eksekusi" untuk kelas bug
   ini).

**Gotcha widget test diperluas (harus di-broaden dari yang sudah ada di
CLAUDE.md):** ketemu lagi kasus drift `StreamProvider` bikin test HANG
selama 10 menit penuh (bukan langsung gagal) sebelum akhirnya muncul "Timer
still pending" — kali ini `ProdukListScreen` (`_lowStockCountProvider`
watch `watchLowStockCount()`) walau test-nya TIDAK memutasi DB sama sekali,
cuma BACA. CLAUDE.md yang ada baru menyebut kasus "yang MEMUTASI db" — pada
praktiknya SEMUA widget test layar yang punya StreamProvider drift butuh
`drain()` di akhir test, bukan cuma yang mutasi. Sempat salah diagnosa
sebagai lock/contention proses `flutter test` overlap (nyaris `kill -9` PID
hasil `ps aux | grep`, DITOLAK tool-permission karena pattern-matched PID
discovery tidak masuk exception "Session-Created Job Cleanup") sebelum
akhirnya lihat output asli test yang gagal dan ketemu akar masalah
sebenarnya.

**Temuan UX susulan dari user (bandingkan lagi dgn Griyo POS, `765734e`):**
saat Tambah Belanjaan pada nota yang MASIH kurang bayar (mis. sisa 5.000
dari penambahan sebelumnya), kalkulator bayar The POS hanya menampilkan
"Total = harga item baru" (mis. 20.000), sementara Griyo menampilkan
akumulatif (25.000 = 20.000 + sisa 5.000). Matematika The POS BENAR
(hasil akhir sama, sudah diverifikasi), tapi bisa MENYESATKAN kasir —
disangka "Total" kalkulator = semua yang perlu ditagih. User pilih
"tampilkan, atau akumulatifkan jika lebih efisien". Keputusan implementasi:
**TAMPILKAN sebagai info terpisah** ("+ Sisa tagihan sebelumnya", nominal
merah, pola sama seperti info "Pakai kembalian" yang sudah ada), BUKAN
diakumulasi ke `_total` — alasan: `_total` mengalir ke `allocateCartTotal`
(alokasi proporsional diskon/pembulatan per-item), menggabungkan sisa lama
ke situ akan mendistorsi harga item susulan yang tercatat. Sumber angka:
`netRemainingOwed()` (helper yang sama dari fix Sisa Tagihan) atas nota
asli + payment rows-nya, dihitung di `_load()` payment_screen.dart saat
mode tambah belanjaan.

**Feedback langsung dari user setelah PR #9 merge (`88c8deb`):** "Jadi
kasir masih harus menjumlah manual dan mengira ngira?" — benar, versi
awal cuma tampilkan 2 baris terpisah (Total item baru + Sisa sebelumnya)
tanpa hasil jumlahnya. Ditambah baris **"Total yang perlu ditagih"**
(bold, warna sama seperti Sisa Tagihan) = `widget.total + widget.
existingShortfall!` — dihitung langsung di `build()` (bukan state baru),
kasir tinggal baca angka jadi, tidak perlu jumlah manual sama sekali.
`_total` (yang dipakai `allocateCartTotal`) tetap tidak disentuh — baris
ini murni turunan tampilan.

**User verifikasi mandiri dgn screenshot (`cd382ed`), nemu bug baru:**
setelah tap "Total yang perlu ditagih" lalu ketik PERSIS angka itu di
kalkulator, pill "Kembalian" tetap muncul PALSU sebesar `existingShortfall`
(mis. bayar 84.400 pas, tapi pill nunjuk "Kembalian Rp 39.600"). Struk
setelah dikonfirmasi TERNYATA benar (tidak ada kembalian tersimpan,
matches `_computePaymentChangeGiven`) — jadi bug ini murni di PREVIEW
kalkulator, bukan data tersimpan. Akar masalah: `_change`/`_shortfall`
getter (dan tombol "Uang Pas" + filter nominal cepat) di
`_CashKeypadSheetState` masih pakai `widget.total` mentah (item susulan
saja), belum ikut disesuaikan saat `existingShortfall` ditambahkan
sesi/commit sebelumnya (`765734e`). Fix: getter baru `_effectiveTotal`
dipakai di SEMUA titik kalkulasi kembalian/tombol/quick-amount di sheet
itu. **Pelajaran**: nambah field baru (`existingShortfall`) ke widget yang
sudah punya logika kalkulasi established (_change/_shortfall) butuh audit
SEMUA titik yang baca field lama (`widget.total`) yang relevan dgn
kalkulasi, bukan cuma titik DISPLAY barunya sendiri — kelas bug yang sama
persis dgn kasus "Dibayar" yang kelewat waktu fix Sisa Tagihan (`87cdaf0`).

**Bug susulan langsung setelah PR #7 di-merge (`87cdaf0`):** user bandingkan
lagi dengan app kompetitor — "Sisa Tagihan" sudah cocok (5.000=5.000), TAPI
baris **"Dibayar"** di Ringkasan beda (The POS: Rp 60.000 mentah, app
pembanding: Rp 55.000 bersih). Akar masalah lanjutan dari fix sebelumnya:
saya sudah benarkan "Sisa Tagihan" jadi bersih tapi LUPA baris "Dibayar" di
ATASNYA (satu card yang sama) masih baca `tx.paid` mentah — jadi Total
(60.000) != Dibayar (60.000) + Sisa (5.000) = 65.000, tidak konsisten
secara matematika DALAM SATU CARD YANG SAMA. Fix: helper baru
`netPaidDisplay()` (pasangan `netRemainingOwed()`, `paid - Σ changeGiven`),
dipakai HANYA di baris "Dibayar" Ringkasan on-screen — struk cetak/gambar
(`_ReceiptPaper`, `printer_service.dart`) SENGAJA tidak disentuh (pasangan
"Bayar../Kembali" di situ ikut konvensi cetak berbeda, sudah dikonfirmasi
sebelumnya jangan diutak-atik). **Pelajaran**: kalau ada baris angka lain
yang SATU CARD dengan baris yang baru diperbaiki, cek juga apa baris itu
masih pakai basis lama (mentah) — user akan langsung notice kalau
angka-angka di satu layar yang sama tidak "nyambung" secara matematika,
walau masing-masing baris technically "benar" sendiri-sendiri.

**Pola PR/merge sepanjang sesi ini:** user berkali-kali minta "merge
langsung" tiap ada batch perubahan baru. **PR #4** (fitur Poin 1-3 awal) →
merge `b477b03`. **PR #5** (cabut flag eksperimental Tempel Pesanan) →
merge `79241db`. **PR #6** (fix checkbox kalkulator tidak merespons,
`c3e975a`) → merge `592442d`. Semua pakai merge biasa (bukan squash) supaya
hash commit individual match CHANGELOG.md. Begitu satu PR merged/closed,
commit susulan di branch yang sama BUTUH PR baru (PR lama tidak reopen
otomatis walau nama branch sama) — pola ini konsisten berulang, jangan
kaget kalau perlu bikin PR #7, #8, dst untuk commit-commit berikutnya di
branch `claude/project-gaps-incomplete-wpgdp8`.

**Bug baru dilaporkan user SETELAH PR #6 (screenshot dibandingkan dengan
app kompetitor):** "Sisa Tagihan" di struk understated (Rp 16.800,
seharusnya Rp 18.100) saat kembalian yang sudah pernah diberikan (Rp 1.300)
dipakai ulang sbg pembayaran item tambahan (persis skenario Poin 1 yang baru
dibangun). **Akar masalah**: `paid` (Σ semua TransactionPayments.amount)
menghitung uang yang sama 2× — masuk lagi sbg "pembayaran baru" tanpa
pernah dikurangi saat keluar sbg kembalian sebelumnya. Investigasi lebih
lanjut menemukan pola bug yang SAMA berpotensi ada di BANYAK tempat lain
(Buku Hutang, Tutup Kasir, printer_service.dart, transaksi_tab.dart,
tx_history_sheet.dart, merged_receipt_screen.dart, settleMergedDebt) — user
diberi 2 pertanyaan lewat poll (scope mana yang mau difix + tx.paid
diredefinisi net vs ditambal terpisah), user awalnya pilih "redefinisi
tx.paid jadi net di satu sumber", TAPI saya temukan risiko baru saat mau
eksekusi: itu akan MERUSAK pasangan "Bayar../Kembali" di struk cetak (yang
assumsikan `paid` = uang mentah yang diserahkan, dipakai di SEMUA transaksi
tunai berkembalian, bukan cuma kasus reuse) — poll susulan untuk
konfirmasi ulang di-**dismiss** oleh user (user minta penjelasan gamblang
dulu, bukan langsung pilih). Setelah dijelaskan ulang dengan analogi
konkret, user pilih **Opsi 1: `tx.paid` TETAP mentah/gross (tidak diubah
maknanya — aman utk struk cetak), tambah hitungan "net" TERPISAH khusus di
titik yang butuh "sisa tagihan yang beneran"** — bukan redefinisi di satu
sumber. Dieksekusi (`19e679d`, 12 Juli):
- Status (`kurang_bayar`/`lunas`) di `_reconcileTransactionTotals` &
  `addPaymentToTransaction` dihitung dari `paid - Σ changeGiven`
  (`netPaidForStatus`), BUKAN `paid` mentah — `paid`/`changeAmount` yang
  TERSIMPAN tidak disentuh sama sekali.
- `receipt_screen.dart`: helper baru `netRemainingOwed(tx, payments)` = `total
  - paid + Σ changeGiven` (clamp ≥0), dipakai di 3 tempat: Ringkasan struk
  ("Sisa Tagihan"), prefill dialog Tambah Bayar, `_ReceiptPaper` (struk
  cetak/gambar, "Sisa hutang"). Semua dari data yang SUDAH dimuat
  (`_payments`/`payments`), tanpa query tambahan.
- **SENGAJA TIDAK disentuh** (scope dipilih user via poll, bukan
  "sapu bersih"): Buku Hutang, `settleMergedDebt`, Tutup Kasir (kas
  sistem — malah temuan LEBIH LUAS, kemungkinan overstated bahkan tanpa
  reuse sama sekali, kategori bug beda & belum dikonfirmasi user),
  `printer_service.dart`, `transaksi_tab.dart`, `tx_history_sheet.dart`,
  `merged_receipt_screen.dart`. **Detail lengkap + kenapa masing-masing
  ditunda ada di PLAN.md Item 23** — cek situ dulu kalau ada laporan bug
  serupa dari salah satu layar itu, kemungkinan besar akar masalahnya sama
  persis, tinggal terapkan pola `netRemainingOwed()`-style.

**Bug ditemukan user SETELAH PR #4 di-merge (`c3e975a`):** centang "Pakai
kembalian" di kalkulator bayar Tambah Belanjaan (fitur baru Poin 1 sesi ini)
tidak merespons tap sama sekali. Akar masalah: `_CashKeypadSheet` dibuka
lewat `showModalBottomSheet`, yang builder-nya CUMA dievaluasi SEKALI saat
sheet dibuka — `setState()` di parent (`_PaymentScreenState`, dipanggil dari
`_toggleUnclaimedChangeTaken` setelah tulis DB sukses) TIDAK memicu rebuild
sheet yang sudah terbuka. `Checkbox` di sheet baca `widget.unclaimedChangeTaken`
langsung dari prop, yang beku di nilai saat sheet dibuka (selalu `false`) —
jadi tulis-DB sukses tapi tampilan checkbox tidak pernah berubah, kelihatan
seperti tidak merespons. **Pelajaran umum**: pola ini (baca state langsung
dari `widget.xxx` di dalam sheet yang dibuka via `showModalBottomSheet`/
`showDialog`) rawan terulang untuk fitur interaktif APAPUN di dalam sheet
serupa — kalau state itu bisa berubah SETELAH sheet dibuka (baik dari
callback internal sheet sendiri atau dari luar), sheet butuh state LOKAL
sendiri (pola `late T _x = widget.x;` + `setState` lokal saat berubah, PERSIS
seperti `_tendered` yang sudah lebih dulu ada di `_CashKeypadSheetState`) —
jangan baca `widget.xxx` langsung di `build()` untuk nilai yang berubah
sesudah sheet terbuka. Fix + test diperkuat dengan assert visual
`Checkbox.value` (bukan cuma DB) supaya kelas bug ini tidak lolos lagi kalau
terulang di fitur lain.

**Flag "Eksperimental" tersisa cuma 1**: "Import dari Griyo POS" (Pengaturan).
Tempel Pesanan (bagian Katalog Pesanan) sudah dicabut sesi ini menyusul
Katalog Pesanan HTML yang sudah dicabut duluan — jadi seluruh alur Katalog
Pesanan (generate → kirim WA → tempel balik) sekarang resmi, tidak ada lagi
badge eksperimental di dalamnya.

**Sesi ini — 3 proposal fitur baru dari user, didiskusikan "jangan coding
dulu" lalu disepakati via Q&A panjang, ketiganya SELESAI dieksekusi:**
1. **Poin 1 (kembalian dari Tambah Belanjaan, nota SAMA saja — lintas
   nota/gabungan di-pending user) — SELESAI** (`d77e81e`), tapi scope-nya
   BERUBAH dari proposal awal setelah diskusi lanjutan dengan user. Awalnya
   direncanakan sebagai "reuse otomatis" (kembalian lama dipakai sebagai
   kredit, sistem yang mengurangi) — ini mentok di tegangan desain: `changeGiven`
   per baris pembayaran sengaja immutable-historis (lihat Poin 2), tapi
   reuse otomatis perlu MENGURANGI baris lama, bertentangan langsung. User
   lalu mengusulkan pendekatan yang jauh lebih sederhana dan sama sekali
   menghindari tegangan itu: **jangan otomatis sama sekali** — cukup
   TAMPILKAN info "kembalian terakhir yang belum diambil" di kalkulator
   bayar Tambah Belanjaan, kasir tetap INPUT MANUAL nominal yang diterima
   (disimulasikan sebagai kejadian pembayaran baru yang sungguhan — bukan
   kredit otomatis). Ini menghilangkan tegangan sepenuhnya karena TIDAK ADA
   mutasi data lama sama sekali: baris lama (`pay1`) tetap utuh selamanya,
   baris baru (`pay2`, dari pembayaran manual kasir) dihitung normal lewat
   `_computePaymentChangeGiven()` yang SUDAH ADA dari Poin 2 — tidak ada
   kode DB baru. User lalu menambahkan 1 penyempurnaan: di samping info
   nominal itu, ada CENTANG "Pakai kembalian" yang fungsinya SAMA PERSIS
   dengan centang di Ringkasan struk (`_toggleChangeTaken`) — supaya kasir
   tidak perlu buka struk dulu untuk menandai kembalian lama sebagai
   "dipakai/diambil" (mengurangi risiko lupa saat rush hour). Centang ini
   PURE UPDATE (bukan INSERT) ke baris yang sama, jadi klik berkali-kali
   tidak menghasilkan riwayat baru — cuma menimpa nilai boolean terakhir
   (dikonfirmasi eksplisit ke user saat ditanya). Centang & nominal manual
   di kalkulator SENGAJA DIBIARKAN LEPAS/independen (tidak saling
   memvalidasi) — keputusan eksplisit user. Diimplementasi di
   `_CashKeypadSheet` (`payment_screen.dart`), murni tambahan UI + 1 query
   `SELECT ... ORDER BY paid_at DESC LIMIT 1` di `_load()`. Sekalian:
   user minta highlight nominal "Total" di header kalkulator (sebelumnya
   teks kecil rata, "kayak NPC cameo") — dibuat sebagian bold+besar via
   `Text.rich`, pola yang sama diterapkan ke info kembalian baru. Test
   helper `test/helpers/pump_app.dart` diperluas dengan parameter opsional
   `initialPrefs` (seed SharedPreferences sebelum render, dibutuhkan untuk
   seed keranjang cart Tambah Belanjaan di widget test — parameter opsional
   dengan default `{}`, tidak mengubah perilaku test lain yang sudah ada).
2. **Poin 2 (kembalian per-baris pembayaran + centang per-baris di Riwayat
   Pembayaran) — SELESAI** (`399a742`, `5759c18`). Desain final (kesepakatan
   user via Q&A): Ringkasan nota SELALU tampilkan kembalian pembayaran
   TERAKHIR saja (bukan akumulatif — kalau akumulatif, centang kembalian
   jadi tidak ada gunanya). Card Riwayat Pembayaran tampilkan kembalian tiap
   baris yang punya kembalian sendiri (termasuk pembayaran PERTAMA kalau
   nota dilunasi belakangan), dengan centang "sudah diambil" per baris —
   TANPA timestamp terpisah (pakai timestamp `paidAt` milik baris itu,
   karena kembalian & pembayaran dianggap satu momen). Skema baru:
   `TransactionPayments.changeGiven`/`.changeTaken` (schemaVersion 13, kolom
   ditambah via migrasi, bukan tabel baru). Formula kunci penghindar
   dobel-hitung ada di `_computePaymentChangeGiven()`
   (`app_database.dart`): `thisChange = (priorPaid + newPaymentAmount −
   currentTotal) − priorChangeSum`, lalu di-clamp ke 0 kalau negatif. Ada
   fallback ke `transactions.paid` kalau belum ada baris `TransactionPayments`
   sama sekali (nota legacy/pre-backfill) — pola sama seperti
   `_reconcileTransactionTotals`. Kasus khusus: sisa lebih di
   `settleMergedDebt` (pelunasan hutang gabungan beberapa nota) sekarang ikut
   tersimpan di baris pembayaran nota TERAKHIR (sebelumnya cuma tampil
   sekali di SnackBar, TIDAK PERNAH tersimpan di mana pun — temuan bug nyata
   selama analisis, bukan cuma penyempurnaan).
3. **Poin 3 (Buku Hutang: lihat nota mana saja yang belum lunas per
   pelanggan) — SELESAI** (`6173b57`). User pilih extend modal detail
   pelanggan yang SUDAH ADA (bukan route/layar baru) — `getUnpaidTxDetails()`
   query baru + `DraggableScrollableSheet` di `hutang_tab.dart`, tap nota
   langsung `context.push('/kasir/struk/${tx.id}')`.

**Bug tersembunyi ditemukan selama sesi ini (di luar 3 poin di atas, murni
dari widget test baru):**
- **2 overflow RenderFlex PRE-EXISTING di `hutang_tab.dart`** (baris ringkasan
  jumlah pelanggan+total, & baris total-hutang di modal detail) — baru
  ketahuan sekarang karena ini PERTAMA KALINYA `HutangTab` dapat widget test
  sama sekali. Sudah diperbaiki sekalian (`Expanded`+ellipsis, pola yang
  sama dipakai berkali-kali sesi-sesi sebelumnya).
- **`formatRupiah` pakai non-breaking space (U+00A0)**, bukan spasi biasa,
  antara "Rp" dan angka — literal string test `find.text('Rp 5.000')`
  gagal match walau teks yang sama persis tampil di layar (`find.text`
  0 widget padahal dump manual `Text.data` menunjukkan teks itu render 2x).
  Butuh ~1 jam debug (test debug DB-level vs widget-level dump vs re-run
  isolasi file, semua "membuktikan" data benar sebelum akhirnya ketemu lewat
  `codeUnits` dump: `160` bukan `32` di posisi spasi). **Sudah dicatat di
  CLAUDE.md §Gotcha** supaya tidak terulang — pakai `formatRupiah(x)` untuk
  bangun string expected di test, jangan hardcode literal "Rp X.XXX".
  Pelajaran tambahan: `findsWidgets` (>=1) terlalu longgar untuk revert-verify
  saat ada 2 lokasi render yang sengaja duplikat (Ringkasan + Riwayat
  Pembayaran) — harus `findsNWidgets(2)` biar revert-verify benar-benar bisa
  gagal saat salah satu lokasi sengaja dimatikan untuk pembuktian.

---

## Sesi sebelumnya (11 Juli, sebelum sesi kembalian di atas) — Griyo POS import
User upload sampel CSV export Griyo POS untuk migrasi
data toko lama → ditemukan & diperbaiki bug import CSV (`63d0f2d`): parser
cuma kenal pemisah `,` (Griyo pakai `;`), alias kolom tidak cocok header asli
Griyo ("Produk"/"Kode Produk"/"Grup Produk"/"Harga Jual"/"Harga Pokok"), dan
kolom Satuan/Grup Produk berisi ID legacy MENTAH (bukan nama teks) yang
sebenarnya sudah match `_kDefaultUnitTypes`/grup 3-20 di `_seedDefaults`
(app_database.dart) tapi importer tidak pernah memakainya sebagai ID
langsung. Keputusan desain: import tetap FLAT (user pilih ini, bukan
auto-gabung baris nama-sama-satuan-beda jadi 1 produk multi-satuan) karena
CSV Griyo tidak menyertakan rasio konversi antar satuan — digabung manual
lewat Edit Produk bila perlu, dibantu counter `sameNameDifferentUnit` baru
di hasil import. Behavior import: UPSERT per baris, BUKAN overwrite/replace
katalog — baris yang cocok (barcode→SKU→nama+satuan) ke produk lama HANYA
update harga (stok tidak disentuh sama sekali di re-import), baris baru
di-append sebagai produk baru (opening stock ledger dari kolom Stok), dan
produk lama yang TIDAK ada di file CSV dibiarkan utuh (tidak dihapus). Lalu
dirapikan jadi fitur bernama "Import dari Griyo POS", diflag Eksperimental
(`CsvImportScreen(griyoMode: true)`, route `/pengaturan/import-griyo`) —
dan flag Eksperimental yang lama di Katalog Pesanan (HTML,
`order_share_screen.dart`) DICABUT karena sudah jadi fitur native (dipindah
dari section Eksperimental ke Sinkronisasi di `pengaturan_screen.dart`).

**Bug susulan ditemukan & diperbaiki (`e4baa92`):** user lapor "import dari
Griyo, tab Produk normal, tapi Katalog Pesanan HTML kosong". Akar masalah:
`csv_import_service.dart` membuat `ProductUnits` TANPA `isBaseUnit: true`
(defaultnya `false`) — beda dari tambah produk manual yang selalu set true.
`OrderPageService._buildCatalogJson()` mensyaratkan ada unit `isBaseUnit`
TANPA fallback (beda dari ~10 titik lain di app — kasir_screen,
produk_form_screen, item_entry_sheet, paste_order_sheet, `_baseUnitOf()`,
`_matchExistingUnit()` — yang semua pakai pola `?? units.first`), jadi
produk hasil import selalu dilewati diam-diam dari katalog HTML. Fix 2
lapis: (1) importer sekarang set `isBaseUnit: true` (akar masalah), (2)
`order_page_service.dart` ditambah fallback yang sama seperti pola di
seluruh app (juga otomatis memperbaiki produk lama yang sudah kadung
ter-import sebelum fix, tanpa migrasi data). **Pelajaran untuk importer
baru (mis. Item 4, import pelanggan):** field yang di-skip saat insert
lewat importer bisa punya default DB yang diam-diam melanggar asumsi kode
lain — cek SEMUA titik baca sebelum menganggap importer beres, bukan cuma
"tampil di 1 layar" saja.

**Item 4 (import pelanggan dari Griyo POS) — ANALISIS SELESAI, implementasi
BELUM dimulai.** User upload `Pelanggan.xlsx` (493 baris: Pelanggan, Alamat,
Telepon, Barcode, Keterangan, Poin, Piutang — semua kolom TEXT termasuk
angka, minimal 1 Piutang dalam notasi ilmiah butuh `double.tryParse` bukan
`int.tryParse`). Keputusan user: Piutang lama TIDAK dibawa (mulai nol
bersih — alasan: `outstandingDebt` cuma cache, Buku Hutang hitung fresh
dari transaksi, isi field itu langsung bikin 2 tempat beda angka); baris
"-" (bucket piutang tanpa nama, ~Rp1,2jt) DILEWATI. Detail lengkap +
keputusan kecil sisa (nama duplikat, whitespace) ada di PLAN.md Item 4.

**2 fix susulan (user lapor setelah pakai fitur import Griyo, `c8a79f1` +
`9e52f61`):**
1. Tombol "Harga lain" di `item_entry_sheet.dart` sekarang menampilkan nama
   opsi harga yang aktif (mis. "Eceran") — sebelumnya selalu label generik
   "Harga lain (N)" walau user sudah memilih opsi tertentu. Derived getter
   `_selectedPriceLabel` (cocokkan `_price` ke `_priceOptions()`), HANYA
   aktif kalau `_priceOverridden` (supaya default/harga-dasar tetap tampil
   label generik, tidak breaking existing test).
2. **Bug nyata ditemukan**: owner ikut ter-block saat setting global
   "Izinkan Stok Minus" OFF — sama seperti kasir, TIDAK ADA bypass khusus
   owner (beda dari semua izin lain: override harga, input stok, dst yang
   semuanya tanpa syarat untuk owner). Root cause di
   `payment_screen.dart::_confirm()` C-5 check. Fix: extract jadi
   `resolveAllowNegativeStock(db, device)` (top-level function, testable
   Tier 1 tanpa drive seluruh widget PaymentScreen) + tambah
   `if (device.isOwner) return true;` unconditional. **Tidak ada test
   sebelumnya untuk fitur stok-minus ini sama sekali** — baru dibuat
   `test/allow_negative_stock_test.dart`.
3. **User tanya balik "toggle itu dulu ada, kok sekarang tidak?"** — dicek
   `git log`, ternyata dulu toggle "Izinkan Stok Minus" memang ada langsung
   di halaman utama Pengaturan, lalu di komit `1b292eb` (SEBELUM sesi ini)
   dipindah masuk ke dalam Izin Kasir (kurang terlihat). Bukan bug kode,
   murni penempatan UI. User minta dibuatkan **entri terpisah lagi** (bukan
   dikembalikan sebagai bagian Izin Kasir, bukan juga cuma taruh di kedua
   tempat) → `cb87507`: dipindah balik jadi `SwitchListTile` sendiri di
   `pengaturan_screen.dart` (section "Toko", owner-only), dicabut total
   dari `kasir_permissions_screen.dart`. Provider `_allowNegativeStockProvider`
   ikut pindah lokasi (masing-masing file private, tidak dibagi)._
**Gotcha locale:** app TIDAK memanggil `initializeDateFormatting` — jangan
pakai `DateFormat(..., 'id')` (throw LocaleDataException). Format nama hari/
bulan Indonesia MANUAL (lihat `expenses_screen.dart` `_idDays`/`_idMonths`).

## Lingkungan sesi ini (PENTING untuk sesi lanjutan)
Flutter TIDAK terpasang default di environment ini — dipasang manual ke
`/tmp/flutter` (versi **3.24.5 stable**, samakan dengan CI `build-apk.yml`).
Jalankan `export PATH="/tmp/flutter/bin:$PATH"` tiap sesi baru, `flutter pub get`,
lalu `flutter analyze` + `flutter test`. Kalau `/tmp/flutter` sudah hilang
(container di-reclaim), unduh ulang:
`curl -sSL -o /tmp/flutter.tar.xz "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz" && tar xf /tmp/flutter.tar.xz -C /tmp`.
Baseline sebelum eksekusi: 141 test hijau; setelah Item 22: 149 hijau; setelah
sesi kembalian per-pembayaran + Tambah Belanjaan (lihat atas): 213 hijau.
Google Fonts butuh binding aktif — di test, JANGAN panggil `AppTheme.light()/dark()`
di badan `main()` (fase collection); bangun theme DI DALAM `testWidgets`
(lihat `test/chip_and_banner_color_test.dart`).
**Gotcha widget test + drift StreamProvider yang MEMUTASI db:** saat provider
di-dispose di akhir test, drift `StreamQueryStore.markAsClosed` menjadwalkan
Timer 0ms → binding lapor "Timer still pending". Fix: sebelum test selesai,
unmount eksplisit lalu drain — `await tester.pumpWidget(const SizedBox()); await
tester.pump(Duration(milliseconds: 10));` (lihat helper `drain` di
`test/payment_method_edit_delete_test.dart`).
**Overflow PRE-EXISTING (bukan bug baru):** cart bar `kasir_screen.dart:2500`
(Row, ~8.8px) & kartu antrian `:3061` (Column, ~8px) overflow pada lebar 430px
— muncul saat keranjang/panel antrian berisi. Kandidat perbaikan layout
tersendiri; test Item 18 sengaja meng-konsumsi exception ini.

---

## Di Mana Kita Sekarang

### Sesi sebelumnya — eksekusi backlog Item 9-22 (12 dari 13 SELESAI)
User menyetujui eksekusi seluruh saran fitur + bug + proposal (Item 9-22 di
PLAN.md) dan mendelegasikan penuh ("Anda yang lebih tahu"). Dieksekusi 12 item
berturut-turut, tiap item: kode + test berjenjang + **revert-verify** + full
suite hijau + `flutter analyze` bersih + docs, satu commit per item, push ke
`claude/project-gaps-incomplete-wpgdp8`. Baseline 141 test → **184 test hijau**.

Selesai (lihat CHANGELOG untuk hash): **22** warna chip terpilih (fix tema
sistemik `chipTheme.labelStyle` state-aware, kena 8 titik) + banner sukses
hijau/gagal merah • **10** metode bayar pelunasan hutang (dialog reusable
`debt_payment_dialog.dart`) • **20** tombol edit produk di modal kasir
(owner/asisten) • **14** edit/hapus metode bayar • **9** pengeluaran + Laba
Bersih (`ExpensesScreen`; Laba Bersih = Laba Kotor − daily_expense −
change_given) • **12** Buku Hutang (tab Laporan ke-5) • **18** beralih pesanan
tertahan auto-hold (tanpa dialog "Ganti Keranjang") • **16** atribusi varian
per-satuan (`CartItem.parentProductUnitId` + `belongsToParent`, cascade delete)
+ fix tombol minus • **19** Harga Lain/grosir → dropdown di field Harga •
**11** stok menipis (`ProductUnits.minStock`, **schemaVersion 11**) badge+filter
• **13** pengingat backup (cek saat app dibuka, `BackupReminder`) • **15**
Tutup Kasir harian (tabel `cash_closings`, **schemaVersion 12**).

**schemaVersion 12** (Item 15, sesi ini): v11 addColumn `product_units.
min_stock` (tanpa guard `from>=X` — product_units cuma di base schema); v12
createTable `cash_closings`. **schemaVersion 13** (sesi kembalian, lihat
bagian atas): addColumn `transaction_payments.change_given` +
`.change_taken`. Fixture migrasi test v7-v10 ditambah tabel `product_units`
+ `transaction_payments` minimal, assert versi akhir 13.

### ⚠️ MENGGANTUNG — Item 21+17 (sync) BELUM dikerjakan (sengaja ditunda)
Satu-satunya item backlog yang belum: **Item 21** (angkat state sync ke
provider global + banner persisten di shell + lepaskan lifecycle host dari
`SyncScreen.dispose` yang kini `stopHost()` total) & **Item 17** (persist
`_pendingQueue` in-memory ke DB agar selamat restart, lalu majukan watermark
upload). **Sengaja ditunda ke sesi fokus** karena menyentuh infrastruktur sync
multi-device yang KRITIS — bagian "majukan watermark upload" berisiko
kehilangan data diam-diam bila salah (persis yang dicegah full-dump sekarang),
dan butuh test round-trip HTTP asli (HttpOverrides escape-hatch, lihat
CLAUDE.md §Metode Test level 3). Detail lengkap masih di PLAN.md Item 17 & 21.

**Catatan lingkungan sesi ini:** binary `flutter` ada di `/tmp/flutter/bin/flutter`
di environment ini (BUKAN `/opt/flutter/bin` seperti disebut CLAUDE.md — itu
mungkin beda per environment/container, cek `which flutter`/`find` dulu kalau
command CLAUDE.md gagal). Playwright global ada di `/opt/node22/lib/node_modules`
(`NODE_PATH` perlu di-set manual), Chromium executable di
`/opt/pw-browsers/chromium-1194/chrome-linux/chrome` (bukan `chromium/chrome-linux/chrome`
seperti disebut di system prompt — versi folder berubah, cek `find /opt/pw-browsers -iname "*chrome*"`
kalau path itu gagal).

### Sesi sebelumnya (commit `50752cd`) — poles layout topbar kasir
Lihat CHANGELOG untuk detail commit. Ringkasan: lebar collapsed field cari
dihitung presisi dari lebar tombol nyata (bukan hardcode), tinggi Stack
topbar diperbesar supaya label 2 baris tidak kepepet divider, tap
"+"/badan-produk saat search aktif tidak lagi collapse field.

### Fitur eksperimental Katalog Pesanan (branch `claude/order-html-eksperimental`)
Lengkap dua fase (generate HTML → kirim WA → pelanggan pilih barang → kasir
tempel balik ke keranjang), ditambah optimasi performa sesi ini (lihat di
atas). Detail arsitektur lengkap ada di `lib/core/services/order_page_service.dart`
(generator) & `lib/core/services/order_parser_service.dart` (parser).

### Yang SENGAJA belum dibangun (deferred, bukan lupa)
- Hosting "link hidup" (GitHub Pages dkk) untuk Katalog Pesanan — user pilih
  TIDAK sekarang (kirim manual via WA).
- UX varian (arrow-tap + auto-expand-on-search) hanya ada di HTML generated,
  belum diseragamkan ke kasir utama (yang masih pakai long-press).
- Belum ada PR untuk branch `claude/order-html-eksperimental` — menunggu
  instruksi user.
- Item 8 PLAN.md (bawa UI pilih-harga ItemEntrySheet ke HTML) — masih
  diskusi kelayakan, belum ada keputusan scope.

## Ringkasan Sesi Audit Sebelumnya (masih berlaku, tidak diulang detail)
14 bug hasil audit kode menyeluruh sudah diperbaiki & dirilis sebagai
v2.1.1+3 (lihat CHANGELOG). PR #2 sudah di-merge ke `main`.

## Temuan yang SENGAJA Belum Diperbaiki (kandidat diskusi, dari audit)
- **Multi-satuan + varian bercampur**: invariant `storedQty induk = base +
  Σvarian` ambigu bila satu produk punya ≥2 baris satuan non-varian di
  keranjang. Butuh refactor atribusi varian per-baris — jangan disentuh
  tanpa keputusan user.
- Tombol minus di kartu produk (`_decrementProduct`) selalu mengurangi baris
  satuan PERTAMA bila produk ada di keranjang dengan >1 satuan.
- **Upload sync klien→host masih full-dump** (sengaja — antrian approval
  host (`_pendingQueue`) hanya di memori, hilang bila host restart sebelum
  approve; full-dump adalah pengaman agar data tak hilang permanen). Bukan
  "sync satu arah tanpa ACK" — sync SUDAH dua arah & host SUDAH punya review
  manual. Fix presisi = persist `_pendingQueue` ke DB (pola `held_orders`)
  lalu majukan watermark upload. Detail di PLAN.md Item 17.
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
  `Mockup.zip` & `Contoh_Dataset.rar` yang masih ada & dipakai aktif untuk
  perencanaan migrasi data (lihat PLAN.md Item 3-5).
- Ekspor pakai `FilePicker.saveFile`, bukan `Printing.sharePdf`.
- Katalog Pesanan (eksperimental): tanpa hosting, kasir utama tidak
  disentuh (hanya tombol baru ditambah).
- Harga Lain (`alt_prices`) TIDAK pernah dipilih otomatis oleh
  `PriceService.resolvePrice` — murni manual/tap. Urutan tampilnya sekarang
  bisa diatur user via drag-handle di form Produk (`sortOrder` kolom).
- Claude TIDAK punya akses berkelanjutan ke database toko user (offline-first,
  terenkripsi SQLCipher) — alur migrasi data dari dataset lama selalu:
  user kirim data mentah → Claude olah format → user import sendiri lewat
  fitur di app. Lihat "Konteks" di PLAN.md.

## Menggantung / Kandidat Berikutnya
- **PLAN.md Item 3** (konversi format `Products.csv` + fix rasio multi-satuan
  hilang, 31% katalog terdampak) — prioritas TINGGI, harus selesai SEBELUM
  data produk diimpor ke DB live. Menunggu user siap kirim/konfirmasi data
  final.
- **PLAN.md Item 4** (importer pelanggan + poin loyalty, fitur baru) —
  menunggu user jawab 3 pertanyaan desain (overwrite vs delta poin, kunci
  pencocokan, penanganan nama kembar).
- **PLAN.md Item 5** (import riwayat transaksi dari dataset lama) — setelah
  Item 3 selesai, dan setelah user konfirmasi cakupan tanggal file
  `Transaksi ...xlsx` yang tersedia.
- **PLAN.md Item 8** (bawa UI pilih-harga ke HTML Katalog) — menunggu
  keputusan user soal trade-off kompleksitas vs manfaat.
- Saran fitur audit di atas menunggu keputusan user.
- Belum ada PR untuk branch `claude/order-html-eksperimental`.

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
- Untuk rencana kerja yang didiskusikan tapi belum dieksekusi ("jangan
  coding dulu"): masukkan ke PLAN.md secara komprehensif, jangan cuma
  disimpan di riwayat chat.
